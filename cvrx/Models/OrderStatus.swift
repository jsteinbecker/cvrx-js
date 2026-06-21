import Foundation

enum OrderStatus: String, CaseIterable, Hashable, Codable {
    case pending = "Pending"
    case compounding = "Compounding"
    case waitingForApproval = "Waiting for Approval"
    case remediation = "Remediation"
    case approved = "Approved"
    case rejected = "Rejected"
}

