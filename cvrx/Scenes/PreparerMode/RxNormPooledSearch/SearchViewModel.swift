// SearchViewModel.swift
// Central ObservableObject — mirrors all JS global state and the doSearch/applyNameFilter flow.

import Foundation
import SwiftData
import Observation

@Observable
final class SearchViewModel {

    // MARK: - Config (mirrors active1, active2, crossPop, includeCombos)

    var activeTTY1: Set<TTY> = Set(TTY.allCases.filter { $0.isGroup || $0.isForm })
    var activeTTY2: Set<TTY> = [.SCD, .SBD, .GPCK, .BPCK]
    var crossPop:      Bool = false
    var includeCombos: Bool = false

    // MARK: - Search state (mirrors lastUnique, lastTokens, lastVia)

    var query:        String = ""
    var phase:        SearchPhase = .idle
    var statusText:   String = ""

    private var lastUnique: [RxConcept] = []
    private var lastTokens: [String] = []
    private var lastVia:    String = "exact"

    // MARK: - Display state (mirrors lastNonGroupConcepts, groupTreeRoots, selectedGroups)

    var forestRoots:       [ForestNode] = []
    var dfgTree:           [DFGNode] = []
    var selectedGroups:    Set<String> = []
    private var conceptLabel: [String: String] = [:]
    private var nonGroupConcepts: [RxConcept] = []

    // MARK: - Selected NDC for popover

    var selectedNDC: NDCInfo? = nil
    var importSummary: String = ""
    var importingNodeID: String?

    // MARK: - Search timer (mirrors debounce)

    private var searchTask: Task<Void, Never>?

    // MARK: - SwiftData context (injected from App)

    var modelContext: ModelContext?
    var facilityID: String?

    // MARK: - Search entry point (mirrors doSearch with debounce)

    func scheduleSearch() {
        searchTask?.cancel()
        searchTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(420))
            guard !Task.isCancelled else { return }
            await self?.doSearch()
        }
    }

    func doSearch() async {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { phase = .idle; forestRoots = []; statusText = ""; return }

        phase = .searching("Finding RxCUIs…")
        await APICache.shared.clear()

        do {
            // Step 1: exact seed
            var seeds = try await findRxcuiSeeds(q)
            var via   = "exact"
            var unique: [RxConcept] = seeds.isEmpty ? [] : try await gatherConcepts(seeds: seeds, tty1: activeTTY1, tty2: activeTTY2)

            // Step 2: approximate fallback
            if unique.isEmpty {
                phase = .searching("No exact match — trying approximate…")
                seeds  = try await approximateSeeds(q)
                if !seeds.isEmpty {
                    unique = try await gatherConcepts(seeds: seeds, tty1: activeTTY1, tty2: activeTTY2)
                    via    = "approximate"
                }
            }

            if unique.isEmpty {
                phase = .noResults("No results — try a different spelling or enable more TTYs")
                lastUnique = []; lastTokens = []; lastVia = "exact"
                return
            }

            lastUnique = unique
            lastTokens = tokenize(q)
            lastVia    = via

            await saveHistory(query: q, count: unique.count)
            applyNameFilter()
        } catch {
            phase = .error(error.localizedDescription)
        }
    }

    // MARK: - Name filter (mirrors applyNameFilter)

    func applyNameFilter() {
        let filtered = lastUnique.filter { c in
            includeCombos
                ? matchesTokensLoose(c.name, tokens: lastTokens)
                : matchesTokens(c.name, tokens: lastTokens)
        }
        let hidden = lastUnique.count - filtered.count

        if filtered.isEmpty {
            let hint = hidden > 0
                ? " (\(hidden) filtered — \(includeCombos ? "try different terms" : "enable Combos to see all"))"
                : ""
            phase = .noResults("No concepts matched the name filter.\(hint)")
            forestRoots = []
            return
        }

        // Build DFG filter
        let dfgResult  = buildDFGFilter(from: filtered)
        nonGroupConcepts = dfgResult.nonGroupConcepts
        dfgTree        = dfgResult.groupTree
        conceptLabel   = dfgResult.conceptLabel
        selectedGroups = Set(dfgTree.flatMap { $0.allKeys() })   // default: all on

        buildForestAndStatus(filtered: filtered, hidden: hidden)
    }

    // MARK: - Build forest + update status

    func buildForestAndStatus(filtered: [RxConcept], hidden: Int) {
        let visible = nonGroupConcepts.filter { familyVisible(rxcui: $0.rxcui) }
        forestRoots = buildFamilyForest(from: visible)

        let approxNote = lastVia == "approximate" ? " (approx)" : ""
        let hiddenNote = hidden > 0 ? " · \(hidden) filtered" : ""
        statusText = "\(filtered.count) concept\(filtered.count == 1 ? "" : "s")\(hiddenNote)\(approxNote)"
        phase = .results
    }

    // MARK: - DFG group toggle (mirrors toggleSubtree)

    func toggleDFGSubtree(_ node: DFGNode) {
        let keys = node.allKeys()
        let allOn = keys.allSatisfy { selectedGroups.contains($0) }
        if allOn { keys.forEach { selectedGroups.remove($0) } }
        else     { keys.forEach { selectedGroups.insert($0) } }
        rebuildForest()
    }

    func selectAllGroups()  { selectedGroups = Set(dfgTree.flatMap { $0.allKeys() }); rebuildForest() }
    func clearAllGroups()   { selectedGroups.removeAll(); rebuildForest() }

    private func rebuildForest() {
        let filtered = lastUnique.filter { c in
            includeCombos ? matchesTokensLoose(c.name, tokens: lastTokens) : matchesTokens(c.name, tokens: lastTokens)
        }
        buildForestAndStatus(filtered: filtered, hidden: lastUnique.count - filtered.count)
    }

    // MARK: - Visibility (mirrors familyVisible)

    func familyVisible(rxcui: String) -> Bool {
        let label = conceptLabel[rxcui]
        guard let l = label else { return true }   // ungrouped → always shown
        return selectedGroups.contains(l)
    }

    // MARK: - DFG node state (mirrors nodeState)

    func dfgNodeState(_ node: DFGNode) -> DFGState {
        let keys = node.allKeys()
        let on = keys.filter { selectedGroups.contains($0) }.count
        if on == 0 { return .off }
        if on == keys.count { return .on }
        return .mixed
    }

    func dfgNodeCount(_ node: DFGNode) -> Int {
        let keys = Set(node.allKeys())
        return nonGroupConcepts.filter { conceptLabel[$0.rxcui].map { keys.contains($0) } ?? false }.count
    }

    // MARK: - NDC loading for a concept node

    func loadNDCs(for node: ForestNode) {
        guard case .idle = node.ndcState else { return }
        node.ndcState = .loading
        Task {
            do {
                let result: NDCResult
                if node.concept.traversal {
                    result = try await poolNDCsViaForm(concept: node.concept, crossPop: crossPop)
                } else {
                    result = try await poolNDCsDirect(concept: node.concept, crossPop: crossPop)
                }
                await MainActor.run {
                    node.ndcResult = result
                    node.ndcState  = .loaded
                }
            } catch {
                await MainActor.run { node.ndcState = .failed(error.localizedDescription) }
            }
        }
    }

    // MARK: - NDC name lookup for popover

    func loadNDCInfo(_ ndc: String) async {
        // Check SwiftData cache first
        if let ctx = modelContext {
            let cached = try? ctx.fetch(FetchDescriptor<CachedNDCName>(
                predicate: #Predicate { $0.ndc == ndc }
            )).first
            if let c = cached {
                selectedNDC = NDCInfo(ndc: ndc, productName: c.productName, status: c.status, marketed: c.marketed)
                return
            }
        }
        do {
            let info = try await fetchNDCInfo(ndc)
            selectedNDC = info
            // Persist to SwiftData
            if let ctx = modelContext {
                let entry = CachedNDCName(ndc: ndc, productName: info.productName, status: info.status, marketed: info.marketed)
                ctx.insert(entry)
                try? ctx.save()
            }
        } catch {
            selectedNDC = NDCInfo(ndc: ndc)
        }
    }

    // MARK: - Product import

    func importProduct(from node: ForestNode) {
        guard let result = node.ndcResult else { return }
        let ndcs = result.ndcs.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard !ndcs.isEmpty else {
            importSummary = "No NDCs available to import."
            return
        }
        guard let ctx = modelContext else {
            importSummary = "Product catalog is unavailable."
            return
        }

        importingNodeID = node.id
        Task { @MainActor in
            defer { importingNodeID = nil }
            do {
                let descriptor = FetchDescriptor<Product>()
                let products = try ctx.fetch(descriptor)
                let incomingKeys = Set(ndcs.flatMap { ndcMatchKeys(for: $0) })
                let existing = products.first { product in
                    product.name.localizedCaseInsensitiveCompare(node.concept.name) == .orderedSame
                        || !product.normalizedNDCMatchKeys.isDisjoint(with: incomingKeys)
                }

                let product = existing ?? Product(
                    name: node.concept.name,
                    linkedNDCs: [],
                    importedRxCUI: node.concept.rxcui,
                    importedTTY: node.concept.tty.rawValue,
                    importedAt: .now,
                    facilityID: facilityID,
                    strength: 0,
                    strengthUnit: .unitless
                )

                if existing == nil { ctx.insert(product) }
                let before = product.linkedNDCs.count
                product.linkedNDCs = mergedNDCs(existing: product.linkedNDCs, imported: ndcs)
                product.importedRxCUI = node.concept.rxcui
                product.importedTTY = node.concept.tty.rawValue
                product.importedAt = .now
                product.facilityID = facilityID

                try ctx.save()
                let added = product.linkedNDCs.count - before
                let verb = existing == nil ? "Created" : "Updated"
                importSummary = "\(verb) \(product.name) with \(product.linkedNDCs.count) NDCs (\(added) new)."
            } catch {
                importSummary = "Import failed: \(error.localizedDescription)"
            }
        }
    }

    private func mergedNDCs(existing: [String], imported: [String]) -> [String] {
        var seen = Set(existing.flatMap { ndcMatchKeys(for: $0) })
        var merged = existing
        for ndc in imported {
            let keys = ndcMatchKeys(for: ndc)
            guard seen.isDisjoint(with: keys) else { continue }
            merged.append(ndc)
            seen.formUnion(keys)
        }
        return merged.sorted()
    }

    // MARK: - History

    private func saveHistory(query: String, count: Int) async {
        guard let ctx = modelContext else { return }
        await MainActor.run {
            let entry = SearchHistoryEntry(query: query, resultCount: count)
            ctx.insert(entry)
            try? ctx.save()
        }
    }

    // MARK: - RxMix URL

    func rxMixURL() -> URL? {
        buildRxMixURL(query: query, tty1: activeTTY1, tty2: activeTTY2)
    }
}

enum DFGState { case on, mixed, off }
