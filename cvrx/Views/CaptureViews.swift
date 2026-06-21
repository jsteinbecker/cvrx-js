import SwiftUI

// MARK: - Capture badge

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

extension CompoundOrder {
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

// MARK: - Reusable thumbnail (image-only, with optional badge)

/// Image-only thumbnail. Square, rounded. When given a non-`.none` badge it
/// gains a colored border and a small icon chip in the top-right corner;
/// resolved-flag badges also dim the image to half opacity.
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

// MARK: - Reference image grid (used in OrderDetailScene)

/// Grid of captured images. When `order` is supplied each thumbnail is
/// rendered with its remediation badge. When `onSelect` is supplied each
/// thumbnail becomes a button that opens the capture viewer.
struct ReferenceImageGrid: View {
    let captures: [CompoundCapture]
    var order: CompoundOrder? = nil
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

// MARK: - Capture viewer (with optional delete)

/// Modal that shows a single capture at large size. When `canDelete` is true,
/// a destructive button appears that triggers a confirmation alert before
/// calling `onDelete`. Used from order detail to manage in-progress captures.
struct CaptureViewerSheet: View {
    let capture: CompoundCapture
    var badge: CaptureBadge = .none
    let canDelete: Bool
    let onDelete: () -> Void

    @State private var showDeleteConfirm = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                imageArea

                if badge != .none {
                    HStack(spacing: 6) {
                        Image(systemName: badge.icon)
                            .font(.caption.weight(.bold))
                        Text(badge.label)
                            .font(.caption.weight(.bold))
                    }
                    .foregroundStyle(badge.borderColor)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(badge.borderColor.opacity(0.15)))
                    .padding(.vertical, 10)
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
        }
    }

    @ViewBuilder
    private var imageArea: some View {
        ZStack {
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(
            Rectangle()
                .strokeBorder(badge.borderColor, lineWidth: badge == .none ? 0 : 4)
                .allowsHitTesting(false)
        )
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
