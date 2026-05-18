import Foundation

/// An image captured during compounding.
/// Records who took the photo, what kind it is, and when.
struct CompoundCapture: Identifiable, Hashable, Codable {
    let id: UUID
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

    init(
        id: UUID = UUID(),
        kind: CaptureKind,
        capturedBy: User? = nil,
        timestamp: Date = Date(),
        imageURL: URL? = nil,
        imageName: String? = nil,
        note: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.capturedBy = capturedBy
        self.timestamp = timestamp
        self.imageURL = imageURL
        self.imageName = imageName
        self.note = note
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
