import SwiftUI

// MARK: - Pin marker

/// A numbered pin used both interactively (composer) and read-only (detail sheet).
/// The marker is offset upward so the visual "point" sits at the tapped location.
struct PinMarker: View {
    let number: Int
    var color: Color = .purple

    var body: some View {
        ZStack {
            Circle()
                .fill(color)
                .frame(width: 28, height: 28)
                .shadow(color: .black.opacity(0.45), radius: 2, x: 0, y: 1)

            Circle()
                .strokeBorder(Color.white, lineWidth: 2)
                .frame(width: 28, height: 28)

            Text("\(number)")
                .font(.caption.weight(.bold).monospacedDigit())
                .foregroundStyle(.white)
        }
        .contentShape(Circle())
    }
}

// MARK: - Pinnable image card (one carousel page)

/// One page in a remediation carousel. Renders the capture and overlays pins
/// at their normalized positions. If `onAddPin` / `onRemovePin` are non-nil
/// the card is interactive (composer); otherwise it's a read-only display.
///
/// Layout strategy: the AsyncImage with explicit `maxWidth/maxHeight: .infinity`
/// is the *base* and defines the card's size. The pin layer is layered on top
/// via `.overlay`, where a `GeometryReader` reads the established size for
/// coordinate math. Doing it the other way around — `GeometryReader` at the
/// root — leaves the card with no intrinsic size inside a `TabView` page, which
/// collapses it to a tiny strip.
struct PinnableImageCard: View {
    let capture: CompoundCapture
    let pins: [CaptureFlag]
    /// Ordinal numbers for these pins relative to the whole set.
    /// Pre-computed by the parent so numbering is consistent across pages.
    let numbering: [UUID: Int]
    var pinColor: Color = .purple
    var onAddPin: ((Double, Double) -> Void)? = nil
    var onRemovePin: ((CaptureFlag) -> Void)? = nil

    var body: some View {
        imageContent
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black.opacity(0.04))
            .overlay {
                // The overlay inherits the base view's size. Inside it,
                // a GeometryReader reads that size to position pins and to
                // convert tap locations into normalized [0,1] coordinates.
                GeometryReader { geo in
                    ZStack(alignment: .topLeading) {
                        // Transparent tap target across the whole image area.
                        // Pins sit above this layer, so a tap on a pin reaches
                        // the pin's gesture (remove); a tap on empty image
                        // area reaches this layer's gesture (add).
                        Color.clear
                            .contentShape(Rectangle())
                            .onTapGesture(coordinateSpace: .local) { location in
                                guard let onAddPin else { return }
                                let w = max(geo.size.width, 1)
                                let h = max(geo.size.height, 1)
                                let nx = Double(location.x / w)
                                let ny = Double(location.y / h)
                                guard (0...1).contains(nx), (0...1).contains(ny) else { return }
                                onAddPin(nx, ny)
                            }

                        ForEach(pins) { pin in
                            PinMarker(number: numbering[pin.id] ?? 0, color: pinColor)
                                .position(
                                    x: CGFloat(pin.x) * geo.size.width,
                                    y: CGFloat(pin.y) * geo.size.height
                                )
                                .onTapGesture {
                                    onRemovePin?(pin)
                                }
                                .allowsHitTesting(onRemovePin != nil)
                        }
                    }
                }
            }
    }

    @ViewBuilder
    private var imageContent: some View {
        if let url = capture.imageURL {
            AsyncImage(url: url) { phase in
                switch phase {
                case .empty:
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
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

    private var placeholder: some View {
        VStack(spacing: 8) {
            Image(systemName: "photo")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)
            Text("No image available")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Composer (verifier flow — pin-based)

/// Modal used by the verifier to compose a remediation request. Shows captures
/// in a swipeable carousel that opens on the image the verifier was last
/// viewing in the main verify carousel. Tap any spot on an image to drop a
/// numbered pin; tap a pin to remove it. A single shared reason text field
/// describes the overall remediation.
struct RemediationComposerSheet: View {
    let captures: [CompoundCapture]
    /// Index in `captures` to open at. The verifier passes the current
    /// index from their main carousel so they land where they left off.
    let initialIndex: Int
    let onCancel: () -> Void
    let onSubmit: (_ reason: String, _ flags: [CaptureFlag]) -> Void

    @State private var reason: String = ""
    @State private var flags: [CaptureFlag] = []
    @State private var currentIndex: Int

    @Environment(\.currentUser) private var user
    @Environment(\.dismiss) private var dismiss

    init(
        captures: [CompoundCapture],
        initialIndex: Int,
        onCancel: @escaping () -> Void,
        onSubmit: @escaping (String, [CaptureFlag]) -> Void
    ) {
        self.captures = captures
        self.initialIndex = initialIndex
        self.onCancel = onCancel
        self.onSubmit = onSubmit
        // Clamp into valid range; State must be initialized once at construction
        // so the carousel renders on the right page from frame zero.
        let clamped = captures.isEmpty
            ? 0
            : min(max(initialIndex, 0), captures.count - 1)
        _currentIndex = State(initialValue: clamped)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                instructionsBar

                carousel
                    .frame(maxHeight: .infinity)

                footerBar

                reasonField
                    .background(Color.rxCardBackground)
            }
            .background(Color.rxGroupedBackground.ignoresSafeArea())
            .navigationTitle("Request Remediation")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onCancel()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Send") {
                        onSubmit(
                            reason.trimmingCharacters(in: .whitespacesAndNewlines),
                            flags
                        )
                        dismiss()
                    }
                    .bold()
                    .disabled(reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    // MARK: subviews

    private var instructionsBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "hand.tap.fill")
                .foregroundStyle(.purple)
            Text("Tap the image to pin a problem. Tap a pin to remove it.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.purple.opacity(0.08))
    }

    private var carousel: some View {
        TabView(selection: $currentIndex) {
            ForEach(Array(captures.enumerated()), id: \.element.id) { idx, capture in
                PinnableImageCard(
                    capture: capture,
                    pins: pinsForCurrent(captureID: capture.id),
                    numbering: globalNumbering,
                    onAddPin: { x, y in
                        flags.append(CaptureFlag(captureID: capture.id,
                                                 x: x, y: y, createdBy: user!, note: ""))
                    },
                    onRemovePin: { pin in
                        flags.removeAll { $0.id == pin.id }
                    }
                )
                .tag(idx)
            }
        }
        #if os(iOS)
        .tabViewStyle(.page(indexDisplayMode: .never))
        #endif
    }

    private var footerBar: some View {
        HStack {
            Text("\(currentIndex + 1) of \(captures.count)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Spacer()

            if !flags.isEmpty {
                Label("\(flags.count) pin\(flags.count == 1 ? "" : "s")",
                      systemImage: "mappin.and.ellipse")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.purple)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.purple.opacity(0.12)))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private var reasonField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("REASON")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
                .tracking(0.5)
            TextField("Describe what needs to be fixed.",
                      text: $reason, axis: .vertical)
                .lineLimit(2...4)
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.rxGroupedBackground)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.1), lineWidth: 1)
                )
        }
        .padding(16)
    }

    // MARK: pin helpers

    private func pinsForCurrent(captureID: UUID) -> [CaptureFlag] {
        flags.filter { $0.captureID == captureID }
    }

    /// Numbering across the whole remediation, in the order pins were added.
    /// Stored as id → ordinal so each page can render the right number.
    private var globalNumbering: [UUID: Int] {
        var dict: [UUID: Int] = [:]
        for (idx, flag) in flags.enumerated() {
            dict[flag.id] = idx + 1
        }
        return dict
    }
}

// MARK: - Detail sheet (read-only view of an existing remediation)

/// Shown from the order detail when a remediation has been requested. Mirrors
/// the composer layout: reason at top, carousel of flagged captures with
/// pins overlaid below.
struct RemediationDetailSheet: View {
    let remediation: RemediationRequest
    let captures: [CompoundCapture]

    @State private var currentIndex: Int = 0
    @Environment(\.dismiss) private var dismiss

    /// Only show captures that have at least one pin.
    private var flaggedCaptures: [CompoundCapture] {
        captures.filter { remediation.flaggedCaptureIDs.contains($0.id) }
    }

    private var globalNumbering: [UUID: Int] {
        var dict: [UUID: Int] = [:]
        for (idx, flag) in remediation.flags.enumerated() {
            dict[flag.id] = idx + 1
        }
        return dict
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                reasonHeader

                if flaggedCaptures.isEmpty {
                    Spacer()
                    ContentUnavailableView(
                        "No Images Flagged",
                        systemImage: "photo",
                        description: Text("The remediation request did not pin any images.")
                    )
                    Spacer()
                } else {
                    TabView(selection: $currentIndex) {
                        ForEach(Array(flaggedCaptures.enumerated()), id: \.element.id) { idx, capture in
                            PinnableImageCard(
                                capture: capture,
                                pins: remediation.pins(for: capture.id),
                                numbering: globalNumbering
                            )
                            .tag(idx)
                        }
                    }
                    #if os(iOS)
                    .tabViewStyle(.page(indexDisplayMode: .always))
                    #endif

                    HStack {
                        Text("\(currentIndex + 1) of \(flaggedCaptures.count)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Label("\(remediation.flags.count) pin\(remediation.flags.count == 1 ? "" : "s") total",
                              systemImage: "mappin.and.ellipse")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.purple)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(.bar)
                }
            }
            .navigationTitle("Remediation")
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

    private var reasonHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.purple)
                Text("REASON")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.purple)
                    .tracking(0.5)
                Spacer()
                Text(remediation.requestedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Text(remediation.reason)
                .font(.body)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .background(Color.purple.opacity(0.08))
    }
}
