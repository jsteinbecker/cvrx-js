import Foundation
import SwiftData

// MARK: - Audit Trail Events

/// The immutable record of who did what, when, and why.
/// Every action that requires traceability generates one of these.
@Model
final class AuditEvent {
    @Attribute(.unique) var id: UUID
    /// The user who performed the action.
    var actor: User
    /// When the action occurred.
    var timestamp: Date
    /// JSON-encoded AuditAction — stored as Data to avoid SwiftData composite-attribute introspection failures with enums.
    var actionData: Data
    /// Optional context: reason, comment, or correlation ID for grouped operations.
    var context: String?

    /// The type of action and its details.
    var action: AuditAction {
        get { try! JSONDecoder().decode(AuditAction.self, from: actionData) }
        set { actionData = try! JSONEncoder().encode(newValue) }
    }

    init(
        id: UUID = UUID(),
        actor: User,
        timestamp: Date = Date(),
        action: AuditAction,
        context: String? = nil
    ) {
        self.id = id
        self.actor = actor
        self.timestamp = timestamp
        self.actionData = try! JSONEncoder().encode(action)
        self.context = context
    }
    
    /// Compact summary for display in audit logs.
    var summary: String {
        let roleLabel = actor.role.rawValue
        let userInfo = "\(actor.username) (\(roleLabel))"
        return "\(timestamp.formatted(date: .abbreviated, time: .standard)): \(userInfo) — \(action.summary)"
    }
}

// MARK: - User Snapshot

/// Immutable snapshot of user identity captured at the time of an audit event.
/// Using a value type avoids embedding a SwiftData class reference inside a
/// persisted Codable enum, which SwiftData does not support.
struct UserSnapshot: Codable, Hashable {
    let id: UUID
    let username: String
    let name: String
}

extension User {
    var snapshot: UserSnapshot {
        UserSnapshot(id: id, username: username, name: name)
    }
}

// MARK: - Action Types

/// Union of all auditable actions.
enum AuditAction: Hashable, Codable {
    /// A lot was scanned (barcode auto-populated).
    case lotScanned(
        orderID: UUID,
        componentID: UUID,
        lotID: UUID,
        barcodeValue: String,
        lot: String,
        expiration: Date?
    )
    
    /// A lot was manually entered (no barcode).
    case lotManuallyEntered(
        orderID: UUID,
        componentID: UUID,
        lotID: UUID,
        lot: String,
        expiration: Date?
    )
    
    /// A scanned lot's data was overridden (barcode changed, lot corrected, etc.).
    case lotOverridden(
        orderID: UUID,
        componentID: UUID,
        lotID: UUID,
        field: String,  // e.g., "barcode", "lot", "expiration"
        previousValue: String,
        newValue: String
    )
    
    /// A scan override was co-signed by a verifier, making it official.
    case scanOverrideCosigned(
        orderID: UUID,
        componentID: UUID,
        lotID: UUID,
        field: String,
        cosignedBy: UserSnapshot
    )
    
    /// An image was captured during compounding.
    case imageCaptured(
        orderID: UUID,
        captureID: UUID,
        kind: String,  // "Reference" or "Aux"
        imageName: String
    )
    
    /// An image was captured as part of remediation (after verification rejection).
    case remediationImageCaptured(
        orderID: UUID,
        captureID: UUID,
        imageName: String,
        remediationRequestID: UUID
    )
    
    /// A verification (approval or rejection) was performed.
    case verificationPerformed(
        orderID: UUID,
        decision: String,  // "Approved" or "Rejected"
        rejectionReason: String?  // Non-nil if rejected
    )
    
    /// A remediation request was issued to the compounder.
    case remediationRequested(
        orderID: UUID,
        remediationRequestID: UUID,
        reason: String,
        requestedBy: UserSnapshot
    )
    
    /// Remediation (re-do of captures, lot corrections, etc.) was completed and resubmitted.
    case remediationCompleted(
        orderID: UUID,
        remediationRequestID: UUID,
        completedBy: UserSnapshot
    )
    
    var summary: String {
        switch self {
        case .lotScanned(_, _, _, let barcode, let lot, _):
            return "Scanned lot \(lot) (barcode: \(barcode))"
        case .lotManuallyEntered(_, _, _, let lot, _):
            return "Manually entered lot \(lot)"
        case .lotOverridden(_, _, _, let field, let prev, let new):
            return "Overrode \(field): '\(prev)' → '\(new)'"
        case .scanOverrideCosigned(_, _, _, let field, let verifier):
            return "Cosigned \(field) override (by \(verifier.username))"
        case .imageCaptured(_, _, let kind, let name):
            return "Captured \(kind) image: \(name)"
        case .remediationImageCaptured(_, _, let name, _):
            return "Captured remediation image: \(name)"
        case .verificationPerformed(_, let decision, _):
            return "\(decision) compound"
        case .remediationRequested(_, _, let reason, _):
            return "Requested remediation: \(reason)"
        case .remediationCompleted(_, _, let compounder):
            return "Completed remediation (by \(compounder.username))"
        }
    }
}

// MARK: - Equatable / Codable Conformance for AuditAction

extension AuditAction {
    enum CodingKeys: String, CodingKey {
        case type
        case orderID, componentID, lotID, barcodeValue, lot, expiration
        case field, previousValue, newValue
        case kind, imageName, captureID
        case decision, rejectionReason, remediationRequestID, reason
        case actor, completedBy, requestedBy
    }
    
    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        switch self {
        case .lotScanned(let orderID, let componentID, let lotID, let barcodeValue, let lot, let expiration):
            try container.encode("lotScanned", forKey: .type)
            try container.encode(orderID, forKey: .orderID)
            try container.encode(componentID, forKey: .componentID)
            try container.encode(lotID, forKey: .lotID)
            try container.encode(barcodeValue, forKey: .barcodeValue)
            try container.encode(lot, forKey: .lot)
            try container.encode(expiration, forKey: .expiration)
            
        case .lotManuallyEntered(let orderID, let componentID, let lotID, let lot, let expiration):
            try container.encode("lotManuallyEntered", forKey: .type)
            try container.encode(orderID, forKey: .orderID)
            try container.encode(componentID, forKey: .componentID)
            try container.encode(lotID, forKey: .lotID)
            try container.encode(lot, forKey: .lot)
            try container.encode(expiration, forKey: .expiration)
            
        case .lotOverridden(let orderID, let componentID, let lotID, let field, let previousValue, let newValue):
            try container.encode("lotOverridden", forKey: .type)
            try container.encode(orderID, forKey: .orderID)
            try container.encode(componentID, forKey: .componentID)
            try container.encode(lotID, forKey: .lotID)
            try container.encode(field, forKey: .field)
            try container.encode(previousValue, forKey: .previousValue)
            try container.encode(newValue, forKey: .newValue)
            
        case .scanOverrideCosigned(let orderID, let componentID, let lotID, let field, let cosignedBy):
            try container.encode("scanOverrideCosigned", forKey: .type)
            try container.encode(orderID, forKey: .orderID)
            try container.encode(componentID, forKey: .componentID)
            try container.encode(lotID, forKey: .lotID)
            try container.encode(field, forKey: .field)
            try container.encode(cosignedBy, forKey: .actor)
            
        case .imageCaptured(let orderID, let captureID, let kind, let imageName):
            try container.encode("imageCaptured", forKey: .type)
            try container.encode(orderID, forKey: .orderID)
            try container.encode(captureID, forKey: .captureID)
            try container.encode(kind, forKey: .kind)
            try container.encode(imageName, forKey: .imageName)
            
        case .remediationImageCaptured(let orderID, let captureID, let imageName, let remediationRequestID):
            try container.encode("remediationImageCaptured", forKey: .type)
            try container.encode(orderID, forKey: .orderID)
            try container.encode(captureID, forKey: .captureID)
            try container.encode(imageName, forKey: .imageName)
            try container.encode(remediationRequestID, forKey: .remediationRequestID)
            
        case .verificationPerformed(let orderID, let decision, let rejectionReason):
            try container.encode("verificationPerformed", forKey: .type)
            try container.encode(orderID, forKey: .orderID)
            try container.encode(decision, forKey: .decision)
            try container.encode(rejectionReason, forKey: .rejectionReason)
            
        case .remediationRequested(let orderID, let remediationRequestID, let reason, let requestedBy):
            try container.encode("remediationRequested", forKey: .type)
            try container.encode(orderID, forKey: .orderID)
            try container.encode(remediationRequestID, forKey: .remediationRequestID)
            try container.encode(reason, forKey: .reason)
            try container.encode(requestedBy, forKey: .requestedBy)
            
        case .remediationCompleted(let orderID, let remediationRequestID, let completedBy):
            try container.encode("remediationCompleted", forKey: .type)
            try container.encode(orderID, forKey: .orderID)
            try container.encode(remediationRequestID, forKey: .remediationRequestID)
            try container.encode(completedBy, forKey: .completedBy)
        }
    }
    
    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        
        switch type {
        case "lotScanned":
            let orderID = try container.decode(UUID.self, forKey: .orderID)
            let componentID = try container.decode(UUID.self, forKey: .componentID)
            let lotID = try container.decode(UUID.self, forKey: .lotID)
            let barcodeValue = try container.decode(String.self, forKey: .barcodeValue)
            let lot = try container.decode(String.self, forKey: .lot)
            let expiration = try container.decodeIfPresent(Date.self, forKey: .expiration)
            self = .lotScanned(orderID: orderID, componentID: componentID, lotID: lotID, barcodeValue: barcodeValue, lot: lot, expiration: expiration)
            
        case "lotManuallyEntered":
            let orderID = try container.decode(UUID.self, forKey: .orderID)
            let componentID = try container.decode(UUID.self, forKey: .componentID)
            let lotID = try container.decode(UUID.self, forKey: .lotID)
            let lot = try container.decode(String.self, forKey: .lot)
            let expiration = try container.decodeIfPresent(Date.self, forKey: .expiration)
            self = .lotManuallyEntered(orderID: orderID, componentID: componentID, lotID: lotID, lot: lot, expiration: expiration)
            
        case "lotOverridden":
            let orderID = try container.decode(UUID.self, forKey: .orderID)
            let componentID = try container.decode(UUID.self, forKey: .componentID)
            let lotID = try container.decode(UUID.self, forKey: .lotID)
            let field = try container.decode(String.self, forKey: .field)
            let previousValue = try container.decode(String.self, forKey: .previousValue)
            let newValue = try container.decode(String.self, forKey: .newValue)
            self = .lotOverridden(orderID: orderID, componentID: componentID, lotID: lotID, field: field, previousValue: previousValue, newValue: newValue)
            
        case "scanOverrideCosigned":
            let orderID = try container.decode(UUID.self, forKey: .orderID)
            let componentID = try container.decode(UUID.self, forKey: .componentID)
            let lotID = try container.decode(UUID.self, forKey: .lotID)
            let field = try container.decode(String.self, forKey: .field)
            let cosignedBy = try container.decode(UserSnapshot.self, forKey: .actor)
            self = .scanOverrideCosigned(orderID: orderID, componentID: componentID, lotID: lotID, field: field, cosignedBy: cosignedBy)
            
        case "imageCaptured":
            let orderID = try container.decode(UUID.self, forKey: .orderID)
            let captureID = try container.decode(UUID.self, forKey: .captureID)
            let kind = try container.decode(String.self, forKey: .kind)
            let imageName = try container.decode(String.self, forKey: .imageName)
            self = .imageCaptured(orderID: orderID, captureID: captureID, kind: kind, imageName: imageName)
            
        case "remediationImageCaptured":
            let orderID = try container.decode(UUID.self, forKey: .orderID)
            let captureID = try container.decode(UUID.self, forKey: .captureID)
            let imageName = try container.decode(String.self, forKey: .imageName)
            let remediationRequestID = try container.decode(UUID.self, forKey: .remediationRequestID)
            self = .remediationImageCaptured(orderID: orderID, captureID: captureID, imageName: imageName, remediationRequestID: remediationRequestID)
            
        case "verificationPerformed":
            let orderID = try container.decode(UUID.self, forKey: .orderID)
            let decision = try container.decode(String.self, forKey: .decision)
            let rejectionReason = try container.decodeIfPresent(String.self, forKey: .rejectionReason)
            self = .verificationPerformed(orderID: orderID, decision: decision, rejectionReason: rejectionReason)
            
        case "remediationRequested":
            let orderID = try container.decode(UUID.self, forKey: .orderID)
            let remediationRequestID = try container.decode(UUID.self, forKey: .remediationRequestID)
            let reason = try container.decode(String.self, forKey: .reason)
            let requestedBy = try container.decode(UserSnapshot.self, forKey: .requestedBy)
            self = .remediationRequested(orderID: orderID, remediationRequestID: remediationRequestID, reason: reason, requestedBy: requestedBy)
            
        case "remediationCompleted":
            let orderID = try container.decode(UUID.self, forKey: .orderID)
            let remediationRequestID = try container.decode(UUID.self, forKey: .remediationRequestID)
            let completedBy = try container.decode(UserSnapshot.self, forKey: .completedBy)
            self = .remediationCompleted(orderID: orderID, remediationRequestID: remediationRequestID, completedBy: completedBy)
            
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Unknown action type: \(type)"
            )
        }
    }
}
