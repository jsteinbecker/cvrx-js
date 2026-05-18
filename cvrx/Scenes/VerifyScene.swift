import SwiftUI

/// Verification scene. Built around a large image with carousel navigation,
/// pinch-to-zoom, and quick approve/reject actions.
struct VerifyScene: View {
    @Binding var order: CompoundOrder
    @EnvironmentObject var user: User;
    let store: CompoundingStore

    @State private var rejectionReason = ""
    @State private var showRejectSheet = false
    @State private var showRemediateSheet = false
    @State private var currentIndex = 0

    @Environment(\.dismiss) private var dismiss

    var chronologicalCaptures: [CompoundCapture] {
        order.captures.sorted { $0.timestamp < $1.timestamp }
    }

    var body: some View {
        HStack(spacing: 10) {
            VStack(spacing: 0) {
                Text("Recipe").font(.largeTitle).bold().padding()
                Text(self.order.recipeText)
                Spacer(minLength: 100).frame(maxWidth: .infinity)
                Text("Components").font(.largeTitle).bold().padding()
                ForEach(order.components) { component in
                    VerifyComponentRow(
                        component: component,
                        onAddScan: {
                            // Trigger barcode scanner, lot entry modal, etc.
                        }
                    )
                }
            }
            .containerRelativeFrame(.horizontal, count: 3, span: 1, spacing: 10)

            VStack(spacing: 0) {
                // Order summary header.
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(order.orderNumber)
                            .font(.headline)
                        Spacer()
                        StatusPill(status: order.status)
                    }
                    Text(order.medicationName)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(.bar)

                // Main carousel area.
                if chronologicalCaptures.isEmpty {
                    ContentUnavailableView("No Images Captured", systemImage: "photo.badge.exclamationmark")
                        .frame(maxHeight: .infinity)
                } else {
                    ZoomableCarousel(
                        captures: chronologicalCaptures,
                        currentIndex: $currentIndex,
                        order: order
                    )

                    // Bottom strip: thumbnails for quick jumping.
                    CarouselThumbnailStrip(
                        captures: chronologicalCaptures,
                        currentIndex: $currentIndex,
                        order: order
                    )
                    .padding(.vertical, 8)
                    .background(.bar)

                    // Legend appears only when remediation context makes the
                    // colors meaningful — keeps non-remediation flows uncluttered.
                    if order.remediation != nil {
                        CaptureBadgeLegend(badges: [.flaggedResolved, .addedDuringRemediation])
                            .padding(.horizontal, 16)
                            .padding(.vertical, 6)
                            .background(.bar)
                    }
                }
            }
            .containerRelativeFrame(.horizontal, count: 3, span: 2, spacing: 10)
        }
        
        .navigationTitle("Verify")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 0) {
                Divider()
                HStack(spacing: 10) {
                    Button(role: .destructive) {
                        showRejectSheet = true
                    } label: {
                        Label("Reject", systemImage: "xmark.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)

                    Button {
                        showRemediateSheet = true
                    } label: {
                        Label("Remediate", systemImage: "wrench.adjustable")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(.purple)
                    .disabled(order.captures.isEmpty)

                    Button {
                        store.verify(orderID: order.id, verifiedBy: user, approved: true)
                        dismiss()
                    } label: {
                        Label("Approve", systemImage: "checkmark.seal.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(order.captures.isEmpty)
                }
                .padding()
                .background(.bar)
            }
        }
        .sheet(isPresented: $showRemediateSheet) {
            RemediationComposerSheet(
                captures: chronologicalCaptures,
                initialIndex: currentIndex,
                onCancel: { showRemediateSheet = false },
                onSubmit: { reason, flags in
                    store.createRemediationRequest(orderID: order.id, reason: reason, requestedBy: user)
                    showRemediateSheet = false
                    dismiss()
                }
            )
        }
        .sheet(isPresented: $showRejectSheet) {
            NavigationStack {
                Form {
                    Section("Rejection Reason") {
                        TextField("Describe issue", text: $rejectionReason, axis: .vertical)
                            .lineLimit(3...6)
                    }
                }
                .navigationTitle("Reject Compound")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            showRejectSheet = false
                        }
                    }

                    ToolbarItem(placement: .confirmationAction) {
                        Button("Reject") {
                            store.verify(orderID: order.id, verifiedBy: user, approved: false)
                            showRejectSheet = false
                            dismiss()
                        }
                        .disabled(rejectionReason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
            .presentationDetents([.medium])
        }
    }
}

// MARK: - Zoomable carousel

/// Horizontal-swipe carousel. Each page hosts a pinch/double-tap-to-zoom image.
struct ZoomableCarousel: View {
    let captures: [CompoundCapture]
    @Binding var currentIndex: Int
    /// Source of remediation context; the carousel derives per-capture badges
    /// from this to apply borders and dimming.
    var order: CompoundOrder

    var body: some View {
        VStack(spacing: 0) {
#if os(macOS)
            if captures.indices.contains(currentIndex) {
                let capture = captures[currentIndex]
                ZoomableImageView(
                    capture: capture,
                    badge: order.badge(for: capture)
                )
            }
#else
            TabView(selection: $currentIndex) {
                ForEach(Array(captures.enumerated()), id: \.element.id) { idx, capture in
                    ZoomableImageView(
                        capture: capture,
                        badge: order.badge(for: capture)
                    )
                    .tag(idx)
                }
            }
            // PageTabViewStyle is available on iOS, macOS 11+, watchOS, and
            // tvOS — applying it unconditionally avoids macOS falling back
            // to the default tab-bar style, which would render an empty tab
            // strip above the carousel (one blank tab per capture, since
            // none of the pages declares a `.tabItem`).
            .tabViewStyle(.page(indexDisplayMode: .never))
#endif

            // Footer: index, current-image badge pill, kind label.
            HStack(spacing: 10) {
                Text("\(currentIndex + 1) of \(captures.count)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                if captures.indices.contains(currentIndex) {
                    let badge = order.badge(for: captures[currentIndex])
                    if badge != .none {
                        Label(badge.label, systemImage: badge.icon)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(badge.borderColor)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(badge.borderColor.opacity(0.15)))
                    }
                }

                Spacer()
                if captures.indices.contains(currentIndex) {
                    Label(captures[currentIndex].kind.rawValue,
                          systemImage: captures[currentIndex].kind == .reference
                          ? "doc.viewfinder" : "tag")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 6)
        }
        .background(Color.black.opacity(0.04))
    }
}

/// A single image with pinch-to-zoom, pan, and double-tap-to-toggle-zoom.
/// When a `badge` is set, the page gets a colored border and (for resolved
/// flags) lowered opacity so the verifier can tell at a glance which images
/// need fresh attention vs. which were already addressed.
struct ZoomableImageView: View {
    let capture: CompoundCapture
    var badge: CaptureBadge = .none

    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    private let minScale: CGFloat = 1.0
    private let maxScale: CGFloat = 5.0
    private let doubleTapScale: CGFloat = 2.5

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.opacity(0.02)

                if let url = capture.imageURL {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .empty:
                            ProgressView()
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFit()
                        case .failure:
                            placeholder
                        @unknown default:
                            placeholder
                        }
                    }
                } else {
                    placeholder
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .scaleEffect(scale)
            .offset(offset)
            .opacity(badge.opacity)
            .overlay(
                Rectangle()
                    .strokeBorder(badge.borderColor, lineWidth: badge == .none ? 0 : 4)
                    .allowsHitTesting(false)
            )
            .gesture(
                SimultaneousGesture(
                    MagnificationGesture()
                        .onChanged { value in
                            let newScale = lastScale * value
                            scale = min(max(newScale, minScale), maxScale)
                        }
                        .onEnded { _ in
                            lastScale = scale
                            if scale <= minScale {
                                resetZoom(animated: true)
                            }
                        },
                    DragGesture()
                        .onChanged { value in
                            guard scale > 1.0 else { return }
                            offset = CGSize(
                                width: lastOffset.width + value.translation.width,
                                height: lastOffset.height + value.translation.height
                            )
                        }
                        .onEnded { _ in
                            lastOffset = offset
                        }
                )
            )
            .onTapGesture(count: 2) {
                withAnimation(.spring(response: 0.3)) {
                    if scale > 1.0 {
                        resetZoom(animated: false)
                    } else {
                        scale = doubleTapScale
                        lastScale = doubleTapScale
                    }
                }
            }
            .onChange(of: capture.id) { _, _ in
                resetZoom(animated: false)
            }
            .clipped()
        }
    }

    private func resetZoom(animated: Bool) {
        let apply = {
            scale = minScale
            lastScale = minScale
            offset = .zero
            lastOffset = .zero
        }
        if animated {
            withAnimation(.spring(response: 0.3)) { apply() }
        } else {
            apply()
        }
    }

    private var placeholder: some View {
        VStack(spacing: 8) {
            Image(systemName: "photo")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)
            Text("No image available")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Thumbnail strip

struct CarouselThumbnailStrip: View {
    let captures: [CompoundCapture]
    @Binding var currentIndex: Int
    var order: CompoundOrder

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(captures.enumerated()), id: \.element.id) { idx, capture in
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                currentIndex = idx
                            }
                        } label: {
                            CaptureThumbnailImage(
                                capture: capture,
                                size: 56,
                                badge: order.badge(for: capture)
                            )
                            // Active-selection outline rendered on top of the
                            // badge border so the user can always see which
                            // thumbnail is selected, even when it's also flagged.
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .strokeBorder(
                                        idx == currentIndex ? Color.accentColor : Color.clear,
                                        lineWidth: 3
                                    )
                            )
                            .id(idx)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
            }
            .onChange(of: currentIndex) { _, new in
                withAnimation { proxy.scrollTo(new, anchor: .center) }
            }
        }
    }
}
