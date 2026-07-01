// Models.swift
// Pure value types mirroring the JS data structures.

import Foundation
import SwiftData

// MARK: - TTY

/// Term Type (TTY) is an RxNorm Categorical class at the highest scop.
/// NDCs typically feed into the SCD/SBD level (semantic clinical drug / semantic branded drug)
enum TTY: String, Codable, Hashable, CaseIterable {
    /// Semantic Drug Dose Form
    case SCDF
    /// Semantic Brand Dose Form
    case SBDF, SCDFP, SBDFP
    case SCDG, SBDG, SCDGP
    case SCD, SBD, GPCK, BPCK

    var isGroup: Bool { [.SCDG, .SBDG, .SCDGP].contains(self) }
    var isForm:  Bool { [.SCDF, .SBDF, .SCDFP, .SBDFP].contains(self) }
    var isDrug:  Bool { [.SCD, .SBD, .GPCK, .BPCK].contains(self) }
    var isClinical: Bool { [.SCD, .GPCK].contains(self) }
    var isBranded:  Bool { [.SBD, .SBDF, .SBDG, .SBDFP, .BPCK].contains(self) }

    var sortOrder: Int {
        switch self {
        case .SCDF: return 0; case .SBDF: return 1; case .SCDFP: return 2; case .SBDFP: return 3
        case .SCDG: return 4; case .SBDG: return 5; case .SCDGP: return 6
        case .SCD:  return 7; case .SBD:  return 8; case .GPCK:  return 9; case .BPCK:  return 10
        }
    }

    var pillColor: PillStyle {
        switch self {
        case .SCD, .SBD:            return .green
        case .GPCK, .BPCK:          return .amber
        case .SCDF, .SBDF, .SCDFP, .SBDFP,
             .SCDG, .SBDG, .SCDGP:  return .blue
        }
    }
}

enum PillStyle { case blue, green, amber }

// MARK: - RxConcept

struct RxConcept: Identifiable, Hashable {
    let rxcui: String
    let name:  String
    let tty:   TTY
    var traversal: Bool = false   // needs SCDF→SCD traversal for NDCs

    var id: String { rxcui }
}

// MARK: - NDCInfo

struct NDCInfo: Identifiable {
    let ndc: String
    var productName: String?
    var status: String?
    var marketed: Bool?
    var id: String { ndc }
}

// MARK: - NDCResult

struct NDCResult {
    var ndcs: [String]
    var path: String           // provenance description
}

// MARK: - ForestNode (display tree)

@Observable final class ForestNode: Identifiable {
    let concept: RxConcept
    var children: [ForestNode]
    var depth: Int              // 0=SCDF, 1=SCD base, 2=SCD quant, 3=SBD brand

    var ndcResult: NDCResult?
    var ndcState: NDCLoadState = .idle

    var id: String { concept.rxcui }

    init(concept: RxConcept, children: [ForestNode] = [], depth: Int = 0) {
        self.concept  = concept
        self.children = children
        self.depth    = depth
    }
}

enum NDCLoadState { case idle, loading, loaded, failed(String) }

// MARK: - DFG filter tree

struct DFGNode: Identifiable, Hashable {
    let key: String            // "dfg:<name>" or "df:<name>"
    let label: String
    var children: [DFGNode]
    var id: String { key }

    // Recursively collect all keys in this subtree
    func allKeys() -> [String] {
        [key] + children.flatMap { $0.allKeys() }
    }
}

// MARK: - SearchPhase

enum SearchPhase: Equatable {
    case idle
    case searching(String)
    case results
    case noResults(String)
    case error(String)
}

// MARK: - SwiftData — search history

@Model
final class SearchHistoryEntry {
    var query: String
    var date: Date
    var resultCount: Int

    init(query: String, resultCount: Int) {
        self.query       = query
        self.date        = Date()
        self.resultCount = resultCount
    }
}

@Model
final class CachedNDCName {
    var ndc: String
    var productName: String?
    var status: String?
    var marketed: Bool?
    var cachedAt: Date

    init(ndc: String, productName: String?, status: String?, marketed: Bool?) {
        self.ndc         = ndc
        self.productName = productName
        self.status      = status
        self.marketed    = marketed
        self.cachedAt    = Date()
    }
}
