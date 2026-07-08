import SwiftUI

// MARK: - Hero

struct HeroCard: View {
    let order: CSPOrder

    var body: some View {
        HStack(spacing: 0) {
            statusRail

            VStack(alignment: .leading, spacing: 16) {
                header
                medicationSection
                Divider()
                patientSection
                metadataSection
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .cardSurface()
        .background(heroCardTint)
        .overlay(heroCardBorder)
        .clipShape(
            RoundedRectangle(cornerRadius: CardStyle.cornerRadius, style: .continuous)
        )
    }

    private var statusRail: some View {
        statusColor.frame(width: 5)
    }

    private var header: some View {
        HStack {
            Text(order.orderNumber)
                .font(.footnote.weight(.semibold).monospaced())
                .foregroundStyle(.secondary)
                .tracking(0.5)

            Spacer()

            StatusPill(status: order.status)
        }
    }

    private var medicationSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(order.medicationName)
                .font(.title.weight(.bold))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            Label {
                Text(order.finalContainer)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } icon: {
                finalContainerIcon(kind: order.finalContainer)
            }
        }
    }

    private var patientSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("PATIENT")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
                .tracking(0.6)

            Text(order.patient.name)
                .font(.title3.weight(.semibold))

            Text(patientLocation)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var metadataSection: some View {
        HStack(spacing: 16) {
            MetaPill(systemImage: "clock", text: dueText, tone: dueTone)
            MetaPill(systemImage: finalCntrIconName(kind: order.finalContainer), text: order.route)
        }
    }

    private var patientLocation: String {
        [order.patient.floor, order.patient.room]
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }

    private var statusColor: Color {
        switch order.status {
        case .remediation: return .purple
        case .waitingForApproval: return .orange
        case .approved: return .green
        case .rejected: return .red
        default: return .accentColor
        }
    }

    private var dueText: String {
        if order.dueTime <= .now {
            if order.status == .approved || order.status == .rejected {
                return "Due \(RelativeDateFormatter.abbreviated.string(for: order.dueTime))"
            }
            return "Overdue"
        }
        return "Due \(RelativeDateFormatter.abbreviated.string(for: order.dueTime))"
    }

    private var dueTone: Color {
        switch order.status {
        case .approved, .rejected: return .secondary
        default:
            switch order.dueTime.timeIntervalSinceNow {
            case ..<0: return .red
            case ..<(30 * 60): return .orange
            default: return .secondary
            }
        }
    }
    
    private var bg: some View {
        RoundedRectangle(cornerRadius: CardStyle.cornerRadius, style: .continuous)
            .fill(.thickMaterial)
    }
    
    private var heroCardTint: Color {
        switch dueText {
        case "Overdue": .red
        default: .secondary
        }
    }
    
    private var heroCardBorder: some View {
        RoundedRectangle(cornerRadius: CardStyle.cornerRadius, style: .continuous)
            .strokeBorder(heroCardTint.opacity(0.35), lineWidth: 1)
    }

}

struct RemediationBanner: View {
    let remediation: RemediationRequest
    let onResubmit: () -> Void
    let onShowDetail: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            Text(remediation.reason)
                .font(.callout)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)

            flaggedImageLabel
            actions
        }
        .padding(16)
        .background(remediationBackground)
        .overlay(remediationBorder)
    }

    private var header: some View {
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
    }

    @ViewBuilder
    private var flaggedImageLabel: some View {
        if !remediation.flaggedCaptureIDs.isEmpty {
            Label(flaggedImageText, systemImage: "flag.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.purple)
        }
    }

    private var actions: some View {
        HStack(spacing: 10) {
            Button("View Details", action: onShowDetail)
                .buttonStyle(.bordered)
                .controlSize(.small)

            Spacer()

            Button(action: onResubmit) {
                Label("Resubmit", systemImage: "paperplane.fill")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .tint(.purple)
        }
    }

    private var remediationBackground: some View {
        RoundedRectangle(cornerRadius: CardStyle.cornerRadius, style: .continuous)
            .fill(Color.purple.opacity(0.08))
            .shadow(
                color: CardStyle.shadowColor,
                radius: CardStyle.shadowRadius,
                x: 0,
                y: CardStyle.shadowYOffset
            )
    }

    private var remediationBorder: some View {
        RoundedRectangle(cornerRadius: CardStyle.cornerRadius, style: .continuous)
            .strokeBorder(Color.purple.opacity(0.45), lineWidth: 1)
    }

    private var requestedText: String {
        RelativeDateFormatter.abbreviated.string(for: remediation.requestedAt)
    }

    private var flaggedImageText: String {
        let count = remediation.flaggedCaptureIDs.count
        return "\(count) image\(count == 1 ? "" : "s") flagged"
    }
}

struct ComponentsCard: View {
    let order: CSPOrder
    var canMutate: Bool = true
    let onAddLot: (CompoundComponent, CompoundUtilizedLot) -> Void
    let onRemoveLot: (CompoundComponent, CompoundUtilizedLot) -> Void
    var onOverrideLot: ((CompoundComponent, CompoundUtilizedLot) -> Void)? = nil

    var body: some View {
        VStack(spacing: 1) {
            CardHeader("Components") { fulfillmentCount }
            fulfillmentProgress
            componentsList
            fulfillmentFooter
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(componentCardBackground)
        .overlay(componentCardBorder)
    }

    private var fulfillmentCount: some View {
        Text("\(order.fulfilledComponentCount)/\(order.components.count)")
            .font(.subheadline.weight(.semibold).monospacedDigit())
            .foregroundStyle(fulfillmentColor)
    }

    private var fulfillmentProgress: some View {
        ProgressView(
            value: Double(order.fulfilledComponentCount),
            total: Double(max(order.components.count, 1))
        )
        .tint(fulfillmentColor)
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    private var componentsList: some View {
        VStack(spacing: 0) {
            ForEach(Array(order.components.enumerated()), id: \.element.id) { index, component in
                if index > 0 {
                    Divider().padding(.leading, 16)
                }
                ComponentRow(
                    component: component,
                    canMutate: canMutate,
                    onAddLot: { onAddLot(component, $0) },
                    onRemoveLot: { onRemoveLot(component, $0) },
                    onOverrideLot: overrideHandler(for: component)
                )
                .padding(.horizontal, 4)
                .padding(.vertical, 10)
            }
        }
    }

    @ViewBuilder
    private var fulfillmentFooter: some View {
        if order.allComponentsFulfilled {
            Spacer().frame(height: 10)
        } else {
            Text(unfulfilledText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 14)
        }
    }

    private func overrideHandler(
        for component: CompoundComponent
    ) -> ((CompoundUtilizedLot) -> Void)? {
        guard let onOverrideLot else { return nil }
        return { lot in onOverrideLot(component, lot) }
    }

    private var componentCardBackground: some View {
        RoundedRectangle(cornerRadius: CardStyle.cornerRadius, style: .continuous)
            .fill(.regularMaterial)
            .overlay {
                RoundedRectangle(cornerRadius: CardStyle.cornerRadius, style: .continuous)
                    .fill(componentCardTint.opacity(0.08))
            }
            .shadow(
                color: CardStyle.shadowColor,
                radius: CardStyle.shadowRadius,
                x: 0,
                y: CardStyle.shadowYOffset
            )
    }

    private var componentCardBorder: some View {
        RoundedRectangle(cornerRadius: CardStyle.cornerRadius, style: .continuous)
            .strokeBorder(componentCardTint.opacity(componentCardBorderOpacity), lineWidth: 1)
    }

    private var componentCardTint: Color {
        switch componentCardState {
        case .unexpected: .red
        case .fulfilled: .green
        case .inProgress: .orange
        }
    }
    
    private var componentCardBorderOpacity: Double {
        switch componentCardState {
        case .unexpected: 0.36
        case .fulfilled: 0.26
        case .inProgress: 0.24
        }
    }

    private var componentCardState: ComponentCardState {
        if hasUnexpectedComponentState { return .unexpected }
        if order.allComponentsFulfilled { return .fulfilled }
        return .inProgress
    }

    private var hasUnexpectedComponentState: Bool {
        order.components.contains { component in
            component.hasPendingOverrides
                || component.utilizedLots.contains(where: \.isExpired)
                || component.quantityAccountedFor > component.totalQuantity + ComponentRow.quantityTolerance
        }
    }

    private var fulfillmentColor: Color {
        componentCardTint
    }

    private var unfulfilledText: String {
        let count = order.unfulfilledComponents.count
        return "\(count) component\(count == 1 ? "" : "s") not yet fulfilled."
    }

    private enum ComponentCardState {
        case fulfilled
        case inProgress
        case unexpected
    }
}

// MARK: - Current step

struct CurrentStepCard: View {
    let order: CSPOrder
    let store: CompoundingStore
    let currentUser: User?
    var canMutate: Bool = true

    @State private var isCompoundingPresented = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            stepHeader
            stepDescription
            captureButton
        }
        .padding(16)
        .cardSurface()
        .navigationDestination(isPresented: $isCompoundingPresented) {
            CompoundingScene(order: order, store: store)
        }
    }

    private var stepHeader: some View {
        HStack {
            Text(stepTitle)
                .font(.caption.weight(.bold))
                .foregroundStyle(Color.accentColor)
                .tracking(0.6)

            Spacer()

            stepControls
        }
    }

    private var stepControls: some View {
        HStack(spacing: 8) {
            Button(action: goToPreviousStep) {
                Image(systemName: "chevron.left")
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(!canGoBackward || !canMutate)

            Button(action: goToNextStep) {
                Image(systemName: "chevron.right")
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(!canGoForward || !canMutate)
        }
    }

    private var stepDescription: some View {
        Text(order.currentStepText.isEmpty ? "—" : order.currentStepText)
            .font(.title3.weight(.semibold))
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var captureButton: some View {
        Button(action: openCompounding) {
            Label("Open", systemImage: "camera.fill")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(!canOpenCompounding)
    }

    private var stepTitle: String {
        guard order.totalStepCount > 0 else { return "STEP" }
        return "STEP \(order.currentStepNumber) OF \(order.totalStepCount)"
    }

    private var canGoBackward: Bool {
        order.currentStepIndex > 0
    }

    private var canGoForward: Bool {
        order.currentStepIndex < order.totalStepCount - 1
    }

    private var canOpenCompounding: Bool {
        canMutate
    }

    private func goToPreviousStep() {
        guard canGoBackward, canMutate, let currentUser else { return }
        store.previousStep(orderID: order.id, changedBy: currentUser)
    }

    private func goToNextStep() {
        guard canGoForward, canMutate, let currentUser else { return }
        store.advanceStep(orderID: order.id, changedBy: currentUser)
    }

    private func openCompounding() {
        guard canOpenCompounding else { return }
        isCompoundingPresented = true
    }
}

struct AllImagesCard: View {
    let captures: [CompoundCapture]
    let order: CSPOrder
    var canMutate: Bool = true
    var onSelectCapture: ((CompoundCapture) -> Void)?

    var body: some View {
        VStack(spacing: 12) {
            CardHeader("Images") {
                Text("\(captures.count)")
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            ReferenceImageGrid(captures: captures, order: order, onSelect: onSelectCapture)
                .padding(.horizontal, 16)

            interactionHint

            Spacer().frame(height: 14)
        }
        .cardSurface()
    }

    @ViewBuilder
    private var interactionHint: some View {
        if canMutate, !captures.isEmpty {
            Text("Tap an image to view or delete.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
        }
    }
}

struct RecipeCard: View {
    let order: CSPOrder
    var canMutate: Bool = true
    let onSelectStep: (Int) -> Void

    var body: some View {
        VStack(spacing: 0) {
            CardHeader("Full Recipe")

            VStack(spacing: 0) {
                ForEach(Array(order.recipeSteps.enumerated()), id: \.offset) { index, step in
                    if index > 0 {
                        Divider().padding(.leading, 44)
                    }
                    recipeStepButton(index: index, text: step)
                }
            }
            .padding(.bottom, 10)
        }
        .cardSurface()
    }

    private func recipeStepButton(index: Int, text: String) -> some View {
        Button {
            onSelectStep(index)
        } label: {
            RecipeStepRow(
                index: index,
                text: text,
                isCurrent: index == order.currentStepIndex
            )
        }
        .buttonStyle(.plain)
        .disabled(!canMutate)
    }
}

// MARK: - Bottom action bar

struct BottomActionBar: View {
    let order: CSPOrder
    var canSend: Bool = true
    let onSend: () -> Void

    var body: some View {
        switch state {
        case .hidden:
            EmptyView()
        case .waiting:
            waitingView
        case .ready:
            sendButton
        }
    }

    private var waitingView: some View {
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
    }

    private var sendButton: some View {
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
        .disabled(!canSend)
    }

    private var state: State {
        guard !order.captures.isEmpty else { return .hidden }

        switch order.status {
        case .waitingForApproval: return .waiting
        case .approved, .rejected: return .hidden
        default: return .ready
        }
    }

    private enum State {
        case hidden
        case waiting
        case ready
    }
}

// MARK: - Formatting

private enum RelativeDateFormatter {
    static let abbreviated: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()
}

private extension RelativeDateTimeFormatter {
    func string(for date: Date) -> String {
        localizedString(for: date, relativeTo: .now)
    }
}
