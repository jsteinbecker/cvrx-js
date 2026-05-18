import Foundation

enum OrderStatus: String, CaseIterable, Hashable, Codable {
    case pending = "Pending"
    case compounding = "Compounding"
    case readyForVerification = "Ready for Verification"
    case remediation = "Remediation"
    case approved = "Approved"
    case rejected = "Rejected"
}
