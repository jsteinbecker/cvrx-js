import Foundation

/// The result of a verification action (approval or rejection).
struct VerificationRecord: Identifiable, Hashable, Codable {
    let id: UUID
    
    /// The verifier (RPh) who made the decision.
    let verifiedBy: User
    
    /// When the decision was made.
    let verifiedAt: Date
    
    /// The decision: "Approved" or "Rejected".
    let decision: String
    
    /// If rejected, the reason why (will trigger remediation).
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

struct Patient: Identifiable, Hashable, Codable {
    let id: UUID
    var name: String
    var floor: String
    var room: String
    var bed: String?
    
    init(
        id: UUID,
        name: String,
        floor: String,
        room: String,
        bed: String? = nil
    ) {
        self.id = id
        self.name = name
        self.floor = floor
        self.room = room
        self.bed = bed
    }
}

struct CompoundOrder: Identifiable, Hashable, Codable {
    let id: UUID
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
    var currentStepIndex: Int = 0
    var remediation: RemediationRequest? = nil
    
    /// The verification record (who approved/rejected and when).
    /// Non-nil once verification has occurred.
    var verificationRecord: VerificationRecord? = nil
    
    /// Audit trail of all scannable/verifiable actions on this order.
    var auditEvents: [AuditEvent] = []
    
    var finalContainerKind: ContainerKind? {
        // Normalize: lowercase, unify separators to single spaces, collapse runs.
        let normalized = finalContainer
            .lowercased()
            .replacingOccurrences(of: #"[-_/.,]"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)

        guard !normalized.isEmpty else { return nil }

        // Whole-word / boundary match via regex. Patterns are tried in priority order.
        func matches(_ pattern: String) -> Bool {
            normalized.range(of: pattern, options: .regularExpression) != nil
        }

        // 1. CADD / elastomeric / ambulatory devices — most specific, check first.
        let caddPattern = #"\b(cadd|elastomeric|elastomer|homepump|easypump|infusor|intermate|eclipse|folfusor|ambulatory\s*pump|(pump|medication|reservoir)\s*cassette|cassette\s*reservoir)\b"#
        if matches(caddPattern) { return .CADD }

        // 2. Syringe — luer/prefilled/branded syringe systems.
        let syringePattern = #"\b(syringe|syr|luer(\s*(lock|slip|oral))?|prefilled\s*syringe|pca\s*syringe|tubex|carpuject)\b"#
        if matches(syringePattern) { return .Syringe }

        // 3. IV piggyback / minibag / volume bags.
        //    \bns\b and \bd5w?\b are now safe because of word boundaries.
        let ivpbPattern = #"\b(ivpb|piggy\s*back|piggy|mini\s*bag|viaflex|viaflo|excel|freeflex|lvp|svp|iv\s*bag|infusion\s*bag|bag|ns|nacl|normal\s*saline|saline|d5w?|d10w?|\d+\s*ml)\b"#
        if matches(ivpbPattern) { return .IVPB }

        // 4. Present but unrecognized.
        return .Other
    }

    /// Components whose scanned lots fully cover their target quantity.
    var fulfilledComponents: [CompoundComponent] {
        components.filter { $0.isFulfilled() }
    }

    var fulfilledComponentCount: Int {
        fulfilledComponents.count
    }

    /// Components that still need at least one more lot or more quantity.
    var unfulfilledComponents: [CompoundComponent] {
        components.filter { !$0.isFulfilled() }
    }

    var allComponentsFulfilled: Bool {
        !components.isEmpty && unfulfilledComponents.isEmpty
    }

    /// Whether captures can still be edited/deleted (locked once handed off
    /// to verification or beyond).
    var captureMutationsAllowed: Bool {
        switch status {
        case .pending, .compounding, .remediation:
            return true
        case .readyForVerification, .approved, .rejected:
            return false
        }
    }

    /// Parsed recipe steps. Strips leading numbering like "1." or "1)".
    var recipeSteps: [String] {
        recipeText
            .split(whereSeparator: \.isNewline)
            .map { line -> String in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                // Strip leading "N." or "N)" if present
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

    var totalStepCount: Int {
        recipeSteps.count
    }
    
    /// Summary of verification status for display.
    var verificationStatus: String {
        if let record = verificationRecord {
            let decision = record.isApproved ? "✓ Approved" : "✗ Rejected"
            return "\(decision) by \(record.verifiedBy.username) on \(record.verifiedAt.formatted(date: .abbreviated, time: .standard))"
        } else if status == .readyForVerification {
            return "Awaiting verification"
        } else {
            return "Not yet submitted for verification"
        }
    }
    
    /// True if any component has a pending (un-cosigned) override.
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
