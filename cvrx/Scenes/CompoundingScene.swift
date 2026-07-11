import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
#if canImport(UIKit)
import UIKit
#endif

private struct PendingCompoundingStepChange: Identifiable {
    let id = UUID()
    let stepIndex: Int
}

struct CompoundingScene: View {
    var order: CSPOrder
    @Environment(\.currentUser) var user
    let store: CompoundingStore

    @State private var camera = CameraController()
    @State private var cameraErrorMessage: String?
    @State private var showRecipeSheet = false
    @State private var showGridSheet = false
    @State private var showUploadSelector = false

    // Upload flow state
    @State private var uploadKindForPicker: CaptureKind = .reference
    @State private var showPhotoPicker = false
    @State private var pickedPhotoItem: PhotosPickerItem?
    @State private var showFileImporter = false
    @State private var isUploading = false
    @State private var uploadErrorMessage: String?

    @State private var isCapturing = false
    @State private var pendingStepChange: PendingCompoundingStepChange?
    @State private var captureTask: Task<Void, Never>?
    @State private var lockRefreshTask: Task<Void, Never>?
    @State private var ownsSceneAcquiredLock = false

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        content
            .navigationTitle("Capture")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Done") { dismiss() }
                        .bold()
                }
            }
            .task {
                await acquireLockAndStartCamera()
            }
            .onDisappear {
                tearDownScene()
            }
            .sheet(isPresented: $showRecipeSheet) {
                recipeSheet
            }
            .sheet(isPresented: $showGridSheet) {
                capturedGridSheet
            }
            .confirmationDialog(
                "Upload Image",
                isPresented: $showUploadSelector,
                titleVisibility: .visible
            ) {
                uploadSourceButtons
            }
            .photosPicker(
                isPresented: $showPhotoPicker,
                selection: $pickedPhotoItem,
                matching: .images,
                photoLibrary: .shared()
            )
            .onChange(of: pickedPhotoItem) { _, newItem in
                guard let newItem else { return }
                handlePickedPhotoItem(newItem, kind: uploadKindForPicker)
            }
            .fileImporter(
                isPresented: $showFileImporter,
                allowedContentTypes: [.image, .jpeg, .png, .heic],
                allowsMultipleSelection: false
            ) { result in
                handleFileImporterResult(result, kind: uploadKindForPicker)
            }
            .alert(
                "Upload Failed",
                isPresented: Binding(
                    get: { uploadErrorMessage != nil },
                    set: { if !$0 { uploadErrorMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) { uploadErrorMessage = nil }
            } message: {
                Text(uploadErrorMessage ?? "")
            }
            .alert(
                "Unexpected Component",
                isPresented: Binding(
                    get: { pendingStepChange != nil },
                    set: { if !$0 { pendingStepChange = nil } }
                )
            ) {
                Button("Cancel", role: .cancel) { pendingStepChange = nil }
                Button("Acknowledge") {
                    if let stepIndex = pendingStepChange?.stepIndex {
                        performStepChange(stepIndex)
                    }
                    pendingStepChange = nil
                }
            } message: {
                Text(unexpectedComponentWarningText)
            }
    }

    private var content: some View {
        ZStack {
            CameraPreview(session: camera.session)
                .ignoresSafeArea()
                .overlay(alignment: .center) {
                    if !camera.isConfigured {
                        CameraUnavailableView(message: cameraErrorMessage ?? "Camera is not configured.")
                    }
                }

            VStack(spacing: 0) {
                CurrentStepPill(order: order)
                    .padding(.horizontal)
                    .padding(.top, 8)

                Spacer()

                if !order.captures.isEmpty {
                    InCameraReferenceGrid(captures: order.captures, order: order)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 10)
                }

                CameraControlBar(
                    isCapturing: isCapturing,
                    onCaptureReference: { capture(.reference) },
                    onCaptureAux: { capture(.auxiliary) },
                    onRecipe: { showRecipeSheet = true },
                    onGrid: { showGridSheet = true },
                    onUploadImage: { showUploadSelector = true }
                )
                .disabled(!canEditOrder)
                .padding(.horizontal)
                .padding(.bottom, 12)
            }

            if isUploading {
                Color.black.opacity(0.35).ignoresSafeArea()
                ProgressView("Uploading…")
                    .padding(20)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
            }

            if order.isLockedByOther(than: user) {
                Color.white.opacity(0.55).ignoresSafeArea()
                LockedOrderOverlay(order: order, onBreakLock: breakLock)
                    .padding(24)
            }
        }
    }

    private var recipeSheet: some View {
        RecipeStepsSheet(
            order: order,
            currentUser: user,
            canMutate: canEditOrder,
            onSelectStep: requestStepChange
        )
        .presentationDetents([.medium, .large])
    }

    private var capturedGridSheet: some View {
        CapturedGridSheet(
            captures: order.captures,
            order: order,
            currentUser: user,
            canMutate: canEditOrder,
            onDeleteCapture: deleteCapture,
            onAddPreparerPin: addPreparerPinAction,
            onRemovePreparerPin: removePreparerPinAction
        )
        .presentationDetents([.medium, .large])
    }

    private var addPreparerPinAction: ((CompoundCapture, Double, Double, String?) -> Void)? {
        guard canEditOrder else { return nil }
        return { capture, x, y, note in
            addPreparerPin(capture: capture, x: x, y: y, note: note)
        }
    }

    private var removePreparerPinAction: ((CompoundCapture, CaptureFlag) -> Void)? {
        { capture, flag in
            removePreparerPin(capture: capture, flag: flag)
        }
    }

    @ViewBuilder
    private var uploadSourceButtons: some View {
        Button("Reference — Camera Roll") {
            uploadKindForPicker = .reference
            showPhotoPicker = true
        }
        Button("Reference — Files") {
            uploadKindForPicker = .reference
            showFileImporter = true
        }
        Button("Aux — Camera Roll") {
            uploadKindForPicker = .auxiliary
            showPhotoPicker = true
        }
        Button("Aux — Files") {
            uploadKindForPicker = .auxiliary
            showFileImporter = true
        }
        Button("Cancel", role: .cancel) {}
    }

    private var canEditOrder: Bool {
        guard order.captureMutationsAllowed else { return false }
        return order.isLocked(by: user)
    }

    private func acquireLockAndStartCamera() async {
        acquireLockIfPossible()
        if let user, canEditOrder {
            store.beginPreparing(orderID: order.id, by: user)
        }
        do {
            try await camera.configure()
            camera.start()
        } catch {
            cameraErrorMessage = error.localizedDescription
        }
    }

    private func tearDownScene() {
        captureTask?.cancel()
        stopLockRefresh()
        if ownsSceneAcquiredLock, let user {
            store.releaseOrderLock(orderID: order.id, by: user)
        }
        camera.stop()
    }

    private func deleteCapture(_ capture: CompoundCapture) {
        guard let user, canEditOrder else { return }
        store.deleteCapture(orderID: order.id, captureID: capture.id, deletedBy: user)
    }

    private func removePreparerPin(capture: CompoundCapture, flag: CaptureFlag) {
        guard let user, canEditOrder else { return }
        store.removePreparerFlag(orderID: order.id, captureID: capture.id, flagID: flag.id, removedBy: user)
    }

    private func acquireLockIfPossible() {
        guard let user, order.captureMutationsAllowed else { return }
        let alreadyOwned = order.isLocked(by: user)
        guard store.acquireOrderLock(orderID: order.id, by: user) else { return }
        ownsSceneAcquiredLock = !alreadyOwned
        startLockRefresh()
    }

    private func breakLock() {
        guard let user else { return }
        guard store.acquireOrderLock(orderID: order.id, by: user, breakingExisting: true) else { return }
        ownsSceneAcquiredLock = true
        startLockRefresh()
    }

    private func startLockRefresh() {
        guard let user else { return }
        stopLockRefresh()
        lockRefreshTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(10))
                guard !Task.isCancelled else { return }
                store.refreshOrderLock(orderID: order.id, by: user)
            }
        }
    }

    private func stopLockRefresh() {
        lockRefreshTask?.cancel()
        lockRefreshTask = nil
    }

    // MARK: - Capture

    private func addPreparerPin(
        capture: CompoundCapture,
        x: Double,
        y: Double,
        note: String?
    ) {
        guard let user, canEditOrder else {
            cameraErrorMessage = "No signed-in user or active lock — cannot add a pin."
            return
        }

        store.addPreparerFlag(
            orderID: order.id,
            captureID: capture.id,
            x: x,
            y: y,
            note: note,
            createdBy: user
        )
    }

    private func capture(_ kind: CaptureKind) {
        guard !isCapturing else { return }
        guard let user, canEditOrder else {
            cameraErrorMessage = "No signed-in user or active lock — cannot record capture."
            return
        }

        isCapturing = true
        captureTask = Task {
            defer { isCapturing = false }

            do {
                let imageURL = try await camera.capturePhoto(orderID: order.id, kind: kind)
                guard !Task.isCancelled else { return }

                store.addCapture(
                    orderID: order.id,
                    kind: kind,
                    imageURL: imageURL,
                    capturedBy: user
                )

                advanceStepAfterCapture(kind: kind)
                captureFeedback(success: true)
            } catch {
                guard !Task.isCancelled else { return }

                cameraErrorMessage = error.localizedDescription
                store.addCapture(
                    orderID: order.id,
                    kind: kind,
                    imageURL: nil,
                    capturedBy: user
                )
                captureFeedback(success: false)
            }
        }
    }

    private func advanceStepAfterCapture(kind: CaptureKind) {
        guard kind == .reference else { return }
        let next = order.currentStepIndex + 1
        guard next < order.totalStepCount else { return }
        requestStepChange(next)
    }

    private func requestStepChange(_ stepIndex: Int) {
        guard canEditOrder, order.recipeSteps.indices.contains(stepIndex) else { return }
        if order.hasUnexpectedComponents {
            pendingStepChange = PendingCompoundingStepChange(stepIndex: stepIndex)
        } else {
            performStepChange(stepIndex)
        }
    }

    private func performStepChange(_ stepIndex: Int) {
        guard let user, canEditOrder, order.recipeSteps.indices.contains(stepIndex) else { return }
        store.setCurrentStep(orderID: order.id, stepIndex: stepIndex, changedBy: user)
    }

    private var unexpectedComponentWarningText: String {
        let names = order.unexpectedComponents.map(\.product.name).joined(separator: ", ")
        return "This order includes unexpected component(s): \(names). Acknowledge that these products are actually being used before changing stages."
    }

    private func captureFeedback(success: Bool) {
        #if os(iOS)
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(success ? .success : .error)
        #endif
    }

    // MARK: - Upload handling

    /// Loads image data from a PhotosPicker selection, writes it to the same
    /// on-disk location scheme the camera uses, and records it as a capture.
    private func handlePickedPhotoItem(_ item: PhotosPickerItem, kind: CaptureKind) {
        guard let user, canEditOrder else {
            uploadErrorMessage = "No signed-in user or active lock — cannot record upload."
            pickedPhotoItem = nil
            return
        }

        isUploading = true
        Task {
            defer {
                isUploading = false
                pickedPhotoItem = nil
            }
            do {
                guard let data = try await item.loadTransferable(type: Data.self) else {
                    throw UploadError.emptySelection
                }
                let imageURL = try await camera.saveImportedImage(
                    data: data,
                    orderID: order.id,
                    kind: kind
                )

                store.addCapture(
                    orderID: order.id,
                    kind: kind,
                    imageURL: imageURL,
                    capturedBy: user
                )
                advanceStepAfterCapture(kind: kind)
                captureFeedback(success: true)
            } catch {
                uploadErrorMessage = error.localizedDescription
                store.addCapture(
                    orderID: order.id,
                    kind: kind,
                    imageURL: nil,
                    capturedBy: user
                )
                captureFeedback(success: false)
            }
        }
    }

    /// Handles a file picked from the Files/Finder importer. Requires
    /// security-scoped resource access since the file may live outside the
    /// app's sandbox (iCloud Drive, external volumes, etc).
    private func handleFileImporterResult(_ result: Result<[URL], Error>, kind: CaptureKind) {
        guard let user, canEditOrder else {
            uploadErrorMessage = "No signed-in user or active lock — cannot record upload."
            return
        }

        switch result {
        case .failure(let error):
            uploadErrorMessage = error.localizedDescription
        case .success(let urls):
            guard let sourceURL = urls.first else { return }

            isUploading = true
            Task {
                defer { isUploading = false }
                do {
                    let didAccess = sourceURL.startAccessingSecurityScopedResource()
                    defer { if didAccess { sourceURL.stopAccessingSecurityScopedResource() } }

                    let data = try Data(contentsOf: sourceURL)
                    let imageURL = try await camera.saveImportedImage(
                        data: data,
                        orderID: order.id,
                        kind: kind
                    )

                    store.addCapture(
                        orderID: order.id,
                        kind: kind,
                        imageURL: imageURL,
                        capturedBy: user
                    )
                    advanceStepAfterCapture(kind: kind)
                    captureFeedback(success: true)
                } catch {
                    uploadErrorMessage = error.localizedDescription
                    store.addCapture(
                        orderID: order.id,
                        kind: kind,
                        imageURL: nil,
                        capturedBy: user
                    )
                    captureFeedback(success: false)
                }
            }
        }
    }

    private enum UploadError: LocalizedError {
        case emptySelection
        var errorDescription: String? {
            switch self {
            case .emptySelection: return "The selected photo couldn't be loaded."
            }
        }
    }
}

// MARK: - Top "current step" pill

struct CurrentStepPill: View {
    let order: CSPOrder

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(order.totalStepCount > 0
                 ? "STEP \(order.currentStepNumber) / \(order.totalStepCount)"
                 : "STEP")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.white.opacity(0.75))
                .tracking(0.6)

            Text(order.currentStepText.isEmpty ? "No current step" : order.currentStepText)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.black.opacity(0.55))
        )
    }
}

// MARK: - In-camera reference grid

struct InCameraReferenceGrid: View {
    let captures: [CompoundCapture]
    let order: CSPOrder

    private let thumbSize: CGFloat = 64
    private let spacing: CGFloat = 8

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: spacing) {
                ForEach(captures) { capture in
                    CaptureThumbnailImage(
                        capture: capture,
                        size: thumbSize,
                        badge: order.badge(for: capture)
                    )
                }
            }
            .padding(8)
        }
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.black.opacity(0.45))
        )
    }
}

// MARK: - Camera control bar

struct CameraControlBar: View {
    var isCapturing: Bool = false
    let onCaptureReference: () -> Void
    let onCaptureAux: () -> Void
    let onRecipe: () -> Void
    let onGrid: () -> Void
    let onUploadImage: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            CircleIconButton(systemImage: "list.number", action: onRecipe)
                .accessibilityLabel("Recipe steps")
                .disabled(isCapturing)

            CircleIconButton(systemImage: "square.and.arrow.up", action: onUploadImage)
                .accessibilityLabel("Upload image")
                .disabled(isCapturing)

            CaptureButton( title: "Reference", systemImage: "camera.macro", action: onCaptureReference )
                .frame(maxWidth: .infinity)
                .disabled(isCapturing)

            CaptureButton( title: "Aux", systemImage: "camera.filters", action: onCaptureAux )
                .frame(maxWidth: .infinity)
                .disabled(isCapturing)

            CircleIconButton(systemImage: "square.grid.2x2", action: onGrid)
                .accessibilityLabel("Captured grid")
                .disabled(isCapturing)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .opacity(isCapturing ? 0.6 : 1.0)
        .overlay {
            if isCapturing {
                ProgressView()
                    .controlSize(.large)
            }
        }
        .animation(.easeInOut(duration: 0.15), value: isCapturing)
    }
}

struct CircleIconButton: View {
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.title3)
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.bordered)
        .clipShape(Circle())
    }
}

// MARK: - Sheets

struct RecipeStepsSheet: View {
    let order: CSPOrder
    let currentUser: User?
    var canMutate: Bool = true
    let onSelectStep: (Int) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(Array(order.recipeSteps.enumerated()), id: \.offset) { idx, step in
                    Button {
                        guard currentUser != nil, canMutate else { return }
                        onSelectStep(idx)
                        dismiss()
                    } label: {
                        RecipeStepRow(
                            index: idx,
                            text: step,
                            isCurrent: idx == order.currentStepIndex,
                            accessory: .selectionIcon,
                            textFont: .body,
                            horizontalPadding: nil,
                            verticalPadding: 4
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(!canMutate)
                }
            }
            .navigationTitle("Recipe")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

struct CapturedGridSheet: View {
    let captures: [CompoundCapture]
    let order: CSPOrder
    var currentUser: User? = nil
    var canMutate: Bool = true
    let onDeleteCapture: (CompoundCapture) -> Void
    var onAddPreparerPin: ((CompoundCapture, Double, Double, String?) -> Void)? = nil
    var onRemovePreparerPin: ((CompoundCapture, CaptureFlag) -> Void)? = nil

    @State private var viewer: CompoundCapture?
    @Environment(\.dismiss) private var dismiss

    private let columns: [GridItem] = [
        GridItem(.adaptive(minimum: 96), spacing: 8)
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                if captures.isEmpty {
                    ContentUnavailableView("No Images Yet", systemImage: "photo.on.rectangle")
                        .padding(.top, 60)
                } else {
                    LazyVGrid(columns: columns, spacing: 8) {
                        ForEach(captures) { capture in
                            Button {
                                viewer = capture
                            } label: {
                                CaptureThumbnailImage(
                                    capture: capture,
                                    size: 96,
                                    badge: order.badge(for: capture)
                                )
                                .aspectRatio(1, contentMode: .fit)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Captured (\(captures.count))")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(item: $viewer) { capture in
                CaptureViewerSheet(
                    capture: capture,
                    badge: order.badge(for: capture),
                    canDelete: canMutate,
                    onDelete: {
                        onDeleteCapture(capture)
                        viewer = nil
                    },
                    currentUser: currentUser,
                    onAddPreparerPin: canMutate ? { x, y, note in
                        onAddPreparerPin?(capture, x, y, note)
                    } : nil,
                    onRemovePreparerPin: canMutate ? { flag in
                        onRemovePreparerPin?(capture, flag)
                    } : nil
                )
            }
        }
    }
}
