import SwiftUI
import Vision


/// Visual badge derived from a capture's role in the order's remediation
/// history. Drives both border color/opacity on thumbnails and the styling on
/// full-screen image views.
enum CaptureBadge: Equatable {
    /// No remediation context.
    case none
    /// Currently flagged in an active (not-yet-resubmitted) remediation —
    /// shown to the compounder so they can find what to fix.
    case flaggedActive
    /// Was flagged in a prior remediation that has since been resubmitted —
    /// shown grayed out so the verifier knows it's been addressed.
    case flaggedResolved
    /// Captured after the remediation was requested. Highlights work added
    /// in response to the request.
    case addedDuringRemediation

    var borderColor: Color {
        switch self {
        case .none: return .clear
        case .flaggedActive: return .purple
        case .flaggedResolved: return Color.gray.opacity(0.75)
        case .addedDuringRemediation: return .green
        }
    }

    var opacity: Double {
        self == .flaggedResolved ? 0.45 : 1.0
    }

    var label: String {
        switch self {
        case .none: return ""
        case .flaggedActive: return "Flagged"
        case .flaggedResolved: return "Resolved"
        case .addedDuringRemediation: return "New"
        }
    }

    var icon: String {
        switch self {
        case .none: return ""
        case .flaggedActive: return "flag.fill"
        case .flaggedResolved: return "checkmark.circle.fill"
        case .addedDuringRemediation: return "sparkles"
        }
    }
}

struct CaptureBadgePill: View {
    let badge: CaptureBadge
    var horizontalPadding: CGFloat = 8
    var verticalPadding: CGFloat = 3

    var body: some View {
        if badge != .none {
            PillLabel(
                text: badge.label,
                systemImage: badge.icon,
                tone: badge.borderColor,
                font: .caption.weight(.bold),
                horizontalPadding: horizontalPadding,
                verticalPadding: verticalPadding
            )
        }
    }
}

struct CaptureBadgeIconChip: View {
    let badge: CaptureBadge

    var body: some View {
        if badge != .none {
            Image(systemName: badge.icon)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.white)
                .padding(4)
                .background(Circle().fill(badge.borderColor))
                .padding(3)
        }
    }
}

private struct CaptureBadgeBorder: ViewModifier {
    let badge: CaptureBadge
    let lineWidth: CGFloat

    func body(content: Content) -> some View {
        content.overlay(
            Rectangle()
                .strokeBorder(badge.borderColor, lineWidth: badge == .none ? 0 : lineWidth)
                .allowsHitTesting(false)
        )
    }
}

extension View {
    func captureBadgeBorder(_ badge: CaptureBadge, lineWidth: CGFloat = 4) -> some View {
        modifier(CaptureBadgeBorder(badge: badge, lineWidth: lineWidth))
    }
}

struct PinNoteCallout: View {
    let note: String

    var body: some View {
        Text(note)
            .font(.caption)
            .foregroundStyle(.primary)
            .multilineTextAlignment(.leading)
            .lineLimit(3)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(maxWidth: 220, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .roundedPanel(fill: .regularMaterial)
            .shadow(color: .black.opacity(0.16), radius: 6, x: 0, y: 2)
    }
}

extension CSPOrder {
    /// Derive the badge for a capture based on this order's current state and
    /// any associated remediation. Lives next to `CaptureBadge` because it is
    /// a UI-shaping helper, not a pure model concern.
    func badge(for capture: CompoundCapture) -> CaptureBadge {
        guard let remediation else { return .none }
        let isFlagged = remediation.flaggedCaptureIDs.contains(capture.id)
        let isNew = capture.timestamp > remediation.requestedAt

        switch status {
        case .remediation:
            if isFlagged { return .flaggedActive }
        case .waitingForApproval, .approved, .rejected:
            if isFlagged { return .flaggedResolved }
        default:
            return .none
        }
        if isNew { return .addedDuringRemediation }
        return .none
    }
}


/// Image-only thumbnail. Square, rounded. When given a non-`.none` badge it
/// gains a colored border and a small icon chip in the top-right corner;
/// resolved-flag badges also dim the image to half opacity.
/// A small orange pin in the bottom-left corner appears when the preparer has
/// placed flags on this capture.
struct CaptureThumbnailImage: View {
    let capture: CompoundCapture
    var size: CGFloat = 72
    var badge: CaptureBadge = .none

    var body: some View {
        baseImage
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .opacity(badge.opacity)
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(
                        badge.borderColor,
                        lineWidth: badge == .none ? 0 : 2.5
                    )
            )
            .overlay(alignment: .topTrailing) {
                CaptureBadgeIconChip(badge: badge)
            }
            .overlay(alignment: .bottomLeading) {
                if !capture.preparerFlags.isEmpty {
                    Image(systemName: "mapping.fill")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(4)
                        .background(Circle().fill(Color.orange))
                        .padding(3)
                }
            }
    }

    @ViewBuilder
    private var baseImage: some View {
        if let imageURL = capture.imageURL {
            AsyncImage(url: imageURL) { phase in
                switch phase {
                case .empty:
                    placeholder
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
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
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(Color.secondary.opacity(0.18))
            .overlay {
                Image(systemName: capture.kind == .reference ? "doc.viewfinder" : "tag")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
    }
}


/// Grid of captured images. When `order` is supplied each thumbnail is
/// rendered with its remediation badge. When `onSelect` is supplied each
/// thumbnail becomes a button that opens the capture viewer.
struct ReferenceImageGrid: View {
    let captures: [CompoundCapture]
    var order: CSPOrder? = nil
    var onSelect: ((CompoundCapture) -> Void)? = nil

    private let columns: [GridItem] = [
        GridItem(.adaptive(minimum: 72, maximum: 96), spacing: 10)
    ]

    var body: some View {
        if captures.isEmpty {
            HStack {
                Image(systemName: "photo.on.rectangle")
                    .foregroundStyle(.tertiary)
                Text("No images captured yet")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.vertical, 6)
        } else {
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(captures) { capture in
                    Group {
                        if let onSelect {
                            Button {
                                onSelect(capture)
                            } label: {
                                CaptureThumbnailImage(
                                    capture: capture,
                                    size: 80,
                                    badge: order?.badge(for: capture) ?? .none
                                )
                                .aspectRatio(1, contentMode: .fit)
                            }
                            .buttonStyle(.plain)
                        } else {
                            CaptureThumbnailImage(
                                capture: capture,
                                size: 80,
                                badge: order?.badge(for: capture) ?? .none
                            )
                            .aspectRatio(1, contentMode: .fit)
                        }
                    }
                }
            }
        }
    }
}


/// Modal that shows a single capture at large size. When `canDelete` is true,
/// a destructive button appears that triggers a confirmation alert before
/// calling `onDelete`. When `onAddPreparerPin` is non-nil, the image becomes
/// interactive: tap an empty area to place a numbered pin and enter a note;
/// tap an existing pin to select it and read its note. The creator can delete
/// their pin via the trash button in the selection card.
struct CaptureViewerSheet: View {
    let capture: CompoundCapture
    var badge: CaptureBadge = .none
    let canDelete: Bool
    let onDelete: () -> Void
    var currentUser: User? = nil
    /// Called when the preparer confirms a new pin. Receives normalized x/y and an optional note.
    var onAddPreparerPin: ((Double, Double, String?) -> Void)? = nil
    /// Called when the creating user deletes an existing pin.
    var onRemovePreparerPin: ((CaptureFlag) -> Void)? = nil
    /// Persists analysis generated as a fallback for older captures.
    var onStoreAnalysis: ((CaptureAnalysis) -> Void)? = nil
    /// Applies extracted product data to the order's lot rows.
    var onApplyDetectedProduct: ((CaptureAnalysis.DetectedProduct) -> Void)? = nil

    @State private var showDeleteConfirm = false
    @State private var selectedPin: CaptureFlag? = nil
    @State private var hoveredPinID: UUID? = nil
    @State private var pendingPinLocation: CGPoint? = nil
    @State private var pendingNote: String = ""
    @State private var captureAnalysis: CaptureAnalysis?
    @State private var isAnalyzing = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if onAddPreparerPin != nil {
                    preparerInstructionBar
                }

                imageArea
                    .frame(maxHeight: .infinity)

                analysisPanel

                if badge != .none {
                    CaptureBadgePill(
                        badge: badge,
                        horizontalPadding: 10,
                        verticalPadding: 6
                    )
                    .padding(.vertical, 10)
                }

                if let pin = selectedPin {
                    selectedPinCard(pin)
                } else if let loc = pendingPinLocation {
                    pinNoteEntry(at: loc)
                } else if !capture.preparerFlags.isEmpty {
                    preparerPinFooter
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black.opacity(0.04))
            .navigationTitle(capture.kind.rawValue + " Image")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                if canDelete {
                    ToolbarItem(placement: .destructiveAction) {
                        Button(role: .destructive) {
                            showDeleteConfirm = true
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
            .alert("Delete this image?", isPresented: $showDeleteConfirm) {
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) { onDelete() }
            } message: {
                Text("This action can't be undone. Any remediation pins on this image will also be removed.")
            }
            .task(id: capture.id) { await runAnalysis() }
        }
    }

    // MARK: subviews

    private var preparerInstructionBar: some View {
        InstructionBar(
            systemImage: "hand.tap.fill",
            text: "Tap the image to add a pin with a note. Tap a pin to view or delete it.",
            tone: .orange
        )
    }

    private var preparerPinFooter: some View {
        HStack {
            Label(
                "\(capture.preparerFlags.count) preparer pin\(capture.preparerFlags.count == 1 ? "" : "s")",
                systemImage: "mappin.and.ellipse"
            )
            .font(.caption.weight(.bold))
            .foregroundStyle(.orange)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.bar)
    }

    // MARK: image area

    /// Image area with pin overlay. Pins are rendered on a GeometryReader overlay
    /// applied directly to the fitted image so coordinates are relative to the
    /// actual image bounds (not the surrounding letterbox area).
    @ViewBuilder
    private var imageArea: some View {
        ZStack {
            Color.black.opacity(0.04)
            imageWithPins
        }
        .captureBadgeBorder(badge)
    }

    @ViewBuilder
    private var imageWithPins: some View {
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
                        .overlay {
                            pinLayer
                        }
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

    /// Pin overlay: tap background to place a new pin (opens note entry) or deselect.
    /// Tap an existing pin to select it; all others dim to low opacity.
    private var pinLayer: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture(coordinateSpace: .local) { location in
                        if selectedPin != nil {
                            withAnimation(.easeInOut(duration: 0.15)) { selectedPin = nil }
                            return
                        }
                        guard pendingPinLocation == nil, onAddPreparerPin != nil else { return }
                        let w = max(geo.size.width, 1)
                        let h = max(geo.size.height, 1)
                        let nx = Double(location.x / w)
                        let ny = Double(location.y / h)
                        guard (0...1).contains(nx), (0...1).contains(ny) else { return }
                        pendingPinLocation = CGPoint(x: nx, y: ny)
                        pendingNote = ""
                    }

                ForEach(Array(capture.preparerFlags.enumerated()), id: \.element.id) { idx, pin in
                    let isSelected = selectedPin?.id == pin.id
                    let isHovered = hoveredPinID == pin.id

                    ZStack {
                        PinMarker(number: idx + 1, color: .orange)

                        if (isSelected || isHovered), let note = displayNote(for: pin) {
                            PinNoteCallout(note: note)
                                .offset(y: -48)
                                .allowsHitTesting(false)
                                .transition(.opacity.combined(with: .scale(scale: 0.96)))
                        }
                    }
                    .opacity(selectedPin == nil ? 1.0 : (isSelected ? 1.0 : 0.12))
                    .animation(.easeInOut(duration: 0.15), value: selectedPin?.id)
                    .animation(.easeInOut(duration: 0.12), value: hoveredPinID)
                    .position(
                        x: CGFloat(pin.x) * geo.size.width,
                        y: CGFloat(pin.y) * geo.size.height
                    )
                    .onHover { isHovering in
                        hoveredPinID = isHovering ? pin.id : nil
                    }
                    .help(displayNote(for: pin) ?? "Pin \(idx + 1)")
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            pendingPinLocation = nil
                            pendingNote = ""
                            selectedPin = isSelected ? nil : pin
                        }
                    }
                }
            }
        }
    }

    private func selectedPinCard(_ pin: CaptureFlag) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Image(systemName: "mappin.fill")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.orange)
                    Text("Pin \(pinIndex(for: pin))")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.orange)
                }
                if let note = displayNote(for: pin) {
                    Text(note)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                } else {
                    Text("No note")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Text("By \(pin.createdBy.username)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                withAnimation(.easeInOut(duration: 0.15)) { selectedPin = nil }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
                    .font(.title3)
            }
            .buttonStyle(.plain)
            if onRemovePreparerPin != nil, currentUser?.id == pin.createdBy.id {
                Button(role: .destructive) {
                    let pinToDelete = pin
                    withAnimation(.easeInOut(duration: 0.15)) { selectedPin = nil }
                    onRemovePreparerPin?(pinToDelete)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.bordered)
                .tint(.red)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private func pinNoteEntry(at loc: CGPoint) -> some View {
        VStack(spacing: 10) {
            HStack {
                Label("Add Pin Note", systemImage: "mappin.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.orange)
                Spacer()
            }
            ZStack(alignment: .topLeading) {
                TextEditor(text: $pendingNote)
                    .frame(height: 72)
                    .padding(6)
                    .scrollContentBackground(.hidden)

                if pendingNote.isEmpty {
                    Text("Note (optional)")
                        .font(.body)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 14)
                        .allowsHitTesting(false)
                }
            }
            .roundedPanel(fill: Color.rxGroupedBackground)
            HStack {
                Button("Cancel") {
                    pendingPinLocation = nil
                    pendingNote = ""
                }
                .buttonStyle(.bordered)
                Spacer()
                Button("Save Pin") {
                    onAddPreparerPin?(Double(loc.x), Double(loc.y), pendingNote.isEmpty ? nil : pendingNote)
                    pendingPinLocation = nil
                    pendingNote = ""
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.bar)
    }

    private func pinIndex(for pin: CaptureFlag) -> Int {
        (capture.preparerFlags.firstIndex(where: { $0.id == pin.id }) ?? 0) + 1
    }

    private func displayNote(for pin: CaptureFlag) -> String? {
        let note = pin.note?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return note.isEmpty ? nil : note
    }

    private var placeholder: some View {
        ImageUnavailablePlaceholder()
    }

    // MARK: - Image Analysis

    private func runAnalysis() async {
        if let cachedAnalysis = capture.analysis {
            captureAnalysis = cachedAnalysis
            return
        }
        guard let url = capture.imageURL else { return }
        isAnalyzing = true
        let analysis = await ImageAnalyzer.shared.analyze(url: url)
        captureAnalysis = analysis
        onStoreAnalysis?(analysis)
        isAnalyzing = false
    }

    @ViewBuilder
    private var analysisPanel: some View {
        if isAnalyzing {
            HStack(spacing: 8) {
                ProgressView().scaleEffect(0.75)
                Text("Analyzing image…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(.bar)
        } else if let a = captureAnalysis, a.hasAnyData {
            CaptureAnalysisPanel(analysis: a, onApplyDetectedProduct: onApplyDetectedProduct)
        }
    }
}

// MARK: - Analysis Panel

struct CaptureAnalysisPanel: View {
    let analysis: CaptureAnalysis
    var onApplyDetectedProduct: ((CaptureAnalysis.DetectedProduct) -> Void)? = nil
    @State private var expanded = false

    var body: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() }
            } label: {
                headerRow
            }
            .buttonStyle(.plain)

            if expanded {
                Divider()
                detailsScroll
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .move(edge: .top)),
                        removal: .opacity
                    ))
            }
        }
        .background(.bar)
    }

    private var headerRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkle.magnifyingglass")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.blue)
            Text("Image Analysis")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
            Spacer()
            summaryTags
            Image(systemName: expanded ? "chevron.up" : "chevron.down")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var summaryTags: some View {
        if analysis.hasParsedData {
            HStack(spacing: 4) {
                if let lot = analysis.detectedLot {
                    analysisTag("Lot: \(lot)")
                }
                if let exp = analysis.detectedExpiration {
                    analysisTag(exp.formatted(.dateTime.month(.twoDigits).year(.twoDigits)))
                }
                if analysis.detectedNDC != nil {
                    analysisTag("NDC")
                }
            }
        } else {
            Text("\(analysis.barcodes.count) barcode\(analysis.barcodes.count == 1 ? "" : "s") · \(analysis.recognizedLines.count) text line\(analysis.recognizedLines.count == 1 ? "" : "s")")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func analysisTag(_ text: String) -> some View {
        Text(text)
            .font(.caption2.weight(.medium))
            .foregroundStyle(.blue)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(Capsule().fill(Color.blue.opacity(0.12)))
            .lineLimit(1)
    }

    private var detailsScroll: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if !analysis.products.isEmpty {
                    analysisSection("Detected Products") {
                        ForEach(analysis.products) { product in
                            DetectedProductCard(
                                product: product,
                                onApply: onApplyDetectedProduct.map { apply in
                                    { apply(product) }
                                }
                            )
                        }
                    }
                } else if analysis.hasParsedData {
                    analysisSection("Detected Pharmaceutical Data") {
                        if let ndc = analysis.detectedNDC {
                            AnalysisDetailRow(icon: "number", label: "NDC", value: ndc)
                        }
                        if let lot = analysis.detectedLot {
                            AnalysisDetailRow(icon: "tag", label: "Lot", value: lot)
                        }
                        if let exp = analysis.detectedExpiration {
                            AnalysisDetailRow(
                                icon: "calendar",
                                label: "Expiration",
                                value: exp.formatted(date: .abbreviated, time: .omitted)
                            )
                        }
                    }
                }

                if !analysis.barcodes.isEmpty {
                    analysisSection("Detected Barcodes") {
                        ForEach(analysis.barcodes, id: \.payload) { bc in
                            AnalysisDetailRow(
                                icon: bc.isGS1 ? "barcode.viewfinder" : "barcode",
                                label: bc.symbology,
                                value: String(bc.payload.prefix(60))
                            )
                        }
                    }
                }

                if !analysis.recognizedLines.isEmpty {
                    analysisSection("Recognized Text (\(analysis.recognizedLines.count) lines)") {
                        ForEach(analysis.recognizedLines.prefix(12), id: \.self) { line in
                            Text(line)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        if analysis.recognizedLines.count > 12 {
                            Text("+ \(analysis.recognizedLines.count - 12) more…")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }

                if !analysis.imageCategories.isEmpty {
                    analysisSection("Image Content") {
                        Text(analysis.imageCategories.map { $0.capitalized }.joined(separator: " · "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(16)
        }
        .frame(maxHeight: 300)
    }

    @ViewBuilder
    private func analysisSection<C: View>(
        _ title: String,
        @ViewBuilder content: () -> C
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            content()
        }
    }
}

struct DetectedProductCard: View {
    let product: CaptureAnalysis.DetectedProduct
    var onApply: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 6) {
                if let ndc = product.detectedNDC {
                    AnalysisDetailRow(icon: "number", label: "NDC", value: ndc)
                }
                if let lot = product.detectedLot {
                    AnalysisDetailRow(icon: "tag", label: "Lot", value: lot)
                }
                if let exp = product.detectedExpiration {
                    AnalysisDetailRow(
                        icon: "calendar",
                        label: "Expiration",
                        value: exp.formatted(date: .abbreviated, time: .omitted)
                    )
                }
                if let payload = product.sourceBarcodePayload {
                    AnalysisDetailRow(icon: "barcode.viewfinder", label: "Barcode", value: String(payload.prefix(60)))
                }
            }

            if let onApply {
                Button(action: onApply) {
                    Label("Apply to Lot Rows", systemImage: "text.badge.checkmark")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding(10)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

struct AnalysisDetailRow: View {
    let icon: String
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 14, alignment: .center)
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
            }
        }
    }
}

// MARK: - Legend

/// Tiny inline key explaining the colored capture badges. Shown only when the
/// remediation context makes the colors meaningful.
struct CaptureBadgeLegend: View {
    let badges: [CaptureBadge]

    var body: some View {
        HStack(spacing: 12) {
            ForEach(badges, id: \.self) { badge in
                HStack(spacing: 5) {
                    Circle()
                        .fill(badge.borderColor)
                        .frame(width: 8, height: 8)
                    Text(badge.label)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
    }
}
