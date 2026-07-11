import Foundation
import SwiftData

/// An image captured during compounding.
/// Records who took the photo, what kind it is, and when.
@Model
final class CompoundCapture {
    @Attribute(.unique) var id: UUID
    var cspOrder: CSPOrder?
    /// Type of capture (reference, auxiliary, etc.)
    var kind: CaptureKind
    /// Who captured this image.
    var capturedBy: User?
    /// When the photo was taken.
    var timestamp: Date
    /// The image file reference.
    var imageURL: URL?
    var imageName: String?
    /// Optional note (e.g., "labeled syringe", "vial detail").
    var note: String?
    /// Cached Vision extraction for this image. Nil means it has not been analyzed yet.
    var analysis: CaptureAnalysis?
    var analyzedAt: Date?
    /// Pins placed by the preparer to highlight areas that are difficult to capture clearly.
    var preparerFlags: [CaptureFlag]

    init(
        id: UUID = UUID(),
        cspOrder: CSPOrder? = nil,
        kind: CaptureKind,
        capturedBy: User? = nil,
        timestamp: Date = Date(),
        imageURL: URL? = nil,
        imageName: String? = nil,
        note: String? = nil,
        analysis: CaptureAnalysis? = nil,
        analyzedAt: Date? = nil,
        preparerFlags: [CaptureFlag] = []
    ) {
        self.id = id
        self.cspOrder = cspOrder
        self.kind = kind
        self.capturedBy = capturedBy
        self.timestamp = timestamp
        self.imageURL = imageURL
        self.imageName = imageName
        self.note = note
        self.analysis = analysis
        self.analyzedAt = analyzedAt
        self.preparerFlags = preparerFlags
    }
    
    /// Display name showing who captured and when.
    var captureCredit: String {
        if let user = capturedBy {
            return "\(user.username) on \(timestamp.formatted(date: .abbreviated, time: .standard))"
        } else {
            return "Captured on \(timestamp.formatted(date: .abbreviated, time: .standard))"
        }
    }
}

enum CaptureKind: String, CaseIterable, Hashable, Codable {
    case reference = "Reference"
    case auxiliary = "Aux"
}
