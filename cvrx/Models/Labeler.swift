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
    let activeRxProductCount: Int
    let inRxNorm: Bool
    let activeNdcProductCount: Int
    let hasActiveNdcProducts: Bool

    enum CodingKeys: String, CodingKey {
        case fullName = "full_name"
        case codes
        case activeRxProductCount = "active_rx_product_count"
        case inRxNorm = "in_rx_norm"
        case activeNdcProductCount = "active_ndc_product_count"
        case hasActiveNdcProducts = "has_active_ndc_products"
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

func importLabelerData() async throws -> [LabelerRecord] {
    try await Task.detached(priority: .userInitiated) {
        guard let url = Bundle.main.url(
            forResource: "Labelers",
            withExtension: "json",
            subdirectory: "Data"
        ) ?? Bundle.main.url(
            forResource: "Labelers",
            withExtension: "json"
        ) else {
            throw CocoaError(
                .fileNoSuchFile,
                userInfo: [
                    NSFilePathErrorKey: "Data/Labelers.json"
                ]
            )
        }

        let data = try Data(contentsOf: url)

        let decoded = try JSONDecoder().decode(
            [[String: LabelerDetails]].self,
            from: data
        )

        var recordsByName: [String: LabelerRecord] = [:]

        for entry in decoded {
            for (rawName, details) in entry {
                let name = await rawName.normalizedLabelerText
                let fullName = await details.fullName.normalizedLabelerText

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

                let lookupKey = await name.normalizedLabelerKey

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
    }.value
}

private extension String {
    var normalizedLabelerText: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var normalizedLabelerKey: String {
        normalizedLabelerText.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: .current
        )
    }
}
