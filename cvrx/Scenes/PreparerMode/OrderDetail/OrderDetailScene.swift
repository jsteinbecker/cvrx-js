import SwiftUI

private struct LotOverrideContext: Identifiable {
    let id = UUID()
    let component: CompoundComponent
    let lot: CompoundUtilizedLot
}

private struct OrderLockStatusBanner: View {
    let systemImage: String
    let title: String
    let message: String
    let tone: Color

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.headline)
                .foregroundStyle(tone)
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .background(tone.opacity(0.10), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(tone.opacity(0.25), lineWidth: 1)
        )
    }
}

struct LockedOrderOverlay: View {
    let order: CSPOrder
    let onBreakLock: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "lock.fill")
                .font(.title2)
                .foregroundStyle(.orange)

            VStack(spacing: 4) {
                Text("Read Only")
                    .font(.headline)
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button(role: .destructive, action: onBreakLock) {
                Label("Break Lock", systemImage: "lock.open.fill")
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(20)
        .frame(maxWidth: 340)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.orange.opacity(0.35), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.16), radius: 16, x: 0, y: 8)
    }

    private var message: String {
        let name = order.activeEditorDisplayName ?? "another user"
        return "\(name) is currently in this order. Break the lock only if you need to take over editing."
    }
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
    @State private var lockRefreshTask: Task<Void, Never>?
    @FocusState private var barcodeInputFocused: Bool

    private enum Layout {
        static let pagePadding: CGFloat = 16
        static let cardSpacing: CGFloat = 14
    }

    var body: some View {
        ZStack {
            ScrollView {
                VStack(spacing: Layout.cardSpacing) {
                    lockStatusBanner
                    HeroCard(order: order)
                        .padding(2)

                    remediationSection
                    scannerInputArea
                    ComponentsCard(
                        order: order,
                        canMutate: canEditOrder,
                        onAddLot: addLot,
                        onRemoveLot: removeLot,
                        onOverrideLot: overrideLotHandler
                    )
                    .padding(2)
                    
                    CurrentStepCard(order: order, store: store, currentUser: currentUser, canMutate: canEditOrder)
                        .padding(2)
                    
                    capturesSection
                    
                    RecipeCard(order: order, canMutate: canEditOrder, onSelectStep: selectStep)
                        .padding(2)
                }
                .opacity(order.isLockedByOther(than: currentUser) ? 0.38 : 1)
                .disabled(order.isLockedByOther(than: currentUser))
            }
            .scrollDismissesKeyboard(.automatic)

            if order.isLockedByOther(than: currentUser) {
                LockedOrderOverlay(order: order, onBreakLock: breakLock)
                    .padding(24)
            }
        }
        .padding(Layout.pagePadding)
        .background(Color.rxGroupedBackground.ignoresSafeArea())
        .navigationTitle(order.orderNumber)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .safeAreaInset(edge: .bottom) {
            BottomActionBar(order: order, canSend: canEditOrder, onSend: presentSendConfirmation)
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
            acquireLockIfPossible()
            guard canEditOrder else { return }
            barcodeInputFocused = true
        }
        .onDisappear {
            stopLockRefresh()
            releaseLockIfOwned()
        }
    }

    private var canEditOrder: Bool {
        guard order.captureMutationsAllowed else { return false }
        return order.isLocked(by: currentUser)
    }

    // MARK: - Sections

    @ViewBuilder
    private var lockStatusBanner: some View {
        if order.isLocked(by: currentUser), let name = order.activeEditorDisplayName {
            OrderLockStatusBanner(
                systemImage: "lock.open.fill",
                title: "Editing as \(name)",
                message: "Other users can view this order, but changes are locked to you while you are here.",
                tone: .green
            )
        } else if order.isLockedByOther(than: currentUser), let name = order.activeEditorDisplayName {
            OrderLockStatusBanner(
                systemImage: "lock.fill",
                title: "Locked by \(name)",
                message: "This order is read-only until the lock is released or broken.",
                tone: .orange
            )
        }
    }

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
                canMutate: canEditOrder,
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
        .disabled(!canEditOrder)
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
            canDelete: canEditOrder,
            onDelete: { deleteCapture(capture) },
            currentUser: currentUser,
            onAddPreparerPin: addPreparerPinHandler(for: capture),
            onRemovePreparerPin: removePreparerPinHandler(for: capture)
        )
    }

    private func addPreparerPinHandler(
        for capture: CompoundCapture
    ) -> ((Double, Double, String?) -> Void)? {
        guard canEditOrder, let currentUser else { return nil }
        return { x, y, note in
            store.addPreparerFlag(
                orderID: order.id,
                captureID: capture.id,
                x: x,
                y: y,
                note: note,
                createdBy: currentUser
            )
        }
    }

    private func removePreparerPinHandler(
        for capture: CompoundCapture
    ) -> ((CaptureFlag) -> Void)? {
        guard let currentUser, canEditOrder else { return nil }
        return { flag in
            store.removePreparerFlag(
                orderID: order.id,
                captureID: capture.id,
                flagID: flag.id,
                removedBy: currentUser
            )
        }
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
        guard canEditOrder, currentUser?.role.canOverrideScan == true else { return nil }
        return { component, lot in
            lotOverrideContext = LotOverrideContext(component: component, lot: lot)
        }
    }

    // MARK: - Actions

    private func addLot(component: CompoundComponent, lot: CompoundUtilizedLot) {
        guard let currentUser, canEditOrder else {
            assertionFailure("A signed-in user with the active order lock is required to add a lot.")
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
        guard !barcode.isEmpty, canEditOrder else { return }

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
        order.components.first { component in
            component.product.allowsBarcode(barcode)
        }
    }

    private func defaultScannedQuantity(for component: CompoundComponent) -> Double {
        let remaining = component.quantityRemaining
        return remaining > ComponentRow.quantityTolerance ? remaining : component.totalQuantity
    }

    private func removeLot(component: CompoundComponent, lot: CompoundUtilizedLot) {
        guard let currentUser, canEditOrder else { return }
        store.removeLot(orderID: order.id, componentID: component.id, lotID: lot.id, removedBy: currentUser)
    }

    private func selectStep(_ index: Int) {
        guard let currentUser, canEditOrder, order.recipeSteps.indices.contains(index) else { return }
        store.setCurrentStep(orderID: order.id, stepIndex: index, changedBy: currentUser)
    }

    private func presentSendConfirmation() {
        guard canEditOrder, !order.captures.isEmpty else { return }
        isSendConfirmationPresented = true
    }

    private func sendToVerification() {
        guard let currentUser, canEditOrder else { return }
        store.markReadyForVerification(orderID: order.id, by: currentUser)
        dismiss()
    }

    private func resubmitAfterRemediation() {
        guard canEditOrder else { return }
        store.resubmitAfterRemediation(orderID: order.id)
    }

    private func deleteCapture(_ capture: CompoundCapture) {
        guard let currentUser, canEditOrder else { return }
        store.deleteCapture(orderID: order.id, captureID: capture.id, deletedBy: currentUser)
        selectedCapture = nil
    }

    private func acquireLockIfPossible() {
        guard let currentUser, order.captureMutationsAllowed else { return }
        guard store.acquireOrderLock(orderID: order.id, by: currentUser) else { return }
        startLockRefresh()
    }

    private func breakLock() {
        guard let currentUser else { return }
        guard store.acquireOrderLock(orderID: order.id, by: currentUser, breakingExisting: true) else { return }
        startLockRefresh()
        barcodeInputFocused = order.captureMutationsAllowed
    }

    private func startLockRefresh() {
        guard let currentUser else { return }
        stopLockRefresh()
        lockRefreshTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(10))
                guard !Task.isCancelled else { return }
                store.refreshOrderLock(orderID: order.id, by: currentUser)
            }
        }
    }

    private func stopLockRefresh() {
        lockRefreshTask?.cancel()
        lockRefreshTask = nil
    }

    private func releaseLockIfOwned() {
        guard let currentUser else { return }
        store.releaseOrderLock(orderID: order.id, by: currentUser)
    }
}
