import SwiftUI

private struct LotOverrideContext: Identifiable {
    let id = UUID()
    let component: CompoundComponent
    let lot: CompoundUtilizedLot
}


struct OrderDetailScene: View {
    @Environment(\.currentUser) private var currentUser
    @Environment(\.dismiss) private var dismiss

    let order: CSPOrder
    let store: CompoundingStore

    @State private var isSendConfirmationPresented = false
    @State private var isRemediationDetailPresented = false
    @State private var selectedCapture: CompoundCapture?
    @State private var lotOverrideContext: LotOverrideContext?
    @State private var scannerBarcodeInput = ""
    @State private var isManualBarcodeInputVisible = false
    @FocusState private var barcodeInputFocused: Bool

    private enum Layout {
        static let pagePadding: CGFloat = 16
        static let cardSpacing: CGFloat = 14
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Layout.cardSpacing) {
                HeroCard(order: order)
                    .padding(2)

                remediationSection
                scannerInputArea
                ComponentsCard(
                    order: order,
                    onAddLot: addLot,
                    onRemoveLot: removeLot,
                    onOverrideLot: overrideLotHandler
                )
                .padding(2)
                
                CurrentStepCard(order: order, store: store)
                    .padding(2)
                
                capturesSection
                
                RecipeCard(order: order, onSelectStep: selectStep)
                    .padding(2)
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
            BottomActionBar(order: order, onSend: presentSendConfirmation)
        }
        .alert("Send to Verification?", isPresented: $isSendConfirmationPresented) {
            Button("Cancel", role: .cancel) {}
            Button("Send") { sendToVerification() }
        } message: {
            Text("""
                This compound will appear in the Verification queue. \
                You won't capture any more images for it from here. 
            """)
        }
        .sheet(isPresented: $isRemediationDetailPresented) {
            remediationDetailSheet
        }
        .sheet(item: $selectedCapture, content: captureViewerSheet)
        .sheet(item: $lotOverrideContext, content: lotOverrideSheet)
        .onAppear {
            guard order.captureMutationsAllowed else { return }
            barcodeInputFocused = true
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var remediationSection: some View {
        if order.status == .remediation, let remediation = order.remediation {
            RemediationBanner(
                remediation: remediation,
                onResubmit: resubmitAfterRemediation,
                onShowDetail: { isRemediationDetailPresented = true }
            )
        }
    }

    @ViewBuilder
    private var capturesSection: some View {
        if !order.captures.isEmpty {
            AllImagesCard(
                captures: order.captures,
                order: order,
                onSelectCapture: { selectedCapture = $0 }
            )
        }
    }

    private var scannerInputArea: some View {
        HStack(spacing: 10) {
            if isManualBarcodeInputVisible {
                TextField("Barcode", text: $scannerBarcodeInput)
                    .textFieldStyle(.roundedBorder)
                    .focused($barcodeInputFocused)
                    .submitLabel(.done)
                    .onSubmit(processBarcodeInput)
                    #if os(iOS)
                    .keyboardType(.numbersAndPunctuation)
                    .autocorrectionDisabled()
                    #endif

                Button("Done") {
                    isManualBarcodeInputVisible = false
                    barcodeInputFocused = true
                }
                .buttonStyle(.bordered)
            } else {
                TextField("", text: $scannerBarcodeInput)
                    .focused($barcodeInputFocused)
                    .submitLabel(.done)
                    .onSubmit(processBarcodeInput)
                    .frame(width: 1, height: 1)
                    .opacity(0.01)
                    .accessibilityHidden(true)
                    #if os(iOS)
                    .keyboardType(.numbersAndPunctuation)
                    .autocorrectionDisabled()
                    #endif

                Spacer()

                Button("Input Manually") {
                    isManualBarcodeInputVisible = true
                    barcodeInputFocused = true
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(.horizontal, 2)
        .disabled(!order.captureMutationsAllowed)
    }

    // MARK: - Sheets

    @ViewBuilder
    private var remediationDetailSheet: some View {
        if let remediation = order.remediation {
            RemediationDetailSheet(remediation: remediation, captures: order.captures)
                .presentationDetents([.medium, .large])
        }
    }

    @ViewBuilder
    private func captureViewerSheet(for capture: CompoundCapture) -> some View {
        CaptureViewerSheet(
            capture: capture,
            badge: order.badge(for: capture),
            canDelete: order.captureMutationsAllowed,
            onDelete: { deleteCapture(capture) },
            currentUser: currentUser,
            onAddPreparerPin: order.captureMutationsAllowed
                ? { x, y, note in
                    store.addPreparerFlag(
                        orderID: order.id,
                        captureID: capture.id,
                        x: x, y: y, note: note,
                        createdBy: currentUser!
                    )
                }
                : nil,
            onRemovePreparerPin: order.captureMutationsAllowed
                ? { flag in
                    store.removePreparerFlag(
                        orderID: order.id,
                        captureID: capture.id,
                        flagID: flag.id
                    )
                }
                : nil
        )
    }

    @ViewBuilder
    private func lotOverrideSheet(for context: LotOverrideContext) -> some View {
        ScanOverrideSheet(component: context.component, lot: context.lot) { field, newValue in
            guard let user = currentUser else { return }
            store.correctScannedLotField(
                orderID: order.id,
                componentID: context.component.id,
                lotID: context.lot.id,
                field: field,
                newValue: newValue,
                correctedBy: user
            )
        }
        .presentationDetents([.medium, .large])
    }

    /// Override callback for component lots, available only to users who may correct scans.
    private var overrideLotHandler: ((CompoundComponent, CompoundUtilizedLot) -> Void)? {
        guard currentUser?.role.canOverrideScan == true else { return nil }
        return { component, lot in
            lotOverrideContext = LotOverrideContext(component: component, lot: lot)
        }
    }

    // MARK: - Actions

    private func addLot(component: CompoundComponent, lot: CompoundUtilizedLot) {
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
                mfg: lot.mfg,
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

    private func processBarcodeInput() {
        let barcode = scannerBarcodeInput.trimmingCharacters(in: .whitespacesAndNewlines)
        scannerBarcodeInput = ""
        guard !barcode.isEmpty, order.captureMutationsAllowed else { return }

        guard let component = component(matchingBarcode: barcode) else {
            barcodeInputFocused = true
            return
        }

        let quantity = defaultScannedQuantity(for: component)
        addLot(
            component: component,
            lot: CompoundUtilizedLot(
                barcodeValue: barcode,
                lot: "",
                expiration: nil,
                strengthQuantity: quantity
            )
        )
        barcodeInputFocused = true
    }

    private func component(matchingBarcode barcode: String) -> CompoundComponent? {
        let normalizedScan = normalizedBarcode(barcode)
        return order.components.first { component in
            component.product.linkedNDCs.contains { normalizedBarcode($0) == normalizedScan }
        }
    }

    private func normalizedBarcode(_ value: String) -> String {
        value
            .filter { $0.isLetter || $0.isNumber }
            .map { String($0).uppercased() }
            .joined()
    }

    private func defaultScannedQuantity(for component: CompoundComponent) -> Double {
        let remaining = component.quantityRemaining
        return remaining > ComponentRow.quantityTolerance ? remaining : component.totalQuantity
    }

    private func removeLot(component: CompoundComponent, lot: CompoundUtilizedLot) {
        store.removeLot(orderID: order.id, componentID: component.id, lotID: lot.id)
    }

    private func selectStep(_ index: Int) {
        guard order.recipeSteps.indices.contains(index) else { return }
        store.setCurrentStep(orderID: order.id, stepIndex: index)
    }

    private func presentSendConfirmation() {
        guard order.captureMutationsAllowed, !order.captures.isEmpty else { return }
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
        store.deleteCapture(orderID: order.id, captureID: capture.id)
        selectedCapture = nil
    }
}
