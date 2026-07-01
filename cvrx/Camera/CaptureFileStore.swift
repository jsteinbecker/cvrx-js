import Foundation

enum CaptureFileStore {
    nonisolated static func savePhotoData(_ data: Data, orderID: CSPOrder.ID, kind: CaptureKind, timestamp: Date) throws -> URL {
        let directory = try captureDirectory(orderID: orderID)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let safeTimestamp = formatter.string(from: timestamp)
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: ".", with: "-")
        let filename = "\(safeTimestamp)_\(kind.rawValue.lowercased()).jpg"
        let url = directory.appendingPathComponent(filename)
        try data.write(to: url, options: [.atomic])
        return url
    }

    nonisolated static func captureDirectory(orderID: CSPOrder.ID) throws -> URL {
        let base = try FileManager.default.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )

        let directory = base
            .appendingPathComponent("CompoundCaptures", isDirectory: true)
            .appendingPathComponent(orderID.uuidString, isDirectory: true)

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
