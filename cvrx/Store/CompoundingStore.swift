import SwiftUI
import SwiftData

@Observable
final class CompoundingStore {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        seedIfNeeded()
    }

    private func seedIfNeeded() {
        let descriptor = FetchDescriptor<CSPOrder>()
        guard (try? modelContext.fetchCount(descriptor)) == 0 else { return }
        MockData.makeSampleOrders(into: modelContext)
        MockData.makeFacility(into: modelContext)
    }

    private func order(for id: CSPOrder.ID) -> CSPOrder? {
        var descriptor = FetchDescriptor<CSPOrder>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        return try? modelContext.fetch(descriptor).first
    }
    
    private func flag(for id: CaptureFlag.ID) -> CaptureFlag? {
        var descriptor = FetchDescriptor<CaptureFlag>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        return try? modelContext.fetch(descriptor).first
    }

    // MARK: - Lot Entry

    func processBarcodeScan(
        orderID: CSPOrder.ID,
        componentID: CompoundComponent.ID,
        scannedBarcode: String,
        detectedLot: String,
        detectedExpiration: Date?,
        mfg: String? = nil,
        quantity: Double,
        scannedBy: User
    ) {
        guard scannedBy.role.canScan else { return }
        guard let order = order(for: orderID),
              let componentIndex = order.components.firstIndex(where: { $0.id == componentID })
        else { return }

        let lot = CompoundUtilizedLot(
            barcodeValue: scannedBarcode,
            lot: detectedLot,
            expiration: detectedExpiration,
            mfg: mfg,
            strengthQuantity: quantity,
            scannedBy: scannedBy,
            scannedAt: Date.now
        )

        order.components[componentIndex].utilizedLots.append(lot)

        order.auditEvents.append(AuditEvent(
            actor: scannedBy,
            action: .lotScanned(
                orderID: orderID,
                componentID: componentID,
                lotID: lot.id,
                barcodeValue: scannedBarcode,
                lot: detectedLot,
                expiration: detectedExpiration
            ),
            context: "Barcode scan via camera"
        ))

        if order.status == .pending { order.status = .staging }
    }

    func addLotManually(
        orderID: CSPOrder.ID,
        componentID: CompoundComponent.ID,
        lot: String,
        expiration: Date?,
        mfg: String? = nil,
        quantity: Double,
        enteredBy: User
    ) {
        guard enteredBy.role.canScan else { return }
        guard let order = order(for: orderID),
              let componentIndex = order.components.firstIndex(where: { $0.id == componentID })
        else { return }

        let utilizedLot = CompoundUtilizedLot(
            lot: lot,
            expiration: expiration,
            mfg: mfg,
            strengthQuantity: quantity,
            scannedBy: enteredBy,
            scannedAt: Date.now
        )

        order.components[componentIndex].utilizedLots.append(utilizedLot)

        order.auditEvents.append(AuditEvent(
            actor: enteredBy,
            action: .lotManuallyEntered(
                orderID: orderID,
                componentID: componentID,
                lotID: utilizedLot.id,
                lot: lot,
                expiration: expiration
            ),
            context: "Manual entry (barcode unavailable)"
        ))

        if order.status == .pending { order.status = .staging }
    }

    func correctScannedLotField(
        orderID: CSPOrder.ID,
        componentID: CompoundComponent.ID,
        lotID: CompoundUtilizedLot.ID,
        field: String,
        newValue: String,
        correctedBy: User
    ) {
        guard correctedBy.role.canOverrideScan else { return }
        guard let order = order(for: orderID),
              let componentIndex = order.components.firstIndex(where: { $0.id == componentID }),
              let lotIndex = order.components[componentIndex].utilizedLots.firstIndex(where: { $0.id == lotID })
        else { return }

        let lot = order.components[componentIndex].utilizedLots[lotIndex]
        var previousValue = ""

        switch field {
            case "barcode":    previousValue = lot.barcodeValue ?? ""
            case "lot":        previousValue = lot.lot
            case "expiration": previousValue = lot.expiration?.formatted(date: .abbreviated, time: .omitted) ?? ""
            default: return
        }

        let override = ScanOverride(
            lotID: lotID,
            field: field,
            previousValue: previousValue,
            newValue: newValue,
            overriddenBy: correctedBy
        )

        switch field {
            case "barcode": order.components[componentIndex].utilizedLots[lotIndex].barcodeValue = newValue
            case "lot": order.components[componentIndex].utilizedLots[lotIndex].lot = newValue
            case "expiration":
                if let date = parseDate(newValue) {
                    order.components[componentIndex].utilizedLots[lotIndex].expiration = date
                }
            default: break
        }

        order.components[componentIndex].utilizedLots[lotIndex].overrides.append(override)

        order.auditEvents.append(AuditEvent(
            actor: correctedBy,
            action: .lotOverridden(
                orderID: orderID,
                componentID: componentID,
                lotID: lotID,
                field: field,
                previousValue: previousValue,
                newValue: newValue
            ),
            context: "Technician correction — pending verifier cosign"
        ))
    }

    func cosignLotCorrection(
        orderID: CSPOrder.ID,
        componentID: CompoundComponent.ID,
        lotID: CompoundUtilizedLot.ID,
        overrideID: ScanOverride.ID,
        cosignedBy: User
    ) {
        guard cosignedBy.role.canVerify else { return }
        guard let order = order(for: orderID),
              let componentIndex = order.components.firstIndex(where: { $0.id == componentID }),
              let lotIndex = order.components[componentIndex].utilizedLots.firstIndex(where: { $0.id == lotID }),
              let overrideIndex = order.components[componentIndex].utilizedLots[lotIndex].overrides.firstIndex(where: { $0.id == overrideID })
        else { return }

        order.components[componentIndex].utilizedLots[lotIndex].overrides[overrideIndex].cosignedBy = cosignedBy
        order.components[componentIndex].utilizedLots[lotIndex].overrides[overrideIndex].cosignedAt = Date()

        let override = order.components[componentIndex].utilizedLots[lotIndex].overrides[overrideIndex]
        order.auditEvents.append(AuditEvent(
            actor: cosignedBy,
            action: .scanOverrideCosigned(
                orderID: orderID,
                componentID: componentID,
                lotID: lotID,
                field: override.field,
                cosignedBy: cosignedBy.snapshot
            ),
            context: "Verifier approval of \(override.field) correction"
        ))
    }

    func removeLot(
        orderID: CSPOrder.ID,
        componentID: CompoundComponent.ID,
        lotID: CompoundUtilizedLot.ID
    ) {
        guard let order = order(for: orderID),
              let componentIndex = order.components.firstIndex(where: { $0.id == componentID })
        else { return }

        order.components[componentIndex].utilizedLots.removeAll { $0.id == lotID }
    }

    // MARK: - Captures

    func addCapture(
        orderID: CSPOrder.ID,
        kind: CaptureKind,
        imageURL: URL?,
        capturedBy: User
    ) {
        guard capturedBy.role.canRemediate else { return }
        guard let order = order(for: orderID) else { return }

        let capture = CompoundCapture(
            cspOrder: order,
            kind: kind,
            capturedBy: capturedBy,
            timestamp: .now,
            imageURL: imageURL,
            imageName: imageURL?.lastPathComponent,
            note: imageURL == nil ? "Capture recorded, but no image file was saved." : nil
        )

        order.captures.append(capture)
        order.captures.sort { $0.timestamp < $1.timestamp }

        order.auditEvents.append(AuditEvent(
            actor: capturedBy,
            action: .imageCaptured(
                orderID: orderID,
                captureID: capture.id,
                kind: kind.rawValue,
                imageName: capture.imageName ?? "unnamed"
            ),
            context: "Compounding documentation photograph"
        ))

        if order.status == .pending { order.status = .staging }
    }

    @discardableResult
    func deleteCapture(orderID: CSPOrder.ID, captureID: CompoundCapture.ID) -> Bool {
        guard let order = order(for: orderID) else { return false }
        guard order.captureMutationsAllowed else { return false }

        order.captures.removeAll { $0.id == captureID }

        if let rem = order.remediation {
            rem.flags.removeAll { $0.captureID == captureID }
            order.remediation = rem
        }
        return true
    }

    func addPreparerFlag(
        orderID: CSPOrder.ID,
        captureID: CompoundCapture.ID,
        x: Double,
        y: Double,
        note: String?,
        createdBy: User
    ) {
        guard let order = order(for: orderID),
              let captureIndex = order.captures.firstIndex(where: { $0.id == captureID })
        else { return }

        let flag = CaptureFlag(captureID: captureID, x: x, y: y, createdBy: createdBy, note: note)
        order.captures[captureIndex].preparerFlags.append(flag)
    }

    func removePreparerFlag(
        orderID: CSPOrder.ID,
        captureID: CompoundCapture.ID,
        flagID: CaptureFlag.ID
    ) {
        guard let order = order(for: orderID),
              let captureIndex = order.captures.firstIndex(where: { $0.id == captureID })
        else { return }

        order.captures[captureIndex].preparerFlags.removeAll { $0.id == flagID }
    }

    func setCurrentStep(orderID: CSPOrder.ID, stepIndex: Int) {
        guard let order = order(for: orderID) else { return }
        let total = order.recipeSteps.count
        guard total > 0 else { return }
        order.currentStepIndex = min(max(stepIndex, 0), total - 1)
    }

    func advanceStep(orderID: CSPOrder.ID) {
        guard let order = order(for: orderID) else { return }
        let total = order.recipeSteps.count
        guard total > 0 else { return }
        order.currentStepIndex = min(order.currentStepIndex + 1, total - 1)
    }

    func previousStep(orderID: CSPOrder.ID) {
        guard let order = order(for: orderID) else { return }
        order.currentStepIndex = max(order.currentStepIndex - 1, 0)
    }

    func beginPreparing(orderID: CSPOrder.ID) {
        guard let order = order(for: orderID) else { return }
        guard [.pending, .staging].contains(order.status) else { return }
        order.status = .preparing
    }

    // MARK: - Verification

    func markReadyForVerification(orderID: CSPOrder.ID) {
        guard let order = order(for: orderID) else { return }
        order.status = .waitingForApproval
    }

    func verify(
        orderID: CSPOrder.ID,
        verifiedBy: User,
        approved: Bool,
        rejectionReason: String? = nil
    ) {
        guard verifiedBy.role.canVerify else { return }
        guard let order = order(for: orderID) else { return }

        let decision = approved ? VerificationDecision.approved : .rejected
        order.verificationRecord = VerificationRecord(
            verifiedBy: verifiedBy,
            decision: decision,
            rejectionReason: rejectionReason
        )
        order.status = approved ? .approved : .rejected

        order.auditEvents.append(AuditEvent(
            actor: verifiedBy,
            action: .verificationPerformed(
                orderID: orderID,
                decision: decision.rawValue,
                rejectionReason: rejectionReason
            ),
            context: "Final verification after review of all scans, images, and overrides"
        ))

        if !approved {
            createRemediationRequest(
                orderID: orderID,
                reason: rejectionReason ?? "Compound rejected during verification",
                requestedBy: verifiedBy
            )
        }
    }

    func createRemediationRequest(
        orderID: CSPOrder.ID,
        reason: String,
        requestedBy: User
    ) {
        guard requestedBy.role.canVerify else { return }
        guard let order = order(for: orderID) else { return }

        let remediation = RemediationRequest(requestedBy: requestedBy, reason: reason)
        order.remediation = remediation
        order.status = .remediation

        order.auditEvents.append(AuditEvent(
            actor: requestedBy,
            action: .remediationRequested(
                orderID: orderID,
                remediationRequestID: remediation.id,
                reason: reason,
                requestedBy: requestedBy.snapshot
            ),
            context: "Rejected during verification; sent back to compounder for fixes"
        ))
    }

    // MARK: - Remediation

    func captureRemediationImage(
        orderID: CSPOrder.ID,
        imageURL: URL?,
        capturedBy: User,
        note: String? = nil
    ) {
        guard capturedBy.role.canRemediate else { return }
        guard let order = order(for: orderID),
              let remediation = order.remediation
        else { return }

        let capture = RemediationCapture(
            remediationRequestID: remediation.id,
            capturedBy: capturedBy,
            imageURL: imageURL,
            imageName: imageURL?.lastPathComponent,
            note: note
        )

        remediation.remediationCaptures.append(capture)
        order.remediation = remediation

        order.auditEvents.append(AuditEvent(
            actor: capturedBy,
            action: .remediationImageCaptured(
                orderID: orderID,
                captureID: capture.id,
                imageName: capture.imageName ?? "unnamed",
                remediationRequestID: remediation.id
            ),
            context: "Documenting remediation fix with photograph"
        ))
    }

    func recordRemediationLotChange(
        orderID: CSPOrder.ID,
        componentID: CompoundComponent.ID,
        lotID: CompoundUtilizedLot.ID,
        changeType: String,
        madeBy: User,
        descr: String? = nil
    ) {
        guard madeBy.role.canRemediate else { return }
        guard let order = order(for: orderID),
              let remediation = order.remediation
        else { return }

        let change = RemediationLotChange(
            remediationRequestID: remediation.id,
            componentID: componentID,
            lotID: lotID,
            changeType: changeType,
            madeBy: madeBy,
            descr: descr
        )

        remediation.lotChanges.append(change)
        order.remediation = remediation
    }

    func completeRemediation(orderID: CSPOrder.ID, completedBy: User) {
        guard completedBy.role.canRemediate else { return }
        guard let order = order(for: orderID),
              let remediation = order.remediation
        else { return }

        remediation.completedBy = completedBy
        remediation.completedAt = Date()
        order.remediation = remediation
        order.status = .waitingForApproval

        order.auditEvents.append(AuditEvent(
            actor: completedBy,
            action: .remediationCompleted(
                orderID: orderID,
                remediationRequestID: remediation.id,
                completedBy: completedBy.snapshot
            ),
            context: "Remediation fixes complete; resubmitted for verification"
        ))
    }

    func resubmitAfterRemediation(orderID: CSPOrder.ID) {
        guard let order = order(for: orderID) else { return }
        order.status = .waitingForApproval
    }
}

// MARK: - Helper

private func parseDate(_ string: String) -> Date? {
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    return formatter.date(from: string)
}
