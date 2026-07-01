import SwiftData
import Foundation

/// A single pin placed on a capture during remediation. Position is normalized
/// to [0, 1] in both axes so it renders consistently regardless of the
/// container size used to display the image.
@Model
final class CaptureFlag {
    @Attribute(.unique) var id: UUID
    var captureID: UUID
    var x: Double
    var y: Double
    var createdBy: User
    var note: String?

    init(id: UUID = UUID(), captureID: UUID, x: Double, y: Double, createdBy: User, note: String?) {
        self.id = id
        self.captureID = captureID
        self.x = x
        self.y = y
        self.createdBy = createdBy
        self.note = note
    }
}
