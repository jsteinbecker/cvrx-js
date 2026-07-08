// RxNormService.swift
// Mirrors every async function in the JS: seeds, gatherConcepts, NDC pooling,
// cross-population, NDC name lookup.

import Foundation

// MARK: - Base fetch

private func rxFetch<T: Decodable>(_ url: URL, as type: T.Type) async throws -> T {
    var req = URLRequest(url: url)
    req.setValue("application/json", forHTTPHeaderField: "Accept")
    let (data, resp) = try await URLSession.shared.data(for: req)
    guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
        throw URLError(.badServerResponse)
    }
    guard !data.isEmpty else { throw URLError(.zeroByteResource) }
    return try JSONDecoder().decode(type, from: data)
}

private let base = "https://rxnav.nlm.nih.gov/REST"

// MARK: - In-memory cache (mirrors JS `cache` object)

actor APICache {
    static let shared = APICache()
    private var store: [String: Any] = [:]

    func get<T>(_ key: String) -> T? { store[key] as? T }
    func set<T>(_ key: String, value: T) { store[key] = value }
    func clear() { store.removeAll() }
}

private func cached<T: Sendable>(_ key: String, produce: @escaping () async throws -> T) async throws -> T {
    if let v: T = await APICache.shared.get(key) { return v }
    let v = try await produce()
    await APICache.shared.set(key, value: v)
    return v
}

// MARK: - Seed resolution  (findRxcuiSeeds + approximateSeeds)

nonisolated private struct RxcuiResponse: Decodable {
    nonisolated struct IdGroup: Decodable { var rxnormId: [String]? }
    var idGroup: IdGroup?
}

/// Exact/normalized match — mirrors `findRxcuiSeeds`.
func findRxcuiSeeds(_ q: String) async throws -> [String] {
    let enc = q.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? q
    let url  = URL(string: "\(base)/rxcui.json?name=\(enc)&search=1&allsrc=1")!
    let resp = try await rxFetch(url, as: RxcuiResponse.self)
    return resp.idGroup?.rxnormId ?? []
}

nonisolated private struct ApproxResponse: Decodable {
    nonisolated struct Group: Decodable {
        nonisolated struct Candidate: Decodable { var rxcui: String? }
        var candidate: [Candidate]?
    }
    var approximateGroup: Group?
}

/// Fuzzy/approximate fallback — mirrors `approximateSeeds`.
func approximateSeeds(_ q: String, maxEntries: Int = 20) async throws -> [String] {
    let enc = q.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? q
    let url  = URL(string: "\(base)/approximateTerm.json?term=\(enc)&maxEntries=\(maxEntries)&option=1")!
    let resp = try await rxFetch(url, as: ApproxResponse.self)
    var seen = Set<String>(); var out: [String] = []
    for c in resp.approximateGroup?.candidate ?? [] {
        if let r = c.rxcui, seen.insert(r).inserted { out.append(r) }
    }
    return out
}

// MARK: - Related concepts  (gatherConcepts)

nonisolated private struct RelatedResponse: Decodable {
    nonisolated struct RelatedGroup: Decodable {
        nonisolated struct ConceptGroup: Decodable {
            nonisolated struct ConceptProperty: Decodable {
                var rxcui: String
                var name: String
            }
            var tty: String
            var conceptProperties: [ConceptProperty]?
        }
        var conceptGroup: [ConceptGroup]?
    }
    var relatedGroup: RelatedGroup?
}

/// Fetch related concepts for a set of seed RxCUIs — mirrors `gatherConcepts`.
func gatherConcepts(
    seeds: [String],
    tty1: Set<TTY>,
    tty2: Set<TTY>
) async throws -> [RxConcept] {
    let ttyNeedsTraversal: Set<TTY> = [.SCDG, .SBDG, .SCDGP, .SCDF, .SBDF, .SCDFP, .SBDFP]
    let tty1Param = tty1.map(\.rawValue).joined(separator: "+")
    let tty2Param = tty2.map(\.rawValue).joined(separator: "+")

    var allConcepts: [RxConcept] = []
    let lock = NSLock()

    try await withThrowingTaskGroup(of: [RxConcept].self) { group in
        for seed in seeds.prefix(8) {
            group.addTask {
                var batch: [RxConcept] = []
                async let r1 = fetchRelated(rxcui: seed, ttyParam: tty1Param, expand: "psn")
                async let r2 = fetchRelated(rxcui: seed, ttyParam: tty2Param, expand: "")
                let (rel1, rel2) = try await (r1, r2)
                for c in rel1 {
                    guard let tty = TTY(rawValue: c.tty) else { continue }
                    batch.append(RxConcept(rxcui: c.rxcui, name: c.name, tty: tty,
                                           traversal: ttyNeedsTraversal.contains(tty)))
                }
                for c in rel2 {
                    guard let tty = TTY(rawValue: c.tty) else { continue }
                    batch.append(RxConcept(rxcui: c.rxcui, name: c.name, tty: tty, traversal: false))
                }
                return batch
            }
        }
        for try await batch in group {
            lock.withLock { allConcepts += batch }
        }
    }

    // Deduplicate and sort
    var seen = Set<String>()
    var unique: [RxConcept] = []
    for c in allConcepts where seen.insert(c.rxcui).inserted { unique.append(c) }
    unique.sort {
        let o = $0.tty.sortOrder == $1.tty.sortOrder
        return o ? $0.name < $1.name : $0.tty.sortOrder < $1.tty.sortOrder
    }
    return unique
}

private struct RelatedPair { var rxcui: String; var name: String; var tty: String }

private func fetchRelated(rxcui: String, ttyParam: String, expand: String) async throws -> [RelatedPair] {
    guard !ttyParam.isEmpty else { return [] }
    let key = "related:\(rxcui):\(ttyParam):\(expand)"
    return try await cached(key) {
        let exp  = expand.isEmpty ? "" : "&expand=\(expand)"
        let url  = URL(string: "\(base)/rxcui/\(rxcui)/related.json?tty=\(ttyParam)\(exp)")!
        let resp = try await rxFetch(url, as: RelatedResponse.self)
        var out: [RelatedPair] = []
        for g in resp.relatedGroup?.conceptGroup ?? [] {
            for p in g.conceptProperties ?? [] {
                out.append(.init(rxcui: p.rxcui, name: p.name, tty: g.tty))
            }
        }
        return out
    }
}

// MARK: - NDC fetching  (fetchNDCsDirect, fetchSCDsForForm, fetchSCDFsForGroup)

nonisolated private struct NDCResponse: Decodable {
    nonisolated struct NDCGroup: Decodable {
        nonisolated struct NDCList: Decodable { var ndc: [String]? }
        var ndcList: NDCList?
    }
    var ndcGroup: NDCGroup?
}

func fetchNDCsDirect(_ rxcui: String) async throws -> [String] {
    try await cached("ndc:\(rxcui)") {
        let url  = URL(string: "\(base)/rxcui/\(rxcui)/ndcs.json")!
        let resp = try await rxFetch(url, as: NDCResponse.self)
        return resp.ndcGroup?.ndcList?.ndc ?? []
    }
}

func fetchSCDsForForm(_ scdfRxcui: String) async throws -> [RxConcept] {
    try await cached("scdf:\(scdfRxcui)") {
        let pairs = try await fetchRelated(rxcui: scdfRxcui, ttyParam: "SCD+SBD+GPCK+BPCK", expand: "")
        return pairs.compactMap { pair in TTY(rawValue: pair.tty).map { tty in RxConcept(rxcui: pair.rxcui, name: pair.name, tty: tty) } }
    }
}

func fetchSCDFsForGroup(_ scdgRxcui: String) async throws -> [RxConcept] {
    try await cached("scdg:\(scdgRxcui)") {
        let pairs = try await fetchRelated(rxcui: scdgRxcui, ttyParam: "SCDF+SBDF+SCDFP+SBDFP", expand: "")
        return pairs.compactMap { pair in TTY(rawValue: pair.tty).map { tty in RxConcept(rxcui: pair.rxcui, name: pair.name, tty: tty) } }
    }
}

// MARK: - Cross-population  (fetchCrossNDCs, mergeNDCs)

func fetchCrossNDCs(rxcui: String, tty: TTY) async throws -> [String] {
    let crossParam = tty.isClinical ? "SBD+BPCK" : "SCD+GPCK"
    return try await cached("cross:\(rxcui)") {
        let pairs = try await fetchRelated(rxcui: rxcui, ttyParam: crossParam, expand: "")
        let crossNDCs = try await withThrowingTaskGroup(of: [String].self) { grp -> [[String]] in
            for p in pairs { grp.addTask { try await fetchNDCsDirect(p.rxcui) } }
            var all: [[String]] = []
            for try await ndcs in grp { all.append(ndcs) }
            return all
        }
        var seen = Set<String>(); var out: [String] = []
        for n in crossNDCs.flatMap({ $0 }) where seen.insert(n).inserted { out.append(n) }
        return out
    }
}

func mergeNDCs(pairs: [(rxcui: String, tty: TTY)], crossPop: Bool) async throws -> [String] {
    var seen = Set<String>(); var pooled: [String] = []
    func add(_ ns: [String]) { for n in ns where seen.insert(n).inserted { pooled.append(n) } }

    try await withThrowingTaskGroup(of: ([String], [String]).self) { group in
        for pair in pairs {
            group.addTask {
                let own   = (try? await fetchNDCsDirect(pair.rxcui)) ?? []
                let cross = crossPop ? ((try? await fetchCrossNDCs(rxcui: pair.rxcui, tty: pair.tty)) ?? []) : []
                return (own, cross)
            }
        }
        for try await (own, cross) in group {
            add(own)
            if crossPop { add(cross) }
        }
    }
    pooled.sort()
    return pooled
}

// MARK: - NDC pooling  (poolNDCsViaForm, poolNDCsDirect)

func poolNDCsViaForm(concept: RxConcept, crossPop: Bool) async throws -> NDCResult {
    var scdfRxcuis: [String] = []
    if concept.tty.isGroup {
        let scdfs = try await fetchSCDFsForGroup(concept.rxcui)
        scdfRxcuis = scdfs.map(\.rxcui)
    } else if concept.tty.isForm {
        scdfRxcuis = [concept.rxcui]
    }
    guard !scdfRxcuis.isEmpty else { return NDCResult(ndcs: [], path: "no forms found") }

    let scdSets = try await withThrowingTaskGroup(of: [RxConcept].self) { group -> [[RxConcept]] in
        for r in scdfRxcuis { group.addTask { (try? await fetchSCDsForForm(r)) ?? [] } }
        var all: [[RxConcept]] = []
        for try await s in group { all.append(s) }
        return all
    }
    var seenScd = Set<String>(); var allSCDs: [RxConcept] = []
    for scd in scdSets.flatMap({ $0 }) where seenScd.insert(scd.rxcui).inserted && !scd.name.contains(" / ") {
        allSCDs.append(scd)
    }
    guard !allSCDs.isEmpty else { return NDCResult(ndcs: [], path: "\(scdfRxcuis.count) form(s), no SCDs") }

    let ndcs = try await mergeNDCs(pairs: allSCDs.map { ($0.rxcui, $0.tty) }, crossPop: crossPop)
    let path = concept.tty.isGroup
        ? "\(concept.tty.rawValue) → \(scdfRxcuis.count) form(s) → \(allSCDs.count) SCD(s)\(crossPop ? " + branded" : "")"
        : "\(concept.tty.rawValue) → \(allSCDs.count) SCD(s)\(crossPop ? " + branded" : "")"
    return NDCResult(ndcs: ndcs, path: path)
}

func poolNDCsDirect(concept: RxConcept, crossPop: Bool) async throws -> NDCResult {
    let ndcs = try await mergeNDCs(pairs: [(concept.rxcui, concept.tty)], crossPop: crossPop)
    let path = crossPop
        ? "direct + \(concept.tty.isClinical ? "branded" : "generic")"
        : "direct"
    return NDCResult(ndcs: ndcs, path: path)
}

// MARK: - NDC name lookup  (fetchNDCName)

nonisolated private struct NDCStatusResponse: Decodable {
    nonisolated struct NDCStatus: Decodable {
        var conceptName: String?
        var status: String?
        var active: String?
    }
    var ndcStatus: NDCStatus?
}

func fetchNDCInfo(_ ndc: String) async throws -> NDCInfo {
    try await cached("ndcinfo:\(ndc)") {
        let url  = URL(string: "\(base)/ndcstatus.json?ndc=\(ndc)")!
        let resp = try await rxFetch(url, as: NDCStatusResponse.self)
        let s    = resp.ndcStatus
        return NDCInfo(
            ndc: ndc,
            productName: s?.conceptName,
            status: s?.status,
            marketed: s?.active.map { $0 == "YES" }
        )
    }
}

// MARK: - RxMix URL builder

func buildRxMixURL(query: String, tty1: Set<TTY>, tty2: Set<TTY>) -> URL? {
    let t1 = " " + tty1.map(\.rawValue).joined(separator: " ")
    let t2 = " " + tty2.map(\.rawValue).joined(separator: " ")
    let pipeline = """
    rxnorm.findRxcuiByString
    (allsrc:"1",
    search:"1"):idGroup.rxnormId
    rxnorm.getRelatedByType
    (expand:"psn",
    tty:"\(t1)"):relatedGroup.conceptGroup.conceptProperties.rxcui
    rxnorm.getRelatedByType
    (expand:"",
    tty:"\(t2)"):relatedGroup.conceptGroup.conceptProperties.rxcui
    rxnorm.getNDCs
    ():ndcGroup.ndcList.ndc
    """
    var comps = URLComponents(string: "https://mor.nlm.nih.gov/RxMix/")
    comps?.fragment = "?q=\(pipeline.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")&v=\(query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")&s=v"
    return comps?.url
}
