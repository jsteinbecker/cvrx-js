import SwiftUI


struct OrderDetailScene: View {
    @Environment(\.currentUser) private var currentUser
    @Environment(\.dismiss) private var dismiss

    let order: CompoundOrder
    let store: CompoundingStore

    @State private var isSendConfirmationPresented = false
    @State private var isRemediationDetailPresented = false
    @State private var selectedCapture: CompoundCapture?
    @State private var dataEntryComplete: Bool = false

    private enum Layout {
        static let pagePadding: CGFloat = 16
        static let cardSpacing: CGFloat = 14
    }
    
    private func checkDataEntryCompleteness() {
        var dataEntryMissing = false
        order.components.forEach { cpt in
            if (cpt.isFulfilled() == false) {
                dataEntryMissing = true
            }
        }
        let result = dataEntryMissing == true ? false : true
        dataEntryComplete = result
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Layout.cardSpacing) {
                HeroCard(order: order)
                    .padding(2)
                remediationSection

                ComponentsCard(
                    order: order,
                    onAddLot: addLot,
                    onRemoveLot: removeLot
                ).padding(2)

                CurrentStepCard(
                    order: order,
                    store: store
                ).padding(2)

                capturesSection

                RecipeCard(
                    order: order,
                    onSelectStep: selectStep
                ).padding(2)
            }
        }
        .scrollDismissesKeyboard(.automatic)
        .padding(Layout.pagePadding)
        .background(Color.rxGroupedBackground.ignoresSafeArea())
        .navigationTitle(order.orderNumber)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .safeAreaInset(edge: .bottom) {
            BottomActionBar(
                order: order,
                onSend: presentSendConfirmation
            )
        }
        .alert(
            "Send to Verification?",
            isPresented: $isSendConfirmationPresented
        ) {
            Button("Cancel", role: .cancel) {}

            Button("Send") {
                sendToVerification()
            }.disabled(dataEntryComplete == false)
            
        } message: {
            Text(
                """
                This compound will appear in the Verification queue. \
                You won't capture any more images for it from here.
                """
            )
        }
        .sheet(isPresented: $isRemediationDetailPresented) {
            remediationDetailSheet
        }
        .sheet(item: $selectedCapture) { capture in
            CaptureViewerSheet(
                capture: capture,
                badge: order.badge(for: capture),
                canDelete: order.captureMutationsAllowed,
                onDelete: {
                    deleteCapture(capture)
                }
            )
        }
    }

    @ViewBuilder
    private var remediationSection: some View {
        if order.status == .remediation,
           let remediation = order.remediation {
            RemediationBanner(
                remediation: remediation,
                onResubmit: resubmitAfterRemediation,
                onShowDetail: {
                    isRemediationDetailPresented = true
                }
            )
        }
    }

    @ViewBuilder
    private var capturesSection: some View {
        if !order.captures.isEmpty {
            AllImagesCard(
                captures: order.captures,
                order: order,
                onSelectCapture: {
                    selectedCapture = $0
                }
            )
        }
    }

    @ViewBuilder
    private var remediationDetailSheet: some View {
        if let remediation = order.remediation {
            RemediationDetailSheet(
                remediation: remediation,
                captures: order.captures
            )
            .presentationDetents([.medium, .large])
        }
    }

    private func addLot(
        component: CompoundComponent,
        lot: CompoundUtilizedLot
    ) {
        guard let currentUser else {
            assertionFailure("A signed-in user is required to add a lot.")
            return
        }

        if let barcodeValue = lot.barcodeValue {
            store.processBarcodeScan(
                orderID: order.id,
                componentID: component.id,
                scannedBarcode: barcodeValue,
                detectedLot: lot.lot,
                detectedExpiration: lot.expiration,
                quantity: lot.strengthQuantity,
                scannedBy: currentUser
            )
        } else {
            store.addLotManually(
                orderID: order.id,
                componentID: component.id,
                lot: lot.lot,
                expiration: lot.expiration,
                mfg: lot.mfg,
                quantity: lot.strengthQuantity,
                enteredBy: currentUser
            )
        }
    }

    private func removeLot(
        component: CompoundComponent,
        lot: CompoundUtilizedLot
    ) {
        store.removeLot(
            orderID: order.id,
            componentID: component.id,
            lotID: lot.id
        )
    }

    private func selectStep(_ index: Int) {
        guard order.recipeSteps.indices.contains(index) else {
            return
        }

        store.setCurrentStep(
            orderID: order.id,
            stepIndex: index
        )
    }

    private func presentSendConfirmation() {
        guard order.captureMutationsAllowed,
              !order.captures.isEmpty else {
            return
        }

        isSendConfirmationPresented = true
    }

    private func sendToVerification() {
        store.markReadyForVerification(orderID: order.id)
        dismiss()
    }

    private func resubmitAfterRemediation() {
        store.resubmitAfterRemediation(orderID: order.id)
    }

    private func deleteCapture(_ capture: CompoundCapture) {
        store.deleteCapture(
            orderID: order.id,
            captureID: capture.id
        )

        selectedCapture = nil
    }
}


// MARK: - Hero

struct HeroCard: View {
    let order: CompoundOrder

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
        .clipShape(
            RoundedRectangle(
                cornerRadius: CardStyle.cornerRadius,
                style: .continuous
            )
        )
    }

    private var statusRail: some View {
        statusColor
            .frame(width: 5)
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
            MetaPill(
                systemImage: "clock",
                text: dueText,
                tone: dueTone
            )

            MetaPill(
                systemImage: finalCntrIconName(
                    kind: order.finalContainer
                ),
                text: order.route
            )
        }
    }

    private var patientLocation: String {
        [order.patient.floor, order.patient.room]
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }

    private var statusColor: Color {
        switch order.status {
        case .remediation:
            return .purple

        case .waitingForApproval:
            return .orange

        case .approved:
            return .green

        case .rejected:
            return .red

        default:
            return .accentColor
        }
    }

    private var dueText: String {
        if order.dueTime <= .now {
            return "Overdue"
        }

        return "Due \(RelativeDateFormatter.abbreviated.string(for: order.dueTime))"
    }

    private var dueTone: Color {
        let remainingTime = order.dueTime.timeIntervalSinceNow

        switch remainingTime {
        case ..<0:
            return .red

        case ..<(30 * 60):
            return .orange

        default:
            return .secondary
        }
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


// MARK: - Remediation

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
            Label(
                flaggedImageText,
                systemImage: "flag.fill"
            )
            .font(.caption.weight(.semibold))
            .foregroundStyle(.purple)
        }
    }

    private var actions: some View {
        HStack(spacing: 10) {
            Button(
                "View Details",
                action: onShowDetail
            )
            .buttonStyle(.bordered)
            .controlSize(.small)

            Spacer()

            Button(action: onResubmit) {
                Label(
                    "Resubmit",
                    systemImage: "paperplane.fill"
                )
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .tint(.purple)
        }
    }

    private var remediationBackground: some View {
        RoundedRectangle(
            cornerRadius: CardStyle.cornerRadius,
            style: .continuous
        )
        .fill(Color.purple.opacity(0.08))
        .shadow(
            color: CardStyle.shadowColor,
            radius: CardStyle.shadowRadius,
            x: 0,
            y: CardStyle.shadowYOffset
        )
    }

    private var remediationBorder: some View {
        RoundedRectangle(
            cornerRadius: CardStyle.cornerRadius,
            style: .continuous
        )
        .strokeBorder(
            Color.purple.opacity(0.45),
            lineWidth: 1
        )
    }

    private var requestedText: String {
        RelativeDateFormatter.abbreviated.string(
            for: remediation.requestedAt
        )
    }

    private var flaggedImageText: String {
        let count = remediation.flaggedCaptureIDs.count
        return "\(count) image\(count == 1 ? "" : "s") flagged"
    }
}


// MARK: - Components

struct ComponentsCard: View {
    let order: CompoundOrder
    let onAddLot: (CompoundComponent, CompoundUtilizedLot) -> Void
    let onRemoveLot: (CompoundComponent, CompoundUtilizedLot) -> Void

    var body: some View {
        VStack(spacing: 0) {
            CardHeader("Components") {
                fulfillmentCount
            }

            fulfillmentProgress
            componentsList
            fulfillmentFooter
        }
        .cardSurface()
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
            ForEach(
                Array(order.components.enumerated()),
                id: \.element.id
            ) { index, component in
                if index > 0 {
                    Divider()
                        .padding(.leading, 16)
                }

                ComponentRow(
                    component: component,
                    canMutate: order.captureMutationsAllowed,
                    onAddLot: {
                        onAddLot(component, $0)
                    },
                    onRemoveLot: {
                        onRemoveLot(component, $0)
                    }
                )
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
        }
    }

    @ViewBuilder
    private var fulfillmentFooter: some View {
        if order.allComponentsFulfilled {
            Spacer()
                .frame(height: 10)
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

    private var fulfillmentColor: Color {
        order.allComponentsFulfilled ? .green : .orange
    }

    private var unfulfilledText: String {
        let count = order.unfulfilledComponents.count
        return "\(count) component\(count == 1 ? "" : "s") not yet fulfilled."
    }
}


// MARK: - Current step

struct CurrentStepCard: View {
    let order: CompoundOrder
    let store: CompoundingStore

    @State private var isCompoundingPresented = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            stepHeader
            stepDescription
            captureButton
        }
        .padding(16)
        .cardSurface()
        .navigationDestination(
            isPresented: $isCompoundingPresented
        ) {
            CompoundingScene(
                order: order,
                store: store
            )
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
            .disabled(!canGoBackward)

            Button(action: goToNextStep) {
                Image(systemName: "chevron.right")
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(!canGoForward)
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
        Button(action: navigateToCompoundingScene) {
            Label(
                "Open",
                systemImage: "camera.fill"
            )
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(!canOpenCompounding)
    }

    private var stepTitle: String {
        guard order.totalStepCount > 0 else {
            return "STEP"
        }

        return "STEP \(order.currentStepNumber) OF \(order.totalStepCount)"
    }

    private var canGoBackward: Bool {
        order.currentStepIndex > 0
    }

    private var canGoForward: Bool {
        order.currentStepIndex < order.totalStepCount - 1
    }

    private var canOpenCompounding: Bool {
        order.captureMutationsAllowed &&
        order.totalStepCount > 0
    }

    private func goToPreviousStep() {
        guard canGoBackward else {
            return
        }

        store.previousStep(orderID: order.id)
    }

    private func goToNextStep() {
        guard canGoForward else {
            return
        }

        store.advanceStep(orderID: order.id)
    }

    private func navigateToCompoundingScene() {
        guard canOpenCompounding else {
            return
        }

        isCompoundingPresented = true
    }
}


// MARK: - Images

struct AllImagesCard: View {
    let captures: [CompoundCapture]
    let order: CompoundOrder
    var onSelectCapture: ((CompoundCapture) -> Void)?

    var body: some View {
        VStack(spacing: 12) {
            CardHeader("Images") {
                Text("\(captures.count)")
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            ReferenceImageGrid(
                captures: captures,
                order: order,
                onSelect: onSelectCapture
            )
            .padding(.horizontal, 16)

            interactionHint

            Spacer()
                .frame(height: 14)
        }
        .cardSurface()
    }

    @ViewBuilder
    private var interactionHint: some View {
        if order.captureMutationsAllowed,
           !captures.isEmpty {
            Text("Tap an image to view or delete.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
        }
    }
}


// MARK: - Recipe

struct RecipeCard: View {
    let order: CompoundOrder
    let onSelectStep: (Int) -> Void

    var body: some View {
        VStack(spacing: 0) {
            CardHeader("Full Recipe")

            VStack(spacing: 0) {
                ForEach(
                    Array(order.recipeSteps.enumerated()),
                    id: \.offset
                ) { index, step in
                    if index > 0 {
                        Divider()
                            .padding(.leading, 44)
                    }

                    recipeStepButton(
                        index: index,
                        text: step
                    )
                }
            }
            .padding(.bottom, 10)
        }
        .cardSurface()
    }

    private func recipeStepButton(
        index: Int,
        text: String
    ) -> some View {
        Button {
            onSelectStep(index)
        } label: {
            HStack(alignment: .top, spacing: 12) {
                StepNumberBadge(
                    number: index + 1,
                    isCurrent: index == order.currentStepIndex
                )

                Text(text)
                    .font(.callout)
                    .fontWeight(
                        index == order.currentStepIndex
                            ? .semibold
                            : .regular
                    )
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct StepNumberBadge: View {
    let number: Int
    let isCurrent: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(backgroundColor)
                .frame(width: 26, height: 26)

            Text("\(number)")
                .font(.caption.weight(.bold).monospacedDigit())
                .foregroundStyle(foregroundColor)
        }
    }

    private var backgroundColor: Color {
        isCurrent
            ? .accentColor
            : Color.secondary.opacity(0.15)
    }

    private var foregroundColor: Color {
        isCurrent ? .white : .secondary
    }
}


// MARK: - Bottom action bar

struct BottomActionBar: View {
    let order: CompoundOrder
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
            Label(
                "Send to Verification",
                systemImage: "checkmark.seal.fill"
            )
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.bar)
    }

    private var state: State {
        guard !order.captures.isEmpty else {
            return .hidden
        }

        switch order.status {
        case .waitingForApproval:
            return .waiting

        case .approved, .rejected:
            return .hidden

        default:
            return .ready
        }
    }

    private enum State {
        case hidden
        case waiting
        case ready
    }
}


// MARK: - Shared views

struct CardHeader<Trailing: View>: View {
    let title: String
    private let trailing: Trailing

    init(
        _ title: String,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.title = title
        self.trailing = trailing()
    }

    var body: some View {
        HStack {
            Text(title)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.primary)
                .tracking(0.2)

            Spacer()

            trailing
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }
}

extension CardHeader where Trailing == EmptyView {
    init(_ title: String) {
        self.init(title) {
            EmptyView()
        }
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
        localizedString(
            for: date,
            relativeTo: .now
        )
    }
}


// MARK: - Styling

private enum CardStyle {
    static let cornerRadius: CGFloat = 16
    static let shadowRadius: CGFloat = 8
    static let shadowYOffset: CGFloat = 2
    static let shadowColor = Color.black.opacity(0.09)
    static let borderColor = Color.primary.opacity(0.08)
}

extension Color {
    static var rxGroupedBackground: Color {
        #if os(iOS)
        Color(.systemGroupedBackground)
        #else
        Color(.windowBackgroundColor)
        #endif
    }

    static var rxCardBackground: Color {
        #if os(iOS)
        Color(.secondarySystemGroupedBackground)
        #else
        Color(.controlBackgroundColor)
        #endif
    }
}

private struct CardSurface: ViewModifier {
    func body(content: Content) -> some View {
        content
            .frame(
                maxWidth: .infinity,
                alignment: .leading
            )
            .background {
                RoundedRectangle(
                    cornerRadius: CardStyle.cornerRadius,
                    style: .continuous
                )
                .fill(Color.rxCardBackground)
                .shadow(
                    color: CardStyle.shadowColor,
                    radius: CardStyle.shadowRadius,
                    x: 0,
                    y: CardStyle.shadowYOffset
                )
            }
            .overlay {
                RoundedRectangle(
                    cornerRadius: CardStyle.cornerRadius,
                    style: .continuous
                )
                .strokeBorder(
                    CardStyle.borderColor,
                    lineWidth: 0.5
                )
            }
    }
}

extension View {
    func cardSurface() -> some View {
        modifier(CardSurface())
    }
}

