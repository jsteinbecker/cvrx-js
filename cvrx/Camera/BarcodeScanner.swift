import SwiftUI
import AVFoundation

@Observable
final class BarcodeScannerController: NSObject {
    let session = AVCaptureSession()

    var isConfigured = false
    var errorMessage: String?
    var detectedBounds: CGRect?

    private let sessionQueue = DispatchQueue(label: "rxcompound.barcode.session")
    private let metadataOutput = AVCaptureMetadataOutput()
    private var sessionReady = false
    private var lastScannedValue: String?
    private var lastScanDate = Date.distantPast
    private var onScan: ((String) -> Void)?

    func configure(onScan: @escaping (String) -> Void) async {
        self.onScan = onScan

        let authorized = await requestCameraAuthorization()
        guard authorized else {
            await MainActor.run { errorMessage = CameraError.authorizationDenied.localizedDescription }
            return
        }

        do {
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
            await MainActor.run {
                isConfigured = true
                errorMessage = nil
            }
        } catch {
            await MainActor.run { errorMessage = error.localizedDescription }
        }
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

    @MainActor
    private func handleDetectedBarcode(_ value: String) {
        let now = Date()
        guard value != lastScannedValue || now.timeIntervalSince(lastScanDate) > 1.5 else { return }
        lastScannedValue = value
        lastScanDate = now
        onScan?(value)
    }

    private func configureSession() throws {
        guard !sessionReady else { return }

        session.beginConfiguration()
        defer { session.commitConfiguration() }

        session.sessionPreset = .high

        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
            ?? AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .unspecified)
        else {
            throw CameraError.noCameraAvailable
        }

        let input = try AVCaptureDeviceInput(device: camera)
        guard session.canAddInput(input) else { throw CameraError.cannotAddInput }
        session.addInput(input)

        guard session.canAddOutput(metadataOutput) else { throw CameraError.cannotAddOutput }
        session.addOutput(metadataOutput)
        metadataOutput.setMetadataObjectsDelegate(self, queue: sessionQueue)

        let requestedTypes: [AVMetadataObject.ObjectType] = [
            .code128,
            .dataMatrix,
            .ean13,
            .ean8,
            .upce,
            .code39,
            .code93,
            .itf14,
            .qr,
            .pdf417,
            .aztec
        ]
        metadataOutput.metadataObjectTypes = requestedTypes.filter { metadataOutput.availableMetadataObjectTypes.contains($0) }
    }
}

extension BarcodeScannerController: AVCaptureMetadataOutputObjectsDelegate {
    nonisolated func metadataOutput(
        _ output: AVCaptureMetadataOutput,
        didOutput metadataObjects: [AVMetadataObject],
        from connection: AVCaptureConnection
    ) {
        guard let object = metadataObjects.first as? AVMetadataMachineReadableCodeObject else {
            Task { @MainActor in detectedBounds = nil }
            return
        }

        let bounds = object.bounds
        Task { @MainActor in detectedBounds = bounds }

        guard let value = object.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return }

        Task { @MainActor in handleDetectedBarcode(value) }
    }
}

struct BarcodeScanner: View {
    var onScan: (String) -> Void

    @State private var controller = BarcodeScannerController()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            cameraArea
                .frame(height: 280)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                )

            HStack(spacing: 8) {
                Image(systemName: controller.isConfigured ? "barcode.viewfinder" : "camera.viewfinder")
                    .foregroundStyle(controller.errorMessage == nil ? Color.accentColor : Color.red)
                    .frame(width: 22)

                Text(statusText)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(controller.errorMessage == nil ? Color.secondary : Color.red)
                    .lineLimit(2)

                Spacer(minLength: 0)
            }
        }
        .task {
            await controller.configure(onScan: onScan)
            controller.start()
        }
        .onDisappear { controller.stop() }
    }

    private var cameraArea: some View {
        ZStack {
            if controller.isConfigured {
                CameraPreview(session: controller.session)
                    .overlay { scannerOverlay }
            } else {
                Rectangle()
                    .fill(Color.black.opacity(0.86))
                    .overlay {
                        ProgressView()
                            .tint(.white)
                    }
            }
        }
        .background(Color.black)
    }

    private var scannerOverlay: some View {
        GeometryReader { proxy in
            ZStack {
                Color.black.opacity(0.18)

                scanningGuide(in: proxy.size)

                if let bounds = controller.detectedBounds {
                    barcodeBounds(bounds, in: proxy.size)
                }
            }
        }
    }

    private func scanningGuide(in size: CGSize) -> some View {
        let guideWidth = min(size.width * 0.78, 420)
        let guideHeight = min(size.height * 0.42, 130)

        return RoundedRectangle(cornerRadius: 8, style: .continuous)
            .strokeBorder(Color.white.opacity(0.9), style: StrokeStyle(lineWidth: 2, dash: [10, 8]))
            .frame(width: guideWidth, height: guideHeight)
            .shadow(color: .black.opacity(0.45), radius: 6, x: 0, y: 2)
            .position(x: size.width / 2, y: size.height / 2)
    }

    private func barcodeBounds(_ normalizedBounds: CGRect, in size: CGSize) -> some View {
        let rect = CGRect(
            x: normalizedBounds.minX * size.width,
            y: normalizedBounds.minY * size.height,
            width: normalizedBounds.width * size.width,
            height: normalizedBounds.height * size.height
        )

        return RoundedRectangle(cornerRadius: 5, style: .continuous)
            .strokeBorder(Color.green, lineWidth: 3)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color.green.opacity(0.14))
            )
            .frame(width: max(rect.width, 24), height: max(rect.height, 24))
            .position(x: rect.midX, y: rect.midY)
            .animation(.easeOut(duration: 0.12), value: rect)
    }

    private var statusText: String {
        if let errorMessage = controller.errorMessage {
            return errorMessage
        }
        if controller.detectedBounds != nil {
            return "Barcode focused"
        }
        return "Center the vial or package barcode in the frame"
    }
}
