import SwiftUI

@Observable
final class CompoundingStore {
    var orders: [CompoundOrder] = MockData.orders

    /// Queue shown in the Verification tab.
    var ordersReadyForVerification: [CompoundOrder] {
        orders.filter { $0.status == .readyForVerification }
    }

    func orderBinding(for orderID: CompoundOrder.ID) -> Binding<CompoundOrder>? {
        guard let index = orders.firstIndex(where: { $0.id == orderID }) else { return nil }
        return Binding(
            get: { self.orders[index] },
            set: { self.orders[index] = $0 }
        )
    }

    /// Process a barcode scan result into a lot entry with full audit tracking.
    func processBarcodeScan(
        orderID: CompoundOrder.ID,
        componentID: CompoundComponent.ID,
        scannedBarcode: String,
        detectedLot: String,
        detectedExpiration: Date?,
        quantity: Double,
        scannedBy: User
    ) {
        guard scannedBy.role.canScan else {
            print("User \(scannedBy.username) does not have scan permission")
            return
        }

        guard let orderIndex = orders.firstIndex(where: { $0.id == orderID }),
              let componentIndex = orders[orderIndex].components.firstIndex(where: { $0.id == componentID })
        else { return }

        let lot = CompoundUtilizedLot(
            barcodeValue: scannedBarcode,
            lot: detectedLot,
            expiration: detectedExpiration,
            strengthQuantity: quantity,
            scannedBy: scannedBy,
            scannedAt: Date.now
        )

        orders[orderIndex].components[componentIndex].utilizedLots.append(lot)

        // Log audit event
        let event = AuditEvent(
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
        )
        orders[orderIndex].auditEvents.append(event)

        if orders[orderIndex].status == .pending {
            orders[orderIndex].status = .compounding
        }
    }

    /// Manual lot entry when barcode scan is unavailable.
    func addLotManually(
        orderID: CompoundOrder.ID,
        componentID: CompoundComponent.ID,
        lot: String,
        expiration: Date?,
        quantity: Double,
        enteredBy: User
    ) {
        guard enteredBy.role.canScan else {
            print("User \(enteredBy.username) does not have scan permission")
            return
        }

        guard let orderIndex = orders.firstIndex(where: { $0.id == orderID }),
              let componentIndex = orders[orderIndex].components.firstIndex(where: { $0.id == componentID })
        else { return }

        let utilizedLot = CompoundUtilizedLot(
            lot: lot,
            expiration: expiration,
            strengthQuantity: quantity,
            scannedBy: enteredBy,
            scannedAt: Date.now
        )

        orders[orderIndex].components[componentIndex].utilizedLots.append(utilizedLot)

        // Log audit event
        let event = AuditEvent(
            actor: enteredBy,
            action: .lotManuallyEntered(
                orderID: orderID,
                componentID: componentID,
                lotID: utilizedLot.id,
                lot: lot,
                expiration: expiration
            ),
            context: "Manual entry (barcode unavailable)"
        )
        orders[orderIndex].auditEvents.append(event)

        if orders[orderIndex].status == .pending {
            orders[orderIndex].status = .compounding
        }
    }

    /// Correct a scanned lot's data (barcode, lot number, or expiration).
    func correctScannedLotField(
        orderID: CompoundOrder.ID,
        componentID: CompoundComponent.ID,
        lotID: CompoundUtilizedLot.ID,
        field: String,  // "barcode", "lot", or "expiration"
        newValue: String,
        correctedBy: User
    ) {
        guard correctedBy.role.canOverrideScan else {
            print("User \(correctedBy.username) does not have override permission")
            return
        }

        guard let orderIndex = orders.firstIndex(where: { $0.id == orderID }),
              let componentIndex = orders[orderIndex].components.firstIndex(where: { $0.id == componentID }),
              let lotIndex = orders[orderIndex].components[componentIndex].utilizedLots.firstIndex(where: { $0.id == lotID })
        else { return }

        let lot = orders[orderIndex].components[componentIndex].utilizedLots[lotIndex]
        var previousValue = ""

        // Capture old value
        switch field {
        case "barcode":
            previousValue = lot.barcodeValue ?? ""
        case "lot":
            previousValue = lot.lot
        case "expiration":
            previousValue = lot.expiration?.formatted(date: .abbreviated, time: .omitted) ?? ""
        default:
            return
        }

        // Create override record (pending cosign)
        let override = ScanOverride(
            lotID: lotID,
            field: field,
            previousValue: previousValue,
            newValue: newValue,
            overriddenBy: correctedBy
        )

        // Apply the change
        switch field {
        case "barcode":
            orders[orderIndex].components[componentIndex].utilizedLots[lotIndex].barcodeValue = newValue
        case "lot":
            orders[orderIndex].components[componentIndex].utilizedLots[lotIndex].lot = newValue
        case "expiration":
            if let date = parseDate(newValue) {
                orders[orderIndex].components[componentIndex].utilizedLots[lotIndex].expiration = date
            }
        default:
            break
        }

        // Add override to history
        orders[orderIndex].components[componentIndex].utilizedLots[lotIndex].overrides.append(override)

        // Log audit event
        let event = AuditEvent(
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
        )
        orders[orderIndex].auditEvents.append(event)
    }

    /// Pharmacist (RPh) cosigns a scan override, making it official.
    func cosignLotCorrection(
        orderID: CompoundOrder.ID,
        componentID: CompoundComponent.ID,
        lotID: CompoundUtilizedLot.ID,
        overrideID: ScanOverride.ID,
        cosignedBy: User
    ) {
        guard cosignedBy.role.canVerify else {
            print("Only RPhs can cosign overrides. User \(cosignedBy.username) does not have verify permission")
            return
        }

        guard let orderIndex = orders.firstIndex(where: { $0.id == orderID }),
              let componentIndex = orders[orderIndex].components.firstIndex(where: { $0.id == componentID }),
              let lotIndex = orders[orderIndex].components[componentIndex].utilizedLots.firstIndex(where: { $0.id == lotID }),
              let overrideIndex = orders[orderIndex].components[componentIndex].utilizedLots[lotIndex].overrides.firstIndex(where: { $0.id == overrideID })
        else { return }

        // Mark override as cosigned
        orders[orderIndex].components[componentIndex].utilizedLots[lotIndex].overrides[overrideIndex].cosignedBy = cosignedBy
        orders[orderIndex].components[componentIndex].utilizedLots[lotIndex].overrides[overrideIndex].cosignedAt = Date()

        // Log audit event
        let override = orders[orderIndex].components[componentIndex].utilizedLots[lotIndex].overrides[overrideIndex]
        let event = AuditEvent(
            actor: cosignedBy,
            action: .scanOverrideCosigned(
                orderID: orderID,
                componentID: componentID,
                lotID: lotID,
                field: override.field,
                cosignedBy: cosignedBy
            ),
            context: "Verifier approval of \(override.field) correction"
        )
        orders[orderIndex].auditEvents.append(event)
    }

    /// Delete a lot (only allowed while status permits).
    func removeLot(
        orderID: CompoundOrder.ID,
        componentID: CompoundComponent.ID,
        lotID: CompoundUtilizedLot.ID
    ) {
        guard let orderIndex = orders.firstIndex(where: { $0.id == orderID }),
              let componentIndex = orders[orderIndex].components.firstIndex(where: { $0.id == componentID })
        else { return }

        orders[orderIndex].components[componentIndex].utilizedLots.removeAll { $0.id == lotID }
    }

    // MARK: - Captures with Audit Trail

    /// Capture an image during compounding with photographer attribution.
    func addCapture(
        orderID: CompoundOrder.ID,
        kind: CaptureKind,
        imageURL: URL?,
        capturedBy: User
    ) {
        guard capturedBy.role.canRemediate else {
            print("User \(capturedBy.username) does not have remediation/capture permission")
            return
        }

        guard let orderIndex = orders.firstIndex(where: { $0.id == orderID }) else { return }

        let capture = CompoundCapture(
            kind: kind,
            capturedBy: capturedBy,
            timestamp: .now,
            imageURL: imageURL,
            imageName: imageURL?.lastPathComponent,
            note: imageURL == nil ? "Capture recorded, but no image file was saved." : nil
        )

        orders[orderIndex].captures.append(capture)
        orders[orderIndex].captures.sort { $0.timestamp < $1.timestamp }

        // Log audit event
        let event = AuditEvent(
            actor: capturedBy,
            action: .imageCaptured(
                orderID: orderID,
                captureID: capture.id,
                kind: kind.rawValue,
                imageName: capture.imageName ?? "unnamed"
            ),
            context: "Compounding documentation photograph"
        )
        orders[orderIndex].auditEvents.append(event)

        if orders[orderIndex].status == .pending {
            orders[orderIndex].status = .compounding
        }
    }

    /// Delete a capture and any remediation pins that referenced it.
    /// Only permitted while the order's `captureMutationsAllowed` is true.
    @discardableResult
    func deleteCapture(orderID: CompoundOrder.ID, captureID: CompoundCapture.ID) -> Bool {
        guard let orderIndex = orders.firstIndex(where: { $0.id == orderID }) else { return false }
        guard orders[orderIndex].captureMutationsAllowed else { return false }

        orders[orderIndex].captures.removeAll { $0.id == captureID }

        // If this capture had pins on it from a remediation, drop those pins
        if var rem = orders[orderIndex].remediation {
            rem.flags.removeAll { $0.captureID == captureID }
            orders[orderIndex].remediation = rem
        }
        return true
    }

    // MARK: - Recipe Navigation

    func setCurrentStep(orderID: CompoundOrder.ID, stepIndex: Int) {
        guard let index = orders.firstIndex(where: { $0.id == orderID }) else { return }
        let total = orders[index].recipeSteps.count
        guard total > 0 else { return }
        orders[index].currentStepIndex = min(max(stepIndex, 0), total - 1)
    }

    func advanceStep(orderID: CompoundOrder.ID) {
        guard let index = orders.firstIndex(where: { $0.id == orderID }) else { return }
        let total = orders[index].recipeSteps.count
        guard total > 0 else { return }
        orders[index].currentStepIndex = min(orders[index].currentStepIndex + 1, total - 1)
    }

    func previousStep(orderID: CompoundOrder.ID) {
        guard let index = orders.firstIndex(where: { $0.id == orderID }) else { return }
        orders[index].currentStepIndex = max(orders[index].currentStepIndex - 1, 0)
    }

    // MARK: - Verification with Audit Trail

    func markReadyForVerification(orderID: CompoundOrder.ID) {
        guard let index = orders.firstIndex(where: { $0.id == orderID }) else { return }
        orders[index].status = .readyForVerification
    }

    /// Pharmacist (RPh) verifies the compound: approve or reject with reason.
    func verify(
        orderID: CompoundOrder.ID,
        verifiedBy: User,
        approved: Bool,
        rejectionReason: String? = nil
    ) {
        guard verifiedBy.role.canVerify else {
            print("Only RPhs can verify. User \(verifiedBy.username) does not have verify permission")
            return
        }

        guard let orderIndex = orders.firstIndex(where: { $0.id == orderID }) else { return }

        let decision = approved ? "Approved" : "Rejected"

        // Create verification record
        let record = VerificationRecord(
            verifiedBy: verifiedBy,
            decision: decision,
            rejectionReason: rejectionReason
        )

        orders[orderIndex].verificationRecord = record
        orders[orderIndex].status = approved ? .approved : .rejected

        // Log audit event
        let event = AuditEvent(
            actor: verifiedBy,
            action: .verificationPerformed(
                orderID: orderID,
                decision: decision,
                rejectionReason: rejectionReason
            ),
            context: "Final verification after review of all scans, images, and overrides"
        )
        orders[orderIndex].auditEvents.append(event)

        // If rejected, create remediation request
        if !approved {
            createRemediationRequest(
                orderID: orderID,
                reason: rejectionReason ?? "Compound rejected during verification",
                requestedBy: verifiedBy
            )
        }
    }

    /// Pharmacist (RPh) rejects the compound and requests remediation.
    func createRemediationRequest(
    orderID: CompoundOrder.ID,
    reason: String,
    requestedBy: User
) {
    guard requestedBy.role.canVerify else { return }
    guard let orderIndex = orders.firstIndex(where: { $0.id == orderID }) else { return }

    let remediation = RemediationRequest(
        requestedBy: requestedBy,
        reason: reason
    )

    orders[orderIndex].remediation = remediation
    orders[orderIndex].status = .remediation

    // Log remediation request
    let event = AuditEvent(
        actor: requestedBy,
        action: .remediationRequested(
            orderID: orderID,
            remediationRequestID: remediation.id,
            reason: reason,
            requestedBy: requestedBy
        ),
        context: "Rejected during verification; sent back to compounder for fixes"
    )
    orders[orderIndex].auditEvents.append(event)
}

    // MARK: - Remediation with Audit Trail

    /// Capture an image during remediation to document a fix.
    func captureRemediationImage(
        orderID: CompoundOrder.ID,
        imageURL: URL?,
        capturedBy: User,
        note: String? = nil
    ) {
        guard capturedBy.role.canRemediate else {
            print("User \(capturedBy.username) does not have remediation permission")
            return
        }

        guard let orderIndex = orders.firstIndex(where: { $0.id == orderID }),
              var remediation = orders[orderIndex].remediation
        else { return }

        let capture = RemediationCapture(
            remediationRequestID: remediation.id,
            capturedBy: capturedBy,
            imageURL: imageURL,
            imageName: imageURL?.lastPathComponent,
            note: note
        )

        remediation.remediationCaptures.append(capture)
        orders[orderIndex].remediation = remediation

        // Log audit event
        let event = AuditEvent(
            actor: capturedBy,
            action: .remediationImageCaptured(
                orderID: orderID,
                captureID: capture.id,
                imageName: capture.imageName ?? "unnamed",
                remediationRequestID: remediation.id
            ),
            context: "Documenting remediation fix with photograph"
        )
        orders[orderIndex].auditEvents.append(event)
    }

    /// Record a lot change during remediation (replaced, re-scanned, or data updated).
    func recordRemediationLotChange(
        orderID: CompoundOrder.ID,
        componentID: CompoundComponent.ID,
        lotID: CompoundUtilizedLot.ID,
        changeType: String,  // "replaced", "reScanned", "dataUpdated"
        madeBy: User,
        description: String? = nil
    ) {
        guard madeBy.role.canRemediate else {
            print("User \(madeBy.username) does not have remediation permission")
            return
        }

        guard let orderIndex = orders.firstIndex(where: { $0.id == orderID }),
              var remediation = orders[orderIndex].remediation
        else { return }

        let change = RemediationLotChange(
            remediationRequestID: remediation.id,
            componentID: componentID,
            lotID: lotID,
            changeType: changeType,
            madeBy: madeBy,
            description: description
        )

        remediation.lotChanges.append(change)
        orders[orderIndex].remediation = remediation
    }

    /// Complete remediation and resubmit for verification.
    func completeRemediation(
        orderID: CompoundOrder.ID,
        completedBy: User
    ) {
        guard completedBy.role.canRemediate else {
            print("User \(completedBy.username) does not have remediation permission")
            return
        }

        guard let orderIndex = orders.firstIndex(where: { $0.id == orderID }),
              var remediation = orders[orderIndex].remediation
        else { return }

        remediation.completedBy = completedBy
        remediation.completedAt = Date()
        orders[orderIndex].remediation = remediation
        orders[orderIndex].status = .readyForVerification

        // Log remediation completion
        let event = AuditEvent(
            actor: completedBy,
            action: .remediationCompleted(
                orderID: orderID,
                remediationRequestID: remediation.id,
                completedBy: completedBy
            ),
            context: "Remediation fixes complete; resubmitted for verification"
        )
        orders[orderIndex].auditEvents.append(event)
    }

    /// After remediation the compounder can resubmit, sending it back to the queue.
    func resubmitAfterRemediation(orderID: CompoundOrder.ID) {
        guard let index = orders.firstIndex(where: { $0.id == orderID }) else { return }
        orders[index].status = .readyForVerification
    }
}

// MARK: - Helper

private func parseDate(_ string: String) -> Date? {
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    return formatter.date(from: string)
}
