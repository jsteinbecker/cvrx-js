import Foundation
import AVFoundation

final class PhotoCaptureDelegate: NSObject, AVCapturePhotoCaptureDelegate {
    nonisolated let orderID: CompoundOrder.ID
    nonisolated let kind: CaptureKind
    nonisolated let completion: (Result<URL, Error>) -> Void

    init(orderID: CompoundOrder.ID, kind: CaptureKind, completion: @escaping (Result<URL, Error>) -> Void) {
        self.orderID = orderID
        self.kind = kind
        self.completion = completion
    }

    nonisolated func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let error {
            completion(.failure(error))
            return
        }

        guard let data = photo.fileDataRepresentation() else {
            completion(.failure(CameraError.noPhotoData))
            return
        }

        // Save synchronously on the AVFoundation callback queue — do NOT
        // jump to MainActor. Two reasons:
        //
        //   1. Writing several MB of JPEG to disk should not block the UI.
        //   2. Hopping through `Task { @MainActor in ... }` detaches the
        //      save from the continuation's lifetime. If the original
        //      caller's Task is cancelled between the photo callback and
        //      the MainActor hop, the continuation may already be in a
        //      terminal state, and `completion(...)` would either be a
        //      no-op or trigger a "continuation resumed twice" trap.
        //
        // The CaptureFileStore methods are pure file I/O with no UI or
        // SwiftData concerns, so they are safe to call from any queue.
        do {
            let url = try CaptureFileStore.savePhotoData(data, orderID: orderID, kind: kind, timestamp: .now)
            completion(.success(url))
        } catch {
            completion(.failure(error))
        }
    }
}
