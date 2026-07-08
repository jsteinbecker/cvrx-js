// ForestBuilder.swift
// Direct port of buildFamilyForest and prepareGroupsAndRender.

import Foundation

// MARK: - 4-level forest builder

/// Build the display tree mirroring JS buildFamilyForest:
///   L0  SCDF/SBDF  → ingredient · form
///   L1  SCD base   → strength
///   L2  SCD quant  → leading qty
///   L3  SBD brand  → brand name
func buildFamilyForest(from concepts: [RxConcept]) -> [ForestNode] {
    let formTTYs: Set<TTY> = [.SCDF, .SBDF, .SCDFP, .SBDFP]

    // Build internal nodes
    struct Node {
        let concept: RxConcept
        let ingKey: String
        let strKey: String
        var children: [Node] = []
        var placed: Bool = false
    }

    var nodes = concepts.map { c in
        Node(concept: c,
             ingKey: ingredientKey(c.name),
             strKey: strengthKey(c.name))
    }

    // Index SCDF nodes by ingredient key
    var scdfByIng: [String: [Int]] = [:]   // ingKey → indices in `nodes`
    for (i, n) in nodes.enumerated() where formTTYs.contains(n.concept.tty) {
        scdfByIng[n.ingKey, default: []].append(i)
    }

    // Group drug nodes by strength key
    struct StrGroup { var base: Int? = nil; var quant: [Int] = []; var branded: [Int] = [] }
    var byStr: [String: StrGroup] = [:]
    for (i, n) in nodes.enumerated() where !formTTYs.contains(n.concept.tty) {
        if byStr[n.strKey] == nil { byStr[n.strKey] = StrGroup() }
        if brandLabel(n.concept.name) != nil    { byStr[n.strKey]!.branded.append(i) }
        else if isQuantified(n.concept.name)    { byStr[n.strKey]!.quant.append(i) }
        else                                    { byStr[n.strKey]!.base = i }
    }

    // Wire: branded → under exact quant twin, then base
    var placedSet = Set<Int>()
    for (_, g) in byStr {
        for qi in g.quant {
            let qStripped = stripBrand(nodes[qi].concept.name)
            for bi in g.branded where !placedSet.contains(bi) {
                if stripBrand(nodes[bi].concept.name) == qStripped {
                    nodes[qi].children.append(nodes[bi])
                    placedSet.insert(bi)
                    nodes[bi].placed = true
                }
            }
            if let baseIdx = g.base {
                nodes[baseIdx].children.append(nodes[qi])
                nodes[qi].placed = true
            }
        }
        for bi in g.branded where !placedSet.contains(bi) {
            if let baseIdx = g.base {
                nodes[baseIdx].children.append(nodes[bi])
                nodes[bi].placed = true
            }
        }
    }

    // Place each strength group's anchor under best-matching SCDF
    for (_, g) in byStr {
        guard let anchorIdx = g.base ?? g.quant.first ?? g.branded.first,
              !nodes[anchorIdx].placed else { continue }
        let ingK = nodes[anchorIdx].ingKey
        var best: Int? = nil; var bestLen = -1
        for (k, idxs) in scdfByIng {
            if (ingK.hasPrefix(k) || k.hasPrefix(ingK)) && k.count > bestLen {
                best = idxs[0]; bestLen = k.count
            }
        }
        if let b = best {
            nodes[b].children.append(nodes[anchorIdx])
            nodes[anchorIdx].placed = true
        }
    }

    // Collect roots
    var roots: [Node] = nodes.filter { !$0.placed }

    // Sort
    let nameSort: (Node, Node) -> Bool = {
        $0.concept.name.compare($1.concept.name, options: .numeric) == .orderedAscending
    }
    func sortRec(_ n: inout Node) {
        n.children.sort(by: nameSort)
        for i in n.children.indices { sortRec(&n.children[i]) }
    }
    roots.sort(by: nameSort)
    for i in roots.indices { sortRec(&roots[i]) }

    // Convert to ForestNode (assigning depths)
    func toForestNode(_ n: Node, depth: Int) -> ForestNode {
        let fn = ForestNode(concept: n.concept, depth: depth)
        fn.children = n.children.map { toForestNode($0, depth: depth + 1) }
        return fn
    }
    return roots.map { toForestNode($0, depth: 0) }
}

// MARK: - Flatten forest for iteration

func flattenForest(_ node: ForestNode) -> [ForestNode] {
    [node] + node.children.flatMap { flattenForest($0) }
}

// MARK: - DFG filter tree builder (mirrors prepareGroupsAndRender)

struct DFGFilterResult {
    var nonGroupConcepts: [RxConcept]   // SCDF/SCD/etc. — the displayable ones
    var groupTree: [DFGNode]            // filter button tree
    var conceptLabel: [String: String]  // rxcui → "df:<DoseForm>"
}

func buildDFGFilter(from concepts: [RxConcept]) -> DFGFilterResult {
    let groupTTYs: Set<TTY> = [.SCDG, .SBDG, .SCDGP]
    let nonGroup = concepts.filter { !groupTTYs.contains($0.tty) }

    var labelMap: [String: String] = [:]
    var presentByDFG: [String: Set<String>] = [:]

    for c in nonGroup {
        guard let df = doseFormOf(c.name), let dfg = dfToDFG[df] else { continue }
        labelMap[c.rxcui] = "df:\(df)"
        presentByDFG[dfg, default: []].insert(df)
    }

    let tree: [DFGNode] = presentByDFG
        .sorted { (dfgOrder[$0.key] ?? 99) < (dfgOrder[$1.key] ?? 99) }
        .map { (dfg, dfSet) in
            let children = dfSet
                .sorted { (dfOrder[$0] ?? 99) < (dfOrder[$1] ?? 99) }
                .map { df in DFGNode(key: "df:\(df)", label: df, children: []) }
            return DFGNode(key: "dfg:\(dfg)", label: dfg, children: children)
        }

    return DFGFilterResult(nonGroupConcepts: nonGroup, groupTree: tree, conceptLabel: labelMap)
}
