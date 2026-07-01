import SwiftUI
import AVFoundation

@Observable
final class CameraController: NSObject {
    let session = AVCaptureSession()

    let sessionQueue = DispatchQueue(label: "rxcompound.camera.session")
    private let photoOutput = AVCapturePhotoOutput()

    // The delegates dictionary is mutated from both `capturePhoto` (on
    // sessionQueue) and from the AVFoundation callback (also on an
    // internal queue, but we hop back to sessionQueue before touching
    // this dict). Never touch this dict from MainActor.
    private var photoDelegates: [Int64: PhotoCaptureDelegate] = [:]

    // Internal flag for queue-guarding start(); only touched on sessionQueue.
    @ObservationIgnored private var sessionReady = false

    // SwiftUI-observed flag; must only be mutated on the main thread.
    var isConfigured = false

    func configure() async throws {
        let authorized = await requestCameraAuthorization()
        guard authorized else { throw CameraError.authorizationDenied }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            sessionQueue.async {
                do {
                    try self.configureSession()
                    self.sessionReady = true
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
        // Hop to the main actor so the @Observable mutation is main-thread-safe.
        await MainActor.run { isConfigured = true }
    }

    func start() {
        sessionQueue.async {
            guard self.sessionReady, !self.session.isRunning else { return }
            self.session.startRunning()
        }
    }

    func stop() {
        sessionQueue.async {
            guard self.session.isRunning else { return }
            self.session.stopRunning()
        }
    }

    func capturePhoto(orderID: CSPOrder.ID, kind: CaptureKind) async throws -> URL {
        guard isConfigured else { throw CameraError.notConfigured }

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
            sessionQueue.async {
                guard self.session.isRunning else {
                    continuation.resume(throwing: CameraError.notConfigured)
                    return
                }

                // Force JPEG so PhotoCaptureDelegate.fileDataRepresentation()
                // returns a writable .jpg blob. AVCapturePhotoOutput defaults
                // to HEIF on capable devices, and the file we save with a
                // `.jpg` extension would then be HEIF bytes — confusing for
                // viewers and inconsistent across devices.
                let settings: AVCapturePhotoSettings
                if self.photoOutput.availablePhotoCodecTypes.contains(.jpeg) {
                    settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg])
                } else {
                    settings = AVCapturePhotoSettings()
                }

                // Snapshot the uniqueID *once*. AVCapturePhotoSettings
                // generates a fresh uniqueID per instance; once captured
                // here it is stable for the life of `settings`, but we
                // never re-read it from `settings` in another scope.
                let requestID = settings.uniqueID

                let delegate = PhotoCaptureDelegate(orderID: orderID, kind: kind) { [weak self] result in
                    // Hop back to sessionQueue to mutate photoDelegates,
                    // matching the queue the entry was inserted on.
                    self?.sessionQueue.async {
                        self?.photoDelegates[requestID] = nil
                    }
                    continuation.resume(with: result)
                }

                // Retain the delegate BEFORE handing it to AVFoundation —
                // AVCapturePhotoOutput holds a weak reference, so if we
                // didn't retain it ourselves it could be deallocated
                // before didFinishProcessingPhoto fires.
                self.photoDelegates[requestID] = delegate
                self.photoOutput.capturePhoto(with: settings, delegate: delegate)
            }
        }
    }

    private func requestCameraAuthorization() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .video)
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }

    private func configureSession() throws {
        guard !sessionReady else { return }

        session.beginConfiguration()
        defer { session.commitConfiguration() }

        session.sessionPreset = .photo

        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
            ?? AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .unspecified)
        else {
            throw CameraError.noCameraAvailable
        }

        let input = try AVCaptureDeviceInput(device: camera)
        guard session.canAddInput(input) else { throw CameraError.cannotAddInput }
        session.addInput(input)

        guard session.canAddOutput(photoOutput) else { throw CameraError.cannotAddOutput }
        session.addOutput(photoOutput)
        photoOutput.maxPhotoQualityPrioritization = .quality
    }
    
    /// Persists externally-sourced image data (Photos library or Files) as
        /// a capture. Mirrors `capturePhoto`'s queue discipline even though no
        /// AVFoundation session state is touched here, to keep all photo I/O
        /// serialized through `sessionQueue` and avoid any race with an
        /// in-flight `capturePhoto` call writing to the same order's directory.
        func saveImportedImage(data: Data, orderID: CSPOrder.ID, kind: CaptureKind) async throws -> URL {
            guard isConfigured else { throw CameraError.notConfigured }

            return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
                sessionQueue.async {
                    do {
                        let url = try Self.writeImportedJPEG(
                            data: data,
                            orderID: orderID,
                            kind: kind
                        )
                        continuation.resume(returning: url)
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
        }

        /// Normalizes arbitrary image data (HEIC/PNG/JPEG) to JPEG and writes
        /// it to disk using the SAME directory/naming convention as
        /// `PhotoCaptureDelegate` uses for live captures.
        ///
        /// ⚠️ ASSUMPTION: I don't have `PhotoCaptureDelegate`'s source, so I
        /// can't see exactly how it derives the destination URL for a given
        /// (orderID, kind) pair. Below is a placeholder — swap the body of
        /// `destinationURL(orderID:kind:)` for whatever `PhotoCaptureDelegate`
        /// actually does (e.g. if it asks a `CaptureStorage` helper, or builds
        /// a path under Application Support / Documents). If you paste that
        /// delegate, I'll wire this up exactly instead of guessing.
        private static func writeImportedJPEG(data: Data, orderID: CSPOrder.ID, kind: CaptureKind) throws -> URL {
            let normalizedData: Data
            #if canImport(UIKit)
            guard let image = UIImage(data: data),
                  let jpegData = image.jpegData(compressionQuality: 0.9) else {
                throw CameraError.invalidImageData
            }
            normalizedData = jpegData
            #elseif canImport(AppKit)
            guard let image = NSImage(data: data),
                  let tiff = image.tiffRepresentation,
                  let bitmap = NSBitmapImageRep(data: tiff),
                  let jpegData = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.9]) else {
                throw CameraError.invalidImageData
            }
            normalizedData = jpegData
            #else
            normalizedData = data
            #endif

            let url = try destinationURL(orderID: orderID, kind: kind)
            try normalizedData.write(to: url, options: .atomic)
            return url
        }

        private static func destinationURL(orderID: CSPOrder.ID, kind: CaptureKind) throws -> URL {
            let fm = FileManager.default
            let base = try fm.url(for: .applicationSupportDirectory,
                                   in: .userDomainMask,
                                   appropriateFor: nil,
                                   create: true)
            let orderDir = base
                .appendingPathComponent("Captures", isDirectory: true)
                .appendingPathComponent("\(orderID)", isDirectory: true)
            try fm.createDirectory(at: orderDir, withIntermediateDirectories: true)
            return orderDir.appendingPathComponent("\(kind.rawValue)_\(UUID().uuidString).jpg")
        }
}
