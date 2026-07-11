import Foundation
import SwiftData

@Model
final class Labeler {
    @Attribute(.unique)
    var name: String

    var fullName: String
    var hidden: Bool
    var labelerCodes: [String]

    init(
        name: String,
        fullName: String,
        labelerCodes: [String],
        hidden: Bool = false
    ) {
        self.name = name
        self.fullName = fullName
        self.hidden = hidden
        self.labelerCodes = labelerCodes
    }
}

struct LabelerRecord: Sendable {
    let name: String
    let fullName: String
    let codes: [String]
}

private struct LabelerDetails: Decodable, Sendable {
    let fullName: String
    let codes: [String]
    let activeRxProductCount: Int?
    let inRxNorm: Bool
    let activeNdcProductCount: Int?
    let hasActiveNdcProducts: Bool?

    enum CodingKeys: String, CodingKey {
        case fullName = "full_name"
        case codes
        case activeRxProductCount = "active_rx_product_count"
        case inRxNorm = "in_rxnorm"
        case legacyInRxNorm = "in_rx_norm"
        case activeNdcProductCount = "active_ndc_product_count"
        case hasActiveNdcProducts = "has_active_ndc_products"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        fullName = try container.decode(String.self, forKey: .fullName)
        codes = try container.decode([String].self, forKey: .codes)
        activeRxProductCount = try container.decodeIfPresent(Int.self, forKey: .activeRxProductCount)
        inRxNorm = try container.decodeIfPresent(Bool.self, forKey: .inRxNorm)
            ?? container.decodeIfPresent(Bool.self, forKey: .legacyInRxNorm)
            ?? false
        activeNdcProductCount = try container.decodeIfPresent(Int.self, forKey: .activeNdcProductCount)
        hasActiveNdcProducts = try container.decodeIfPresent(Bool.self, forKey: .hasActiveNdcProducts)
    }
}

enum LabelerImportError: LocalizedError {
    case duplicateName(String)
    case emptyName
    case emptyFullName(String)
    case missingCodes(String)

    var errorDescription: String? {
        switch self {
        case .duplicateName(let name):
            return "The labeler data contains more than one entry named “\(name)”."

        case .emptyName:
            return "The labeler data contains an entry with an empty name."

        case .emptyFullName(let name):
            return "The labeler “\(name)” has an empty full name."

        case .missingCodes(let name):
            return "The labeler “\(name)” has no labeler codes."
        }
    }
}

enum LabelerCodeLookup {
    nonisolated(unsafe) private static var recordsByCode: [String: String] = [:]

    static func name(forNDC ndc: String) -> String? {
        for code in candidateCodes(forNDC: ndc) {
            if let name = recordsByCode[code] {
                return name
            }
        }
        return nil
    }

    static func replaceRecords(with labelers: [Labeler]) {
        var lookup: [String: String] = [:]
        for labeler in labelers where labeler.hidden != true {
            for code in labeler.labelerCodes {
                let normalizedCode = code.filter(\.isNumber)
                if !normalizedCode.isEmpty {
                    lookup[normalizedCode] = labeler.name
                }
            }
        }
        recordsByCode = lookup
    }

    static func candidateCodes(forNDC ndc: String) -> [String] {
        if ndc.contains("-") {
            let parts = ndc.split(separator: "-").map { String($0.filter(\.isNumber)) }
            if let labeler = parts.first, !labeler.isEmpty {
                return [labeler]
            }
        }

        let digits = ndc.filter(\.isNumber)
        guard digits.count >= 5 else { return [] }

        let fiveDigitPrefix = String(digits.prefix(5))
        var candidates = [fiveDigitPrefix]
        if fiveDigitPrefix.hasPrefix("0") {
            candidates.append(String(fiveDigitPrefix.dropFirst()))
        }

        return Array(Set(candidates)).sorted { $0.count > $1.count }
    }
}

nonisolated func parseLabelerData(_ data: Data) throws -> [LabelerRecord] {
    let decoded = try JSONDecoder().decode(
        [[String: LabelerDetails]].self,
        from: data
    )

    var recordsByName: [String: LabelerRecord] = [:]

    for entry in decoded {
        for (rawName, details) in entry {
            let name = rawName.normalizedLabelerText
            let fullName = details.fullName.normalizedLabelerText

            guard !name.isEmpty else {
                throw LabelerImportError.emptyName
            }

            guard !fullName.isEmpty else {
                throw LabelerImportError.emptyFullName(name)
            }

            let codes = Array(
                Set(
                    details.codes
                        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                        .filter { !$0.isEmpty }
                )
            )
            .sorted()

            guard !codes.isEmpty else {
                throw LabelerImportError.missingCodes(name)
            }

            let lookupKey = name.normalizedLabelerKey

            guard recordsByName[lookupKey] == nil else {
                throw LabelerImportError.duplicateName(name)
            }

            recordsByName[lookupKey] = LabelerRecord(
                name: name,
                fullName: fullName,
                codes: codes
            )
        }
    }

    return recordsByName.values.sorted {
        $0.name.localizedStandardCompare($1.name) == .orderedAscending
    }
}

private extension String {
    nonisolated var normalizedLabelerText: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }

    nonisolated var normalizedLabelerKey: String {
        normalizedLabelerText.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: .current
        )
    }
}

