import SwiftUI

/// Order detail. Hand-laid-out tiled layout — not a Form — so each section has a
/// natural card boundary and the hierarchy is dictated by size/weight/color
/// rather than uniform list rows. The capture action lives *inside* the current
/// step card, which is where the user is mentally focused when they want to
/// take a picture.
struct OrderDetailScene: View {
    @Binding var order: CompoundOrder
    @EnvironmentObject var user: User
    let store: CompoundingStore

    @State private var showMissingComponentOverride = false
    @State private var overrideReason = ""
    @State private var navigateToCompounding = false
    @State private var showFinishConfirm = false
    @State private var showRemediationDetail = false

    @State private var captureViewer: CompoundCapture?

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                HeroCard(order: order)

                if order.status == .remediation, let remediation = order.remediation {
                    RemediationBanner(
                        remediation: remediation,
                        onResubmit: {
                            store.resubmitAfterRemediation(orderID: order.id)
                        },
                        onShowDetail: { showRemediationDetail = true }
                    )
                }

                ComponentsCard(
                    order: order,
                    onAddLot: { component, lot in
                        if let barcodeValue = lot.barcodeValue {
                            store.processBarcodeScan(
                                orderID: order.id,
                                componentID: component.id,
                                scannedBarcode: barcodeValue,
                                detectedLot: lot.lot,
                                detectedExpiration: lot.expiration,
                                quantity: lot.strengthQuantity,
                                scannedBy: user
                            )
                        } else {
                            store.addLotManually(
                                orderID: order.id,
                                componentID: component.id,
                                lot: lot.lot,
                                expiration: lot.expiration,
                                quantity: lot.strengthQuantity,
                                enteredBy: user
                            )
                        }
                    },
                    onRemoveLot: { component, lot in
                        store.removeLot(
                            orderID: order.id,
                            componentID: component.id,
                            lotID: lot.id
                        )
                    }
                )

                CurrentStepCard(
                    order: order,
                    onPrev: { store.previousStep(orderID: order.id) },
                    onNext: { store.advanceStep(orderID: order.id) },
                    onCapture: handleCaptureTap
                )

                if !order.captures.isEmpty {
                    AllReferencesCard(
                        captures: order.captures,
                        order: order,
                        onSelectCapture: { capture in
                            captureViewer = capture
                        }
                    )
                }

                RecipeCard(
                    order: order,
                    onSelectStep: { idx in store.setCurrentStep(orderID: order.id, stepIndex: idx) }
                )
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
        }
        .background(Color.rxGroupedBackground.ignoresSafeArea())
        .navigationTitle(order.orderNumber)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .safeAreaInset(edge: .bottom) {
            BottomActionBar(order: order, onSend: { showFinishConfirm = true })
        }
        .alert("Missing Component Override", isPresented: $showMissingComponentOverride) {
            TextField("Reason", text: $overrideReason, axis: .vertical)

            Button("Cancel", role: .cancel) {
                overrideReason = ""
            }

            Button("Override and Continue") {
                navigateToCompounding = true
            }
            .disabled(overrideReason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } message: {
            Text("The following components are not yet fulfilled: \(order.unfulfilledComponents.map(\.product.name).joined(separator: ", ")). Enter a reason to continue.")
        }
        .alert("Send to Verification?", isPresented: $showFinishConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Send") {
                store.markReadyForVerification(orderID: order.id)
                dismiss()
            }
        } message: {
            Text("This compound will appear in the Verification queue. You won't capture any more images for it from here.")
        }
        .sheet(isPresented: $showRemediationDetail) {
            if let remediation = order.remediation {
                RemediationDetailSheet(remediation: remediation, captures: order.captures)
                    .presentationDetents([.medium, .large])
            }
        }
        .sheet(item: $captureViewer) { capture in
            CaptureViewerSheet(
                capture: capture,
                badge: order.badge(for: capture),
                canDelete: order.captureMutationsAllowed,
                onDelete: {
                    store.deleteCapture(orderID: order.id, captureID: capture.id)
                    captureViewer = nil
                }
            )
        }
        .navigationDestination(isPresented: $navigateToCompounding) {
            CompoundingScene(
                order: $order,
                store: store
            )
        }
    }

    private func handleCaptureTap() {
        if order.allComponentsFulfilled {
            navigateToCompounding = true
        } else {
            showMissingComponentOverride = true
        }
    }
}

// MARK: - Hero card

/// Top hero: medication name is the loudest element, then the patient, then
/// inline meta (due / route / container). Status pill anchored to the top-right.
struct HeroCard: View {
    let order: CompoundOrder

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .trailing) {
                Text(order.orderNumber)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .tracking(0.4)
                Divider()
                MetaPill(systemImage: "clock", text: dueText, tone: dueTone)
                StatusPill(status: order.status)
            }

            VStack(alignment: .leading, spacing: 12) {
                Text(order.medicationName)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.primary)
                    .lineLimit(3)
            HStack {
                finalContainerIcon(kind: order.finalContainer)
                Text(order.finalContainer)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
            }

            Divider()

            // Patient — second most prominent thing.
            VStack(alignment: .leading, spacing: 2) {
                Text("PATIENT")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
                    .tracking(0.5)
                Text(order.patient.name)
                    .font(.title3.weight(.semibold))
                Text("\(order.patient.floor) \(order.patient.room)")
                Divider().frame(height: 16).padding(.horizontal, 10)
                MetaPill(
                    systemImage: finalCntrIconName(kind: order.finalContainer),
                    text: order.route
                )
            }

            // Inline meta row.
            HStack(spacing: 0) {
                
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(18)
        .cardSurface()
    }

    private var dueText: String {
        let interval = order.dueTime.timeIntervalSinceNow
        if interval < 0 {
            return "Overdue"
        }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return "Due " + formatter.localizedString(for: order.dueTime, relativeTo: .now)
    }

    private var dueTone: Color {
        let interval = order.dueTime.timeIntervalSinceNow
        if interval < 0 { return .red }
        if interval < 30 * 60 { return .orange }
        return .secondary
    }
}

struct MetaPill: View {
    let systemImage: String
    let text: String
    var tone: Color = .secondary

    var body: some View {
        Label {
            Text(text)
                .font(.subheadline.weight(.medium))
        } icon: {
            Image(systemName: systemImage)
                .font(.caption)
        }
        .foregroundStyle(tone)
    }
}

// MARK: - Remediation banner

struct RemediationBanner: View {
    let remediation: RemediationRequest
    let onResubmit: () -> Void
    let onShowDetail: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.title3)
                    .foregroundStyle(.purple)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Remediation Requested")
                        .font(.headline)
                    Text(requestedText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            Text(remediation.reason)
                .font(.callout)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)

            if !remediation.flaggedCaptureIDs.isEmpty {
                Label("\(remediation.flaggedCaptureIDs.count) image\(remediation.flaggedCaptureIDs.count == 1 ? "" : "s") flagged",
                      systemImage: "flag.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.purple)
            }

            HStack(spacing: 10) {
                Button("View Details", action: onShowDetail)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                Spacer()
                Button {
                    onResubmit()
                } label: {
                    Label("Resubmit", systemImage: "paperplane.fill")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(.purple)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.purple.opacity(0.08))
                .shadow(color: .black.opacity(0.09), radius: 8, x: 0, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.purple.opacity(0.45), lineWidth: 1)
        )
    }

    private var requestedText: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: remediation.requestedAt, relativeTo: .now)
    }
}

// MARK: - Components card

struct ComponentsCard: View {
    let order: CompoundOrder
    let onAddLot: (CompoundComponent, CompoundUtilizedLot) -> Void
    let onRemoveLot: (CompoundComponent, CompoundUtilizedLot) -> Void

    var body: some View {
        VStack(spacing: 0) {
            CardHeader(
                title: "Components",
                trailing: AnyView(
                    Text("\(order.fulfilledComponentCount)/\(order.components.count)")
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                        .foregroundStyle(order.allComponentsFulfilled ? .green : .orange)
                )
            )

            ProgressView(
                value: Double(order.fulfilledComponentCount),
                total: Double(max(order.components.count, 1))
            )
            .tint(order.allComponentsFulfilled ? .green : .orange)
            .padding(.horizontal, 16)
            .padding(.bottom, 4)

            VStack(spacing: 0) {
                ForEach(Array(order.components.enumerated()), id: \.element.id) { idx, component in
                    if idx > 0 { Divider().padding(.leading, 16) }
                    ComponentRow(
                        component: component,
                        canMutate: order.captureMutationsAllowed,
                        onAddLot: { lot in onAddLot(component, lot) },
                        onRemoveLot: { lot in onRemoveLot(component, lot) }
                    )
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                }
            }

            if !order.allComponentsFulfilled {
                Text("\(order.unfulfilledComponents.count) component\(order.unfulfilledComponents.count == 1 ? "" : "s") not yet fulfilled. Continuing to capture requires an override.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.top, 6)
                    .padding(.bottom, 12)
            } else {
                Spacer().frame(height: 8)
            }
        }
        .cardSurface()
    }
}

// MARK: - Current step card (with inline Capture)

struct CurrentStepCard: View {
    let order: CompoundOrder
    let onPrev: () -> Void
    let onNext: () -> Void
    let onCapture: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header row.
            HStack {
                Text(order.totalStepCount > 0
                     ? "STEP \(order.currentStepNumber) OF \(order.totalStepCount)"
                     : "STEP")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.accentColor)
                    .tracking(0.6)
                Spacer()
                HStack(spacing: 6) {
                    Button(action: onPrev) {
                        Image(systemName: "chevron.left")
                            .frame(width: 32, height: 32)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(order.currentStepIndex <= 0)

                    Button(action: onNext) {
                        Image(systemName: "chevron.right")
                            .frame(width: 32, height: 32)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(order.currentStepIndex >= max(order.totalStepCount - 1, 0))
                }
            }

            // Step text — the focal point of this card.
            Text(order.currentStepText.isEmpty ? "—" : order.currentStepText)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Capture button — large, in the natural place (right where the
            // user is reading the step). Captures aren't tied to a step;
            // this is just a convenient inline shortcut to the camera.
            Button(action: onCapture) {
                Label("Capture", systemImage: "camera.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(16)
        .cardSurface()
    }
}

// MARK: - All references card

struct AllReferencesCard: View {
    let captures: [CompoundCapture]
    let order: CompoundOrder
    var onSelectCapture: ((CompoundCapture) -> Void)? = nil

    var body: some View {
        VStack(spacing: 12) {
            CardHeader(
                title: "All Images",
                trailing: AnyView(
                    Text("\(captures.count)")
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                        .foregroundStyle(.secondary)
                )
            )
            ReferenceImageGrid(
                captures: captures,
                order: order,
                onSelect: onSelectCapture
            )
            .padding(.horizontal, 16)
            .padding(.bottom, 14)

            if order.captureMutationsAllowed && !captures.isEmpty {
                Text("Tap an image to view or delete.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 10)
            }
        }
        .cardSurface()
    }
}

// MARK: - Recipe card

struct RecipeCard: View {
    let order: CompoundOrder
    let onSelectStep: (Int) -> Void

    var body: some View {
        VStack(spacing: 0) {
            CardHeader(title: "Full Recipe", trailing: nil)

            VStack(spacing: 0) {
                ForEach(Array(order.recipeSteps.enumerated()), id: \.offset) { idx, step in
                    if idx > 0 { Divider().padding(.leading, 44) }
                    Button {
                        onSelectStep(idx)
                    } label: {
                        HStack(alignment: .top, spacing: 12) {
                            ZStack {
                                Circle()
                                    .fill(idx == order.currentStepIndex
                                          ? Color.accentColor
                                          : Color.secondary.opacity(0.15))
                                    .frame(width: 26, height: 26)
                                Text("\(idx + 1)")
                                    .font(.caption.weight(.bold).monospacedDigit())
                                    .foregroundStyle(idx == order.currentStepIndex ? .white : .secondary)
                            }
                            Text(step)
                                .font(.callout)
                                .fontWeight(idx == order.currentStepIndex ? .semibold : .regular)
                                .foregroundStyle(.primary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.bottom, 8)
        }
        .cardSurface()
    }
}

// MARK: - Bottom action bar

struct BottomActionBar: View {
    let order: CompoundOrder
    let onSend: () -> Void

    var body: some View {
        Group {
            if order.captures.isEmpty {
                EmptyView()
            } else if order.status == .readyForVerification {
                HStack(spacing: 8) {
                    Image(systemName: "hourglass")
                    Text("In verification queue")
                        .font(.subheadline.weight(.semibold))
                }
                .foregroundStyle(.orange)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .padding(.horizontal, 16)
                .background(.bar)
            } else if order.status == .approved || order.status == .rejected {
                EmptyView()
            } else {
                Button(action: onSend) {
                    Label("Send to Verification", systemImage: "checkmark.seal.fill")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(.bar)
            }
        }
    }
}

// MARK: - Shared building blocks

/// Standard header row used inside cards.
struct CardHeader: View {
    let title: String
    let trailing: AnyView?

    var body: some View {
        HStack {
            Text(title)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.primary)
                .tracking(0.2)
            Spacer()
            if let trailing { trailing }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }
}

// Cross-platform grouped background colors. On macOS the system grouped colors
// don't exist, so we approximate with window/content colors.
extension Color {
    static var rxGroupedBackground: Color {
        #if os(iOS)
        return Color(.systemGroupedBackground)
        #else
        return Color(.windowBackgroundColor)
        #endif
    }

    static var rxCardBackground: Color {
        #if os(iOS)
        return Color(.secondarySystemGroupedBackground)
        #else
        return Color(.controlBackgroundColor)
        #endif
    }
}

/// Card surface styling — applied with a modifier so every card matches.
/// A subtle shadow lifts cards off the page background; pair that with a
/// hairline border for definition in both light and dark mode.
private struct CardSurface: ViewModifier {
    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.rxCardBackground)
                    .shadow(color: .black.opacity(0.09), radius: 8, x: 0, y: 2)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
            )
    }
}

extension View {
    func cardSurface() -> some View { modifier(CardSurface()) }
}
