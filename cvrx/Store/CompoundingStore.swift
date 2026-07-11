import SwiftUI
import SwiftData

@MainActor
@Observable
final class CompoundingStore {
    let modelContext: ModelContext
    var supabaseAuth: SupabaseAuthService?
    private var supabaseRealtime: SupabaseRealtimeService?
    private var realtimeSyncTask: Task<Void, Never>?

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        seedIfNeeded()
    }

    func configureSupabaseAuth(_ supabaseAuth: SupabaseAuthService?) {
        self.supabaseAuth = supabaseAuth
    }

    func writeToSupabase(_ operation: @escaping @MainActor (SupabaseWriteService) async throws -> Void) {
        guard let supabaseAuth else { return }
        Task { @MainActor in
            do {
                try await operation(SupabaseWriteService(authService: supabaseAuth))
            } catch {
                print("Supabase write failed: \(error.localizedDescription)")
            }
        }
    }

    func startSupabaseRealtime(currentUser: User) {
        guard let supabaseAuth else { return }
        let currentUserID = currentUser.id
        Task { [weak self, supabaseAuth, currentUserID] in
            do {
                let connectionInfo = try await supabaseAuth.makeRealtimeConnectionInfo()
                let realtime = SupabaseRealtimeService(connectionInfo: connectionInfo) { [weak self, currentUserID] in
                    await self?.scheduleSupabaseRealtimeSync(currentUserID: currentUserID)
                }
                await MainActor.run {
                    self?.supabaseRealtime = realtime
                }
                await realtime.start()
            } catch {
                print("Supabase realtime start failed: \(error.localizedDescription)")
            }
        }
    }

    func stopSupabaseRealtime() {
        realtimeSyncTask?.cancel()
        realtimeSyncTask = nil
        guard let supabaseRealtime else { return }
        self.supabaseRealtime = nil
        Task {
            await supabaseRealtime.stop()
        }
    }

    private func scheduleSupabaseRealtimeSync(currentUserID: User.ID) {
        realtimeSyncTask?.cancel()
        realtimeSyncTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled,
                  let self,
                  let supabaseAuth = self.supabaseAuth,
                  let currentUser = self.user(for: currentUserID)
            else { return }
            await self.syncOrdersFromSupabase(supabaseAuth, currentUser: currentUser)
        }
    }

    private func seedIfNeeded() {
        seedOrdersIfNeeded()
        seedFacilityIfNeeded()
        seedUsersIfNeeded()
        refreshLabelerLookupCache()
    }

    private func seedOrdersIfNeeded() {
        let descriptor = FetchDescriptor<CSPOrder>()
        guard (try? modelContext.fetchCount(descriptor)) == 0 else { return }
        MockData.makeSampleOrders(into: modelContext)
    }

    private func seedFacilityIfNeeded() {
        let descriptor = FetchDescriptor<Facility>()
        guard (try? modelContext.fetchCount(descriptor)) == 0 else { return }
        MockData.makeFacility(into: modelContext)
    }

    private func seedUsersIfNeeded() {
        let descriptor = FetchDescriptor<User>()
        guard (try? modelContext.fetchCount(descriptor)) == 0 else { return }
        modelContext.insert(MockData.makeUserJts())
        modelContext.insert(MockData.makeUserMsm())
        try? modelContext.save()
    }

    @discardableResult
    func generateSampleOrders(count: Int = 1) -> [CSPOrder] {
        let orders = MockData.makeSampleOrders(into: modelContext, count: count)
        try? modelContext.save()

        for order in orders {
            writeToSupabase { writer in
                try await writer.insertGeneratedOrder(order)
            }
        }

        return orders
    }

    func authenticateUser(username: String, password: String, facilityID: String) -> User? {
        let normalizedUsername = username.normalizedLoginValue
        guard !normalizedUsername.isEmpty,
              !password.isEmpty,
              !facilityID.normalizedLoginValue.isEmpty
        else { return nil }

        let descriptor = FetchDescriptor<User>()
        guard let users = try? modelContext.fetch(descriptor) else { return nil }

        return users.first { user in
            user.active
            && user.username.normalizedLoginValue == normalizedUsername
            && user.matchesFacilityID(facilityID)
            && user.passwordMatches(password)
        }
    }

    private func order(for id: CSPOrder.ID) -> CSPOrder? {
        var descriptor = FetchDescriptor<CSPOrder>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        return try? modelContext.fetch(descriptor).first
    }

    private func user(for id: User.ID) -> User? {
        var descriptor = FetchDescriptor<User>(
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

    private func mutationsAllowed(on order: CSPOrder, by user: User) -> Bool {
        !order.isLockedByOther(than: user)
    }

    @discardableResult
    func acquireOrderLock(orderID: CSPOrder.ID, by user: User, breakingExisting: Bool = false) -> Bool {
        guard let order = order(for: orderID) else { return false }
        guard breakingExisting || !order.isLockedByOther(than: user) else { return false }

        order.activeEditorID = user.id
        order.activeEditorUsername = user.username
        order.activeEditorName = user.name
        order.activeEditorLastSeenAt = Date.now
        writeToSupabase { writer in
            _ = try await writer.acquireOrderLock(orderID: orderID, breakingExisting: breakingExisting)
        }
        return true
    }

    func refreshOrderLock(orderID: CSPOrder.ID, by user: User) {
        guard let order = order(for: orderID), order.isLocked(by: user) else { return }
        order.activeEditorLastSeenAt = Date.now
        writeToSupabase { writer in
            try await writer.refreshOrderLock(orderID: orderID)
        }
    }

    func releaseOrderLock(orderID: CSPOrder.ID, by user: User) {
        guard let order = order(for: orderID), order.isLocked(by: user) else { return }
        order.activeEditorID = nil
        order.activeEditorUsername = nil
        order.activeEditorName = nil
        order.activeEditorLastSeenAt = nil
        writeToSupabase { writer in
            try await writer.releaseOrderLock(orderID: orderID)
        }
    }

    // MARK: - Lot Entry

    func addUnexpectedComponent(
        orderID: CSPOrder.ID,
        barcodeValue: String,
        addedBy user: User
    ) {
        guard user.role.canScan else { return }
        guard let order = order(for: orderID), mutationsAllowed(on: order, by: user) else { return }

        let trimmedBarcode = barcodeValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedBarcode.isEmpty else { return }

        let lot = CompoundUtilizedLot(
            barcodeValue: trimmedBarcode,
            lot: "",
            expiration: nil,
            strengthQuantity: 1,
            scannedBy: user,
            scannedAt: Date.now
        )
        let product = Product(
            name: "Unexpected product \(trimmedBarcode)",
            linkedNDCs: [trimmedBarcode],
            strength: 1,
            strengthUnit: .unitless
        )
        let component = CompoundComponent(
            product: product,
            totalQuantity: 0,
            quantityUnit: .unitless,
            utilizedLots: [lot],
            isUnexpected: true,
            unexpectedBarcodeValue: trimmedBarcode
        )

        order.components.append(component)
        let shouldSetStaging = order.status == .pending
        if shouldSetStaging { order.status = .staging }
        writeToSupabase { writer in
            try await writer.insertUnexpectedComponent(orderID: orderID, component: component, lot: lot)
            if shouldSetStaging {
                try await writer.updateOrderStatus(orderID: orderID, status: .staging)
            }
        }
    }

    func removeUnexpectedComponent(
        orderID: CSPOrder.ID,
        componentID: CompoundComponent.ID,
        removedBy user: User
    ) {
        guard let order = order(for: orderID), mutationsAllowed(on: order, by: user) else { return }
        guard let index = order.components.firstIndex(where: { $0.id == componentID }) else { return }
        guard order.components[index].isUnexpected else { return }
        order.components.remove(at: index)
        writeToSupabase { writer in
            try await writer.deleteComponent(componentID: componentID)
        }
    }

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
              mutationsAllowed(on: order, by: scannedBy),
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

        let shouldSetStaging = order.status == .pending
        if shouldSetStaging { order.status = .staging }
        if let auditEvent = order.auditEvents.last {
            writeToSupabase { writer in
                try await writer.insertLot(componentID: componentID, lot: lot)
                try await writer.insertAuditEvent(orderID: orderID, event: auditEvent)
                if shouldSetStaging {
                    try await writer.updateOrderStatus(orderID: orderID, status: .staging)
                }
            }
        }
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
              mutationsAllowed(on: order, by: enteredBy),
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

        let shouldSetStaging = order.status == .pending
        if shouldSetStaging { order.status = .staging }
        if let auditEvent = order.auditEvents.last {
            writeToSupabase { writer in
                try await writer.insertLot(componentID: componentID, lot: utilizedLot)
                try await writer.insertAuditEvent(orderID: orderID, event: auditEvent)
                if shouldSetStaging {
                    try await writer.updateOrderStatus(orderID: orderID, status: .staging)
                }
            }
        }
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
              mutationsAllowed(on: order, by: correctedBy),
              let componentIndex = order.components.firstIndex(where: { $0.id == componentID }),
              let lotIndex = order.components[componentIndex].utilizedLots.firstIndex(where: { $0.id == lotID })
        else { return }

        let lot = order.components[componentIndex].utilizedLots[lotIndex]
        var previousValue = ""
        var correctedExpiration: Date?

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
                    correctedExpiration = date
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

        if let auditEvent = order.auditEvents.last {
            writeToSupabase { writer in
                switch field {
                case "barcode":
                    try await writer.updateLotBarcode(lotID: lotID, barcodeValue: newValue)
                case "lot":
                    try await writer.updateLotNumber(lotID: lotID, lot: newValue)
                case "expiration":
                    if let correctedExpiration {
                        try await writer.updateLotExpiration(lotID: lotID, expiration: correctedExpiration)
                    }
                default:
                    break
                }
                try await writer.insertScanOverride(override)
                try await writer.insertAuditEvent(orderID: orderID, event: auditEvent)
            }
        }
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

        if let auditEvent = order.auditEvents.last {
            writeToSupabase { writer in
                try await writer.cosignScanOverride(override)
                try await writer.insertAuditEvent(orderID: orderID, event: auditEvent)
            }
        }
    }

    func removeLot(
        orderID: CSPOrder.ID,
        componentID: CompoundComponent.ID,
        lotID: CompoundUtilizedLot.ID,
        removedBy user: User
    ) {
        guard let order = order(for: orderID),
              mutationsAllowed(on: order, by: user),
              let componentIndex = order.components.firstIndex(where: { $0.id == componentID })
        else { return }

        order.components[componentIndex].utilizedLots.removeAll { $0.id == lotID }
        writeToSupabase { writer in
            try await writer.deleteLot(lotID: lotID)
        }
    }

    // MARK: - Captures

    func addCapture(
        orderID: CSPOrder.ID,
        kind: CaptureKind,
        imageURL: URL?,
        capturedBy: User
    ) {
        guard capturedBy.role.canRemediate else { return }
        guard let order = order(for: orderID), mutationsAllowed(on: order, by: capturedBy) else { return }

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

        let shouldSetStaging = order.status == .pending
        if shouldSetStaging { order.status = .staging }
        if let auditEvent = order.auditEvents.last {
            writeToSupabase { writer in
                try await writer.insertCapture(orderID: orderID, capture: capture)
                try await writer.insertAuditEvent(orderID: orderID, event: auditEvent)
                if shouldSetStaging {
                    try await writer.updateOrderStatus(orderID: orderID, status: .staging)
                }
            }
        }

        scheduleAnalysis(for: capture.id, orderID: orderID, imageURL: imageURL)
    }

    private func scheduleAnalysis(for captureID: CompoundCapture.ID, orderID: CSPOrder.ID, imageURL: URL?) {
        guard let imageURL else { return }
        Task { [weak self] in
            let analysis = await ImageAnalyzer.shared.analyze(url: imageURL)
            guard !Task.isCancelled else { return }
            self?.storeAnalysis(analysis, orderID: orderID, captureID: captureID)
        }
    }

    func storeAnalysis(_ analysis: CaptureAnalysis, orderID: CSPOrder.ID, captureID: CompoundCapture.ID) {
        guard let order = order(for: orderID),
              let captureIndex = order.captures.firstIndex(where: { $0.id == captureID }),
              order.captures[captureIndex].analysis == nil
        else { return }

        order.captures[captureIndex].analysis = analysis
        order.captures[captureIndex].analyzedAt = .now
        try? modelContext.save()
    }

    @discardableResult
    func deleteCapture(orderID: CSPOrder.ID, captureID: CompoundCapture.ID, deletedBy user: User) -> Bool {
        guard let order = order(for: orderID) else { return false }
        guard order.captureMutationsAllowed, mutationsAllowed(on: order, by: user) else { return false }

        order.captures.removeAll { $0.id == captureID }

        if let rem = order.remediation {
            rem.flags.removeAll { $0.captureID == captureID }
            order.remediation = rem
        }
        writeToSupabase { writer in
            try await writer.deleteCapture(captureID: captureID)
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
              mutationsAllowed(on: order, by: createdBy),
              let captureIndex = order.captures.firstIndex(where: { $0.id == captureID })
        else { return }

        let flag = CaptureFlag(captureID: captureID, x: x, y: y, createdBy: createdBy, note: note)
        order.captures[captureIndex].preparerFlags.append(flag)
        writeToSupabase { writer in
            try await writer.insertCaptureFlag(captureID: captureID, flag: flag)
        }
    }

    func removePreparerFlag(
        orderID: CSPOrder.ID,
        captureID: CompoundCapture.ID,
        flagID: CaptureFlag.ID,
        removedBy user: User
    ) {
        guard let order = order(for: orderID),
              mutationsAllowed(on: order, by: user),
              let captureIndex = order.captures.firstIndex(where: { $0.id == captureID })
        else { return }

        order.captures[captureIndex].preparerFlags.removeAll { $0.id == flagID }
        writeToSupabase { writer in
            try await writer.deleteCaptureFlag(flagID: flagID)
        }
    }

    func setCurrentStep(orderID: CSPOrder.ID, stepIndex: Int, changedBy user: User) {
        guard let order = order(for: orderID), mutationsAllowed(on: order, by: user) else { return }
        let total = order.recipeSteps.count
        guard total > 0 else { return }
        order.currentStepIndex = min(max(stepIndex, 0), total - 1)
        let persistedStepIndex = order.currentStepIndex
        writeToSupabase { writer in
            try await writer.updateOrderStep(orderID: orderID, stepIndex: persistedStepIndex)
        }
    }

    func advanceStep(orderID: CSPOrder.ID, changedBy user: User) {
        guard let order = order(for: orderID), mutationsAllowed(on: order, by: user) else { return }
        let total = order.recipeSteps.count
        guard total > 0 else { return }
        order.currentStepIndex = min(order.currentStepIndex + 1, total - 1)
        let persistedStepIndex = order.currentStepIndex
        writeToSupabase { writer in
            try await writer.updateOrderStep(orderID: orderID, stepIndex: persistedStepIndex)
        }
    }

    func previousStep(orderID: CSPOrder.ID, changedBy user: User) {
        guard let order = order(for: orderID), mutationsAllowed(on: order, by: user) else { return }
        order.currentStepIndex = max(order.currentStepIndex - 1, 0)
        let persistedStepIndex = order.currentStepIndex
        writeToSupabase { writer in
            try await writer.updateOrderStep(orderID: orderID, stepIndex: persistedStepIndex)
        }
    }

    func beginPreparing(orderID: CSPOrder.ID, by user: User) {
        guard let order = order(for: orderID), mutationsAllowed(on: order, by: user) else { return }
        guard [.pending, .staging].contains(order.status) else { return }
        order.status = .preparing
        writeToSupabase { writer in
            try await writer.updateOrderStatus(orderID: orderID, status: .preparing)
        }
    }

    // MARK: - Verification

    func markReadyForVerification(orderID: CSPOrder.ID, by user: User) {
        guard let order = order(for: orderID), mutationsAllowed(on: order, by: user) else { return }
        order.status = .waitingForApproval
        releaseOrderLock(orderID: orderID, by: user)
        writeToSupabase { writer in
            try await writer.updateOrderStatus(orderID: orderID, status: .waitingForApproval)
        }
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
        let verificationRecord = VerificationRecord(
            verifiedBy: verifiedBy,
            decision: decision,
            rejectionReason: rejectionReason
        )
        order.verificationRecord = verificationRecord
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

        if let auditEvent = order.auditEvents.last {
            writeToSupabase { writer in
                try await writer.insertVerification(orderID: orderID, record: verificationRecord)
                try await writer.insertAuditEvent(orderID: orderID, event: auditEvent)
                if approved {
                    try await writer.updateOrderStatus(orderID: orderID, status: .approved)
                }
            }
        }

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

        if let auditEvent = order.auditEvents.last {
            writeToSupabase { writer in
                try await writer.insertRemediationRequest(orderID: orderID, remediation: remediation)
                try await writer.insertAuditEvent(orderID: orderID, event: auditEvent)
                try await writer.updateOrderStatus(orderID: orderID, status: .remediation)
            }
        }
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

        if let auditEvent = order.auditEvents.last {
            writeToSupabase { writer in
                try await writer.insertRemediationCapture(capture)
                try await writer.insertAuditEvent(orderID: orderID, event: auditEvent)
            }
        }
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
              mutationsAllowed(on: order, by: madeBy),
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
        writeToSupabase { writer in
            try await writer.insertRemediationLotChange(change)
        }
    }

    func completeRemediation(orderID: CSPOrder.ID, completedBy: User) {
        guard completedBy.role.canRemediate else { return }
        guard let order = order(for: orderID),
              mutationsAllowed(on: order, by: completedBy),
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

        if let auditEvent = order.auditEvents.last {
            writeToSupabase { writer in
                try await writer.completeRemediation(remediation)
                try await writer.insertAuditEvent(orderID: orderID, event: auditEvent)
                try await writer.updateOrderStatus(orderID: orderID, status: .waitingForApproval)
            }
        }
    }

    func resubmitAfterRemediation(orderID: CSPOrder.ID) {
        guard let order = order(for: orderID) else { return }
        order.status = .waitingForApproval
        writeToSupabase { writer in
            try await writer.updateOrderStatus(orderID: orderID, status: .waitingForApproval)
        }
    }
}

// MARK: - Helper

private func parseDate(_ string: String) -> Date? {
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    return formatter.date(from: string)
}
