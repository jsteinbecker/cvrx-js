import Foundation

// MARK: - Capture Flag (pin on remediation image)

/// A single pin placed on a capture during remediation. Position is normalized
/// to [0, 1] in both axes so it renders consistently regardless of the
/// container size used to display the image.
struct CaptureFlag: Identifiable, Hashable, Codable {
    let id: UUID
    var captureID: UUID
    var x: Double
    var y: Double

    init(id: UUID = UUID(), captureID: UUID, x: Double, y: Double) {
        self.id = id
        self.captureID = captureID
        self.x = x
        self.y = y
    }
}

// MARK: - Remediation Capture

/// An image captured during remediation to document a fix.
/// Separate from original CompoundCapture so we can distinguish
/// problem documentation (original) from solution documentation (remediation).
struct RemediationCapture: Identifiable, Hashable, Codable {
    let id: UUID
    let remediationRequestID: UUID
    let capturedBy: User
    let capturedAt: Date
    var imageURL: URL?
    var imageName: String?
    var note: String?

    init(
        id: UUID = UUID(),
        remediationRequestID: UUID,
        capturedBy: User,
        capturedAt: Date = Date(),
        imageURL: URL? = nil,
        imageName: String? = nil,
        note: String? = nil
    ) {
        self.id = id
        self.remediationRequestID = remediationRequestID
        self.capturedBy = capturedBy
        self.capturedAt = capturedAt
        self.imageURL = imageURL
        self.imageName = imageName
        self.note = note
    }
}

// MARK: - Remediation Lot Change

/// A change made to a lot during remediation (e.g., replaced, re-scanned, lot data corrected).
struct RemediationLotChange: Identifiable, Hashable, Codable {
    let id: UUID
    let remediationRequestID: UUID
    let componentID: UUID
    let lotID: UUID
    let changeType: String
    let madeBy: User
    let madeAt: Date
    var description: String?

    init(
        id: UUID = UUID(),
        remediationRequestID: UUID,
        componentID: UUID,
        lotID: UUID,
        changeType: String,
        madeBy: User,
        madeAt: Date = Date(),
        description: String? = nil
    ) {
        self.id = id
        self.remediationRequestID = remediationRequestID
        self.componentID = componentID
        self.lotID = lotID
        self.changeType = changeType
        self.madeBy = madeBy
        self.madeAt = madeAt
        self.description = description
    }
    
    var summary: String {
        let desc = description.map { " — \($0)" } ?? ""
        return "\(changeType)\(desc) [by \(madeBy.username)]"
    }
}

// MARK: - Remediation Request

/// A remediation request raised during verification. One shared reason
/// describes what needs fixing; pins on captures highlight specific locations.
///
/// A remediation spans from request through resubmission and includes
/// who requested it, who completed it, what changed during remediation,
/// and what images were captured to document the fixes.
struct RemediationRequest: Identifiable, Hashable, Codable {
    let id: UUID
    let requestedBy: User
    let requestedAt: Date
    var reason: String
    var flags: [CaptureFlag]
    var completedBy: User?
    var completedAt: Date?
    var remediationCaptures: [RemediationCapture]
    var lotChanges: [RemediationLotChange]

    init(
        id: UUID = UUID(),
        requestedBy: User,
        requestedAt: Date = Date(),
        reason: String,
        flags: [CaptureFlag] = [],
        completedBy: User? = nil,
        completedAt: Date? = nil,
        remediationCaptures: [RemediationCapture] = [],
        lotChanges: [RemediationLotChange] = []
    ) {
        self.id = id
        self.requestedBy = requestedBy
        self.requestedAt = requestedAt
        self.reason = reason
        self.flags = flags
        self.completedBy = completedBy
        self.completedAt = completedAt
        self.remediationCaptures = remediationCaptures
        self.lotChanges = lotChanges
    }

    /// Unique captures that have at least one pin.
    var flaggedCaptureIDs: Set<UUID> {
        Set(flags.map(\.captureID))
    }

    func pins(for captureID: UUID) -> [CaptureFlag] {
        flags.filter { $0.captureID == captureID }
    }
    
    /// True if remediation has been completed and resubmitted.
    var isCompleted: Bool { completedBy != nil && completedAt != nil }
    
    /// Summary of what was done during remediation.
    var remediationSummary: String {
        var parts: [String] = []
        
        if !remediationCaptures.isEmpty {
            parts.append("\(remediationCaptures.count) remediation image(s)")
        }
        if !lotChanges.isEmpty {
            parts.append("\(lotChanges.count) lot change(s)")
        }
        
        if isCompleted {
            parts.append("completed by \(completedBy?.username ?? "unknown")")
        }
        
        return parts.joined(separator: ", ")
    }
}
