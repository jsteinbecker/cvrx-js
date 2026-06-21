import SwiftUI
import AVFoundation

@Observable
final class CameraController: NSObject {
    let session = AVCaptureSession()

    private let sessionQueue = DispatchQueue(label: "rxcompound.camera.session")
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

    func capturePhoto(orderID: CompoundOrder.ID, kind: CaptureKind) async throws -> URL {
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
}
