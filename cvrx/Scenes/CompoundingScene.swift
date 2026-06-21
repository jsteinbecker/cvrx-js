import SwiftUI

/// Live camera scene for capturing reference and auxiliary images.
/// Focused purely on capture — verification is reached separately from the
/// Verification tab. "Done" pops back to the order detail.
struct CompoundingScene: View {
    var order: CompoundOrder
    @Environment(\.currentUser) var user
    let store: CompoundingStore

    @State private var camera = CameraController()
    @State private var cameraErrorMessage: String?
    @State private var showRecipeSheet = false
    @State private var showGridSheet = false

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            // Camera fills the screen.
            CameraPreview(session: camera.session)
                .ignoresSafeArea()
                .overlay(alignment: .center) {
                    if !camera.isConfigured {
                        CameraUnavailableView(message: cameraErrorMessage ?? "Camera is not configured.")
                    }
                }

            // Foreground overlays.
            VStack(spacing: 0) {
                // Top: current step pill.
                CurrentStepPill(order: order)
                    .padding(.horizontal)
                    .padding(.top, 8)

                Spacer()

                // Reference grid strip (no names, no times). Hidden when empty.
                if !order.captures.isEmpty {
                    InCameraReferenceGrid(captures: order.captures, order: order)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 10)
                }

                // Bottom bar: capture controls.
                CameraControlBar(
                    onCaptureReference: { capture(.reference) },
                    onCaptureAux: { capture(.auxiliary) },
                    onRecipe: { showRecipeSheet = true },
                    onGrid: { showGridSheet = true }
                )
                .padding(.horizontal)
                .padding(.bottom, 12)
            }
        }
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
            do {
                try await camera.configure()
                camera.start()
            } catch {
                cameraErrorMessage = error.localizedDescription
            }
        }
        .onDisappear {
            camera.stop()
        }
        .sheet(isPresented: $showRecipeSheet) {
            RecipeStepsSheet(order: order, store: store)
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showGridSheet) {
            CapturedGridSheet(
                captures: order.captures,
                order: order,
                onDeleteCapture: { capture in
                    store.deleteCapture(orderID: order.id, captureID: capture.id)
                }
            )
            .presentationDetents([.medium, .large])
        }
    }

    private func capture(_ kind: CaptureKind) {
        Task {
            do {
                let imageURL = try await camera.capturePhoto(orderID: order.id, kind: kind)
                await MainActor.run {
                    store
                        .addCapture(
                            orderID: order.id,
                            kind: kind,
                            imageURL: imageURL,
                            capturedBy: user
                        )
                }
            } catch {
                await MainActor.run {
                    cameraErrorMessage = error.localizedDescription
                    store
                        .addCapture(
                            orderID: order.id,
                            kind: kind,
                            imageURL: nil,
                            capturedBy: user
                        )
                }
            }
        }
    }
}

// MARK: - Top "current step" pill

struct CurrentStepPill: View {
    let order: CompoundOrder

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

// MARK: - In-camera reference grid (no names, no times)

/// Compact horizontal grid of thumbnails shown over the live camera preview.
/// Intentionally minimal: just the images, plus badge borders when a
/// remediation is in progress so the compounder can see at a glance which
/// captures are the new ones they're adding to fix the issue.
struct InCameraReferenceGrid: View {
    let captures: [CompoundCapture]
    let order: CompoundOrder

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
    let onCaptureReference: () -> Void
    let onCaptureAux: () -> Void
    let onRecipe: () -> Void
    let onGrid: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            CircleIconButton(systemImage: "list.number", action: onRecipe)
                .accessibilityLabel("Recipe steps")

            CaptureButton(title: "Reference", systemImage: "camera.macro", action: onCaptureReference)
                .frame(maxWidth: .infinity)

            CaptureButton(title: "Aux", systemImage: "camera.filters", action: onCaptureAux)
                .frame(maxWidth: .infinity)

            CircleIconButton(systemImage: "square.grid.2x2", action: onGrid)
                .accessibilityLabel("Captured grid")
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.ultraThinMaterial)
        )
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
    let order: CompoundOrder
    let store: CompoundingStore

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(Array(order.recipeSteps.enumerated()), id: \.offset) { idx, step in
                    Button {
                        store.setCurrentStep(orderID: order.id, stepIndex: idx)
                        dismiss()
                    } label: {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: idx == order.currentStepIndex
                                  ? "largecircle.fill.circle"
                                  : "circle")
                                .foregroundStyle(idx == order.currentStepIndex ? Color.accentColor : .secondary)
                                .padding(.top, 2)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Step \(idx + 1)")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                Text(step)
                                    .font(.body)
                                    .foregroundStyle(.primary)
                            }
                            Spacer()
                        }
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
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

/// Full-screen-grid variant of the captured images (still no names/times),
/// for browsing within the camera scene. Tap a tile to view it large, with a
/// delete option while the order can still be mutated.
struct CapturedGridSheet: View {
    let captures: [CompoundCapture]
    let order: CompoundOrder
    let onDeleteCapture: (CompoundCapture) -> Void

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
                    canDelete: order.captureMutationsAllowed,
                    onDelete: {
                        onDeleteCapture(capture)
                        viewer = nil
                    }
                )
            }
        }
    }
}
