import Foundation
import SwiftData
import SwiftUI


/// The result of a verification action (approval or rejection).
@Model
final class VerificationRecord {
    @Attribute(.unique) var id: UUID
    var verifiedBy: User
    var verifiedAt: Date
    var decision: String
    var rejectionReason: String?

    init(
        id: UUID = UUID(),
        verifiedBy: User,
        verifiedAt: Date = Date(),
        decision: String,
        rejectionReason: String? = nil
    ) {
        self.id = id
        self.verifiedBy = verifiedBy
        self.verifiedAt = verifiedAt
        self.decision = decision
        self.rejectionReason = rejectionReason
    }

    var isApproved: Bool { decision == "Approved" }
}

enum ContainerKind: String, Hashable, Codable {
    case IVPB
    case Syringe
    case CADD
    case AmbulatoryInfusion
    case Other
}

@Model
final class CompoundOrder {
    @Attribute(.unique) var id: UUID
    var orderNumber: String
    var patient: Patient
    var medicationName: String
    var finalContainer: String
    var route: String
    var dueTime: Date
    var recipeText: String
    var components: [CompoundComponent]
    var captures: [CompoundCapture]
    var status: OrderStatus
    var currentStepIndex: Int
    var remediation: RemediationRequest?
    var verificationRecord: VerificationRecord?
    var auditEvents: [AuditEvent]

    var finalContainerKind: ContainerKind? {
        let normalized = finalContainer
            .lowercased()
            .replacingOccurrences(of: #"[-_/.,]"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)

        guard !normalized.isEmpty else { return nil }

        func matches(_ pattern: String) -> Bool {
            normalized.range(of: pattern, options: .regularExpression) != nil
        }

        let caddPattern = #"\b(cadd|elastomeric|elastomer|homepump|easypump|infusor|intermate|eclipse|folfusor|ambulatory\s*pump|(pump|medication|reservoir)\s*cassette|cassette\s*reservoir)\b"#
        if matches(caddPattern) { return .CADD }

        let syringePattern = #"\b(syringe|syr|luer(\s*(lock|slip|oral))?|prefilled\s*syringe|pca\s*syringe|tubex|carpuject)\b"#
        if matches(syringePattern) { return .Syringe }

        let ivpbPattern = #"\b(ivpb|piggy\s*back|piggy|mini\s*bag|viaflex|viaflo|excel|freeflex|lvp|svp|iv\s*bag|infusion\s*bag|bag|ns|nacl|normal\s*saline|saline|d5w?|d10w?|\d+\s*ml)\b"#
        if matches(ivpbPattern) { return .IVPB }

        return .Other
    }

    var fulfilledComponents: [CompoundComponent] {
        components.filter { $0.isFulfilled() }
    }

    var fulfilledComponentCount: Int { fulfilledComponents.count }

    var unfulfilledComponents: [CompoundComponent] {
        components.filter { !$0.isFulfilled() }
    }

    var allComponentsFulfilled: Bool {
        !components.isEmpty && unfulfilledComponents.isEmpty
    }

    var captureMutationsAllowed: Bool {
        switch status {
        case .pending, .preparing, .compounding, .remediation: return true
        case .waitingForApproval, .approved, .rejected: return false
        }
    }

    var recipeSteps: [String] {
        recipeText
            .split(whereSeparator: \.isNewline)
            .map { line -> String in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if let range = trimmed.range(of: #"^\d+[\.\)]\s*"#, options: .regularExpression) {
                    return String(trimmed[range.upperBound...])
                }
                return trimmed
            }
            .filter { !$0.isEmpty }
    }

    var currentStepText: String {
        let steps = recipeSteps
        guard !steps.isEmpty else { return "" }
        let idx = min(max(currentStepIndex, 0), steps.count - 1)
        return steps[idx]
    }

    var currentStepNumber: Int {
        min(max(currentStepIndex, 0), max(recipeSteps.count - 1, 0)) + 1
    }

    var totalStepCount: Int { recipeSteps.count }

    var verificationStatus: String {
        if let record = verificationRecord {
            let decision = record.isApproved ? "✓ Approved" : "✗ Rejected"
            return "\(decision) by \(record.verifiedBy.username) on \(record.verifiedAt.formatted(date: .abbreviated, time: .standard))"
        } else if status == .waitingForApproval {
            return "Awaiting verification"
        } else {
            return "Not yet submitted for verification"
        }
    }

    var hasPendingOverrides: Bool {
        components.contains { $0.hasPendingOverrides }
    }

    init(
        id: UUID = UUID(),
        orderNumber: String,
        patient: Patient,
        medicationName: String,
        finalContainer: String,
        route: String,
        dueTime: Date,
        recipeText: String,
        components: [CompoundComponent] = [],
        captures: [CompoundCapture] = [],
        status: OrderStatus = .pending,
        currentStepIndex: Int = 0,
        remediation: RemediationRequest? = nil,
        verificationRecord: VerificationRecord? = nil,
        auditEvents: [AuditEvent] = []
    ) {
        self.id = id
        self.orderNumber = orderNumber
        self.patient = patient
        self.medicationName = medicationName
        self.finalContainer = finalContainer
        self.route = route
        self.dueTime = dueTime
        self.recipeText = recipeText
        self.components = components
        self.captures = captures
        self.status = status
        self.currentStepIndex = currentStepIndex
        self.remediation = remediation
        self.verificationRecord = verificationRecord
        self.auditEvents = auditEvents
    }
}



