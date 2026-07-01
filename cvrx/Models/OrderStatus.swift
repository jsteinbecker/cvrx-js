import Foundation

enum OrderStatus: String, CaseIterable, Hashable, Codable {
    case pending = "Pending"
    case staging = "Staging"
    case preparing = "Preparing"
    case waitingForApproval = "Waiting for Approval"
    case remediation = "Remediation"
    case approved = "Approved"
    case rejected = "Rejected"

    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)

        if let status = OrderStatus(rawValue: value) {
            self = status
            return
        }

        switch value {
        case "Compounding":
            self = .preparing
        default:
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "Cannot initialize OrderStatus from invalid String value \(value)"
                )
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}
