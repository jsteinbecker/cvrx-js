import Foundation
import SwiftData


@Model
final class Labeler {
    var name: String
    var fullName: String
    var hidden: Bool = false

    @Attribute(.unique)
    var labelerCode: String

    init(name: String, fullName: String, labelerCode: String, hidden: Bool = false) {
        self.name = name
        self.fullName = fullName
        self.labelerCode = labelerCode
        self.hidden = hidden
    }
}

private struct LabelerPayload: Decodable {
    let name: String
    let fullName: String
    let directory: String?

    enum CodingKeys: String, CodingKey {
        case name
        case fullName = "full_name"
        case directory
    }
}

func importLabelerData() async throws -> [Labeler] {
    guard let url = Bundle.main.url(
        forResource: "Labelers",
        withExtension: "json",
        subdirectory: "Data"
    ) ?? Bundle.main.url(
        forResource: "Labelers",
        withExtension: "json"
    ) else {
        throw CocoaError(.fileNoSuchFile)
    }

    let data = try Data(contentsOf: url)

    let decoded = try JSONDecoder().decode(
        [String: LabelerPayload].self,
        from: data
    )

    return decoded
        .map { labelerCode, payload in
            Labeler(
                name: payload.name,
                fullName: payload.fullName,
                labelerCode: labelerCode
            )
        }
        .sorted { $0.labelerCode < $1.labelerCode }
}
