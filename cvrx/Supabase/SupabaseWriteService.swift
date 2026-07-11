import Foundation

struct SupabaseWriteService: Sendable {
    let authService: SupabaseAuthService

    func acquireOrderLock(orderID: UUID, breakingExisting: Bool) async throws -> Bool {
        let authenticated = try await authService.makeAuthenticatedClient()
        let response: BoolRPCResponse = try await authenticated.client.restRequest(
            path: "rpc/acquire_order_lock",
            method: .post,
            body: AcquireLockRequest(targetOrderID: orderID, breakingExisting: breakingExisting),
            responseType: BoolRPCResponse.self
        )
        return response.value
    }

    func refreshOrderLock(orderID: UUID) async throws {
        let authenticated = try await authService.makeAuthenticatedClient()
        let _: EmptyResponse = try await authenticated.client.restRequest(
            path: "rpc/refresh_order_lock",
            method: .post,
            body: OrderIDRequest(targetOrderID: orderID),
            responseType: EmptyResponse.self
        )
    }

    func releaseOrderLock(orderID: UUID) async throws {
        let authenticated = try await authService.makeAuthenticatedClient()
        let _: EmptyResponse = try await authenticated.client.restRequest(
            path: "rpc/release_order_lock",
            method: .post,
            body: OrderIDRequest(targetOrderID: orderID),
            responseType: EmptyResponse.self
        )
    }

    func updateOrderStatus(orderID: UUID, status: OrderStatus) async throws {
        try await updateOrder(orderID: orderID, body: OrderStatusPatch(status: status.rawValue))
    }

    func updateOrderStep(orderID: UUID, stepIndex: Int) async throws {
        try await updateOrder(orderID: orderID, body: OrderStepPatch(currentStepIndex: stepIndex))
    }

    func insertGeneratedOrder(_ order: CSPOrder) async throws {
        let authenticated = try await authService.makeAuthenticatedClient()
        let patientPayload = PatientPayload(patient: order.patient, facilityID: authenticated.facilityID)
        let orderPayload = OrderPayload(order: order, facilityID: authenticated.facilityID)

        let _: EmptyResponse = try await authenticated.client.restRequest(
            path: "patients",
            method: .post,
            body: patientPayload,
            responseType: EmptyResponse.self
        )

        for component in order.components {
            try await upsertProduct(component.product)
        }

        let _: EmptyResponse = try await authenticated.client.restRequest(
            path: "orders",
            method: .post,
            body: orderPayload,
            responseType: EmptyResponse.self
        )

        for component in order.components {
            try await insertComponent(orderID: order.id, component: component)
        }
    }

    func upsertProduct(_ product: Product) async throws {
        let authenticated = try await authService.makeAuthenticatedClient()
        let payload = ProductPayload(product: product, facilityID: authenticated.facilityID)
        let _: EmptyResponse = try await authenticated.client.restRequest(
            path: "rxcui_concepts?on_conflict=id",
            method: .post,
            body: payload,
            responseType: EmptyResponse.self
        )

        for ndc in product.linkedNDCs {
            try await upsertNDCProduct(ndc: ndc, conceptID: product.id, facilityID: authenticated.facilityID)
        }
    }

    private func upsertNDCProduct(ndc: String, conceptID: UUID, facilityID: UUID) async throws {
        let authenticated = try await authService.makeAuthenticatedClient()
        let normalizedNDC = ndc.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedNDC.isEmpty else { return }

        let _: EmptyResponse = try await authenticated.client.restRequest(
            path: "ndc_products?on_conflict=facility_id,ndc",
            method: .post,
            body: NDCProductPayload(ndc: normalizedNDC, facilityID: facilityID),
            responseType: EmptyResponse.self
        )

        let _: EmptyResponse = try await authenticated.client.restRequest(
            path: "rxcui_concept_ndc_products?on_conflict=facility_id,concept_id,ndc",
            method: .post,
            body: ConceptNDCProductPayload(conceptID: conceptID, ndc: normalizedNDC, facilityID: facilityID),
            responseType: EmptyResponse.self
        )
    }

    func insertUnexpectedComponent(orderID: UUID, component: CompoundComponent, lot: CompoundUtilizedLot) async throws {
        try await upsertProduct(component.product)
        try await insertComponent(orderID: orderID, component: component)
        try await insertLot(componentID: component.id, lot: lot)
    }

    func deleteComponent(componentID: UUID) async throws {
        let authenticated = try await authService.makeAuthenticatedClient()
        let _: EmptyResponse = try await authenticated.client.restRequest(
            path: "ordered_components?id=eq.\(componentID.uuidString)",
            method: .delete,
            responseType: EmptyResponse.self
        )
    }

    func insertComponent(orderID: UUID, component: CompoundComponent) async throws {
        let authenticated = try await authService.makeAuthenticatedClient()
        let payload = ComponentPayload(orderID: orderID, component: component, facilityID: authenticated.facilityID)
        let _: EmptyResponse = try await authenticated.client.restRequest(
            path: "ordered_components",
            method: .post,
            body: payload,
            responseType: EmptyResponse.self
        )
    }

    func insertLot(componentID: UUID, lot: CompoundUtilizedLot) async throws {
        let authenticated = try await authService.makeAuthenticatedClient()
        let payload = LotPayload(componentID: componentID, lot: lot, facilityID: authenticated.facilityID)
        let _: EmptyResponse = try await authenticated.client.restRequest(
            path: "utilized_lots",
            method: .post,
            body: payload,
            responseType: EmptyResponse.self
        )
    }

    func deleteLot(lotID: UUID) async throws {
        let authenticated = try await authService.makeAuthenticatedClient()
        let _: EmptyResponse = try await authenticated.client.restRequest(
            path: "utilized_lots?id=eq.\(lotID.uuidString)",
            method: .delete,
            responseType: EmptyResponse.self
        )
    }

    func insertScanOverride(_ scanOverride: ScanOverride) async throws {
        let authenticated = try await authService.makeAuthenticatedClient()
        let payload = ScanOverridePayload(scanOverride: scanOverride, facilityID: authenticated.facilityID)
        let _: EmptyResponse = try await authenticated.client.restRequest(
            path: "scan_overrides",
            method: .post,
            body: payload,
            responseType: EmptyResponse.self
        )
    }

    func updateLotBarcode(lotID: UUID, barcodeValue: String) async throws {
        try await updateLot(lotID: lotID, body: LotBarcodePatch(barcodeValue: barcodeValue))
    }

    func updateLotNumber(lotID: UUID, lot: String) async throws {
        try await updateLot(lotID: lotID, body: LotNumberPatch(lot: lot))
    }

    func updateLotExpiration(lotID: UUID, expiration: Date) async throws {
        try await updateLot(lotID: lotID, body: LotExpirationPatch(expiration: expiration))
    }

    func cosignScanOverride(_ scanOverride: ScanOverride) async throws {
        let authenticated = try await authService.makeAuthenticatedClient()
        let payload = ScanOverrideCosignPatch(cosignedBy: scanOverride.cosignedBy?.id, cosignedAt: scanOverride.cosignedAt)
        let _: EmptyResponse = try await authenticated.client.restRequest(
            path: "scan_overrides?id=eq.\(scanOverride.id.uuidString)",
            method: .patch,
            body: payload,
            responseType: EmptyResponse.self
        )
    }

    func insertCapture(orderID: UUID, capture: CompoundCapture) async throws {
        let authenticated = try await authService.makeAuthenticatedClient()
        let payload = CapturePayload(orderID: orderID, capture: capture, facilityID: authenticated.facilityID)
        let _: EmptyResponse = try await authenticated.client.restRequest(
            path: "compound_captures",
            method: .post,
            body: payload,
            responseType: EmptyResponse.self
        )
    }

    func deleteCapture(captureID: UUID) async throws {
        let authenticated = try await authService.makeAuthenticatedClient()
        let _: EmptyResponse = try await authenticated.client.restRequest(
            path: "compound_captures?id=eq.\(captureID.uuidString)",
            method: .delete,
            responseType: EmptyResponse.self
        )
    }

    func insertCaptureFlag(captureID: UUID, flag: CaptureFlag, remediationRequestID: UUID? = nil) async throws {
        let authenticated = try await authService.makeAuthenticatedClient()
        let payload = CaptureFlagPayload(captureID: captureID, flag: flag, facilityID: authenticated.facilityID, remediationRequestID: remediationRequestID)
        let _: EmptyResponse = try await authenticated.client.restRequest(
            path: "capture_flags",
            method: .post,
            body: payload,
            responseType: EmptyResponse.self
        )
    }

    func deleteCaptureFlag(flagID: UUID) async throws {
        let authenticated = try await authService.makeAuthenticatedClient()
        let _: EmptyResponse = try await authenticated.client.restRequest(
            path: "capture_flags?id=eq.\(flagID.uuidString)",
            method: .delete,
            responseType: EmptyResponse.self
        )
    }

    func insertVerification(orderID: UUID, record: VerificationRecord) async throws {
        let authenticated = try await authService.makeAuthenticatedClient()
        let payload = VerificationPayload(orderID: orderID, record: record, facilityID: authenticated.facilityID)
        let _: EmptyResponse = try await authenticated.client.restRequest(
            path: "verification_records",
            method: .post,
            body: payload,
            responseType: EmptyResponse.self
        )
    }

    func insertRemediationRequest(orderID: UUID, remediation: RemediationRequest) async throws {
        let authenticated = try await authService.makeAuthenticatedClient()
        let payload = RemediationRequestPayload(orderID: orderID, remediation: remediation, facilityID: authenticated.facilityID)
        let _: EmptyResponse = try await authenticated.client.restRequest(
            path: "remediation_requests",
            method: .post,
            body: payload,
            responseType: EmptyResponse.self
        )
    }

    func insertRemediationCapture(_ capture: RemediationCapture) async throws {
        let authenticated = try await authService.makeAuthenticatedClient()
        let payload = RemediationCapturePayload(capture: capture, facilityID: authenticated.facilityID)
        let _: EmptyResponse = try await authenticated.client.restRequest(
            path: "remediation_captures",
            method: .post,
            body: payload,
            responseType: EmptyResponse.self
        )
    }

    func insertRemediationLotChange(_ change: RemediationLotChange) async throws {
        let authenticated = try await authService.makeAuthenticatedClient()
        let payload = RemediationLotChangePayload(change: change, facilityID: authenticated.facilityID)
        let _: EmptyResponse = try await authenticated.client.restRequest(
            path: "remediation_lot_changes",
            method: .post,
            body: payload,
            responseType: EmptyResponse.self
        )
    }

    func completeRemediation(_ remediation: RemediationRequest) async throws {
        let authenticated = try await authService.makeAuthenticatedClient()
        let payload = RemediationCompletePatch(completedBy: remediation.completedBy?.id, completedAt: remediation.completedAt)
        let _: EmptyResponse = try await authenticated.client.restRequest(
            path: "remediation_requests?id=eq.\(remediation.id.uuidString)",
            method: .patch,
            body: payload,
            responseType: EmptyResponse.self
        )
    }

    func insertAuditEvent(orderID: UUID, event: AuditEvent) async throws {
        let authenticated = try await authService.makeAuthenticatedClient()
        let payload = AuditEventPayload(orderID: orderID, event: event, facilityID: authenticated.facilityID)
        let _: EmptyResponse = try await authenticated.client.restRequest(
            path: "audit_events",
            method: .post,
            body: payload,
            responseType: EmptyResponse.self
        )
    }

    private func updateOrder<Body: Encodable>(orderID: UUID, body: Body) async throws {
        let authenticated = try await authService.makeAuthenticatedClient()
        let _: EmptyResponse = try await authenticated.client.restRequest(
            path: "orders?id=eq.\(orderID.uuidString)",
            method: .patch,
            body: body,
            responseType: EmptyResponse.self
        )
    }

    private func updateLot<Body: Encodable>(lotID: UUID, body: Body) async throws {
        let authenticated = try await authService.makeAuthenticatedClient()
        let _: EmptyResponse = try await authenticated.client.restRequest(
            path: "utilized_lots?id=eq.\(lotID.uuidString)",
            method: .patch,
            body: body,
            responseType: EmptyResponse.self
        )
    }
}

private struct BoolRPCResponse: Decodable {
    let value: Bool

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        value = try container.decode(Bool.self)
    }
}

private struct AcquireLockRequest: Encodable {
    let targetOrderID: UUID
    let breakingExisting: Bool

    enum CodingKeys: String, CodingKey {
        case targetOrderID = "target_order_id"
        case breakingExisting = "breaking_existing"
    }
}

private struct OrderIDRequest: Encodable {
    let targetOrderID: UUID

    enum CodingKeys: String, CodingKey {
        case targetOrderID = "target_order_id"
    }
}

private struct OrderStatusPatch: Encodable {
    let status: String
}

private struct OrderStepPatch: Encodable {
    let currentStepIndex: Int

    enum CodingKeys: String, CodingKey {
        case currentStepIndex = "current_step_index"
    }
}

private struct PatientPayload: Encodable {
    let id: UUID
    let facilityID: UUID
    let name: String
    let floor: String
    let room: String
    let bed: String?
    let dob: Date?

    init(patient: Patient, facilityID: UUID) {
        id = patient.id
        self.facilityID = facilityID
        name = patient.name
        floor = patient.floor
        room = patient.room
        bed = patient.bed
        dob = patient.dob
    }

    enum CodingKeys: String, CodingKey {
        case id
        case facilityID = "facility_id"
        case name
        case floor
        case room
        case bed
        case dob
    }
}

private struct OrderPayload: Encodable {
    let id: UUID
    let facilityID: UUID
    let orderNumber: String
    let patientID: UUID
    let medicationName: String
    let finalContainer: String
    let route: String
    let dueTime: Date
    let recipeText: String
    let status: String
    let currentStepIndex: Int
    let activeEditorID: UUID?
    let activeEditorUsername: String?
    let activeEditorName: String?
    let activeEditorLastSeenAt: Date?

    init(order: CSPOrder, facilityID: UUID) {
        id = order.id
        self.facilityID = facilityID
        orderNumber = order.orderNumber
        patientID = order.patient.id
        medicationName = order.medicationName
        finalContainer = order.finalContainer
        route = order.route
        dueTime = order.dueTime
        recipeText = order.recipeText
        status = order.status.rawValue
        currentStepIndex = order.currentStepIndex
        activeEditorID = order.activeEditorID
        activeEditorUsername = order.activeEditorUsername
        activeEditorName = order.activeEditorName
        activeEditorLastSeenAt = order.activeEditorLastSeenAt
    }

    enum CodingKeys: String, CodingKey {
        case id
        case facilityID = "facility_id"
        case orderNumber = "order_number"
        case patientID = "patient_id"
        case medicationName = "medication_name"
        case finalContainer = "final_container"
        case route
        case dueTime = "due_time"
        case recipeText = "recipe_text"
        case status
        case currentStepIndex = "current_step_index"
        case activeEditorID = "active_editor_id"
        case activeEditorUsername = "active_editor_username"
        case activeEditorName = "active_editor_name"
        case activeEditorLastSeenAt = "active_editor_last_seen_at"
    }
}

private struct ProductPayload: Encodable {
    let id: UUID
    let facilityID: UUID
    let name: String
    let rxCUI: String?
    let tty: String?
    let importedAt: Date?
    let strength: Double
    let strengthUnit: QuantityUnit
    let mlConcentration: Double?

    init(product: Product, facilityID: UUID) {
        id = product.id
        self.facilityID = facilityID
        name = product.name
        rxCUI = product.importedRxCUI
        tty = product.importedTTY
        importedAt = product.importedAt
        strength = product.strength
        strengthUnit = product.strengthUnit
        mlConcentration = product.mlConcentration
    }

    enum CodingKeys: String, CodingKey {
        case id
        case facilityID = "facility_id"
        case name
        case rxCUI = "rxcui"
        case tty
        case importedAt = "imported_at"
        case strength
        case strengthUnit = "strength_unit"
        case mlConcentration = "ml_concentration"
    }
}

private struct NDCProductPayload: Encodable {
    let ndc: String
    let facilityID: UUID

    enum CodingKeys: String, CodingKey {
        case ndc
        case facilityID = "facility_id"
    }
}

private struct ConceptNDCProductPayload: Encodable {
    let conceptID: UUID
    let ndc: String
    let facilityID: UUID

    enum CodingKeys: String, CodingKey {
        case conceptID = "concept_id"
        case ndc
        case facilityID = "facility_id"
    }
}

private struct ComponentPayload: Encodable {
    let id: UUID
    let facilityID: UUID
    let orderID: UUID
    let conceptID: UUID
    let totalQuantity: Double
    let quantityUnit: QuantityUnit
    let isUnexpected: Bool
    let unexpectedBarcodeValue: String?

    init(orderID: UUID, component: CompoundComponent, facilityID: UUID) {
        id = component.id
        self.facilityID = facilityID
        self.orderID = orderID
        conceptID = component.product.id
        totalQuantity = component.totalQuantity
        quantityUnit = component.quantityUnit
        isUnexpected = component.isUnexpected
        unexpectedBarcodeValue = component.unexpectedBarcodeValue
    }

    enum CodingKeys: String, CodingKey {
        case id
        case facilityID = "facility_id"
        case orderID = "order_id"
        case conceptID = "concept_id"
        case totalQuantity = "total_quantity"
        case quantityUnit = "quantity_unit"
        case isUnexpected = "is_unexpected"
        case unexpectedBarcodeValue = "unexpected_barcode_value"
    }
}

private struct LotPayload: Encodable {
    let id: UUID
    let facilityID: UUID
    let componentID: UUID
    let barcodeValue: String?
    let lot: String
    let expiration: Date?
    let mfg: String?
    let strengthQuantity: Double
    let photoBucketID: UUID?
    let scannedBy: UUID?
    let scannedAt: Date

    init(componentID: UUID, lot: CompoundUtilizedLot, facilityID: UUID) {
        id = lot.id
        self.facilityID = facilityID
        self.componentID = componentID
        barcodeValue = lot.barcodeValue
        self.lot = lot.lot
        expiration = lot.expiration
        mfg = lot.mfg
        strengthQuantity = lot.strengthQuantity
        photoBucketID = lot.photoBucketID
        scannedBy = lot.scannedBy?.id
        scannedAt = lot.scannedAt
    }

    enum CodingKeys: String, CodingKey {
        case id
        case facilityID = "facility_id"
        case componentID = "component_id"
        case barcodeValue = "barcode_value"
        case lot
        case expiration
        case mfg
        case strengthQuantity = "strength_quantity"
        case photoBucketID = "photo_bucket_id"
        case scannedBy = "scanned_by"
        case scannedAt = "scanned_at"
    }
}

private struct LotBarcodePatch: Encodable {
    let barcodeValue: String

    enum CodingKeys: String, CodingKey {
        case barcodeValue = "barcode_value"
    }
}

private struct LotNumberPatch: Encodable {
    let lot: String
}

private struct LotExpirationPatch: Encodable {
    let expiration: Date
}

private struct ScanOverridePayload: Encodable {
    let id: UUID
    let facilityID: UUID
    let lotID: UUID
    let field: String
    let previousValue: String
    let newValue: String
    let overriddenBy: UUID
    let overriddenAt: Date

    init(scanOverride: ScanOverride, facilityID: UUID) {
        id = scanOverride.id
        self.facilityID = facilityID
        lotID = scanOverride.lotID
        field = scanOverride.field
        previousValue = scanOverride.previousValue
        newValue = scanOverride.newValue
        overriddenBy = scanOverride.overriddenBy.id
        overriddenAt = scanOverride.overriddenAt
    }

    enum CodingKeys: String, CodingKey {
        case id
        case facilityID = "facility_id"
        case lotID = "lot_id"
        case field
        case previousValue = "previous_value"
        case newValue = "new_value"
        case overriddenBy = "overridden_by"
        case overriddenAt = "overridden_at"
    }
}

private struct ScanOverrideCosignPatch: Encodable {
    let cosignedBy: UUID?
    let cosignedAt: Date?

    enum CodingKeys: String, CodingKey {
        case cosignedBy = "cosigned_by"
        case cosignedAt = "cosigned_at"
    }
}

private struct CapturePayload: Encodable {
    let id: UUID
    let facilityID: UUID
    let orderID: UUID
    let kind: CaptureKind
    let capturedBy: UUID?
    let capturedAt: Date
    let imageURL: String?
    let imageName: String?
    let note: String?

    init(orderID: UUID, capture: CompoundCapture, facilityID: UUID) {
        id = capture.id
        self.facilityID = facilityID
        self.orderID = orderID
        kind = capture.kind
        capturedBy = capture.capturedBy?.id
        capturedAt = capture.timestamp
        imageURL = capture.imageURL?.absoluteString
        imageName = capture.imageName
        note = capture.note
    }

    enum CodingKeys: String, CodingKey {
        case id
        case facilityID = "facility_id"
        case orderID = "order_id"
        case kind
        case capturedBy = "captured_by"
        case capturedAt = "captured_at"
        case imageURL = "image_url"
        case imageName = "image_name"
        case note
    }
}

private struct CaptureFlagPayload: Encodable {
    let id: UUID
    let facilityID: UUID
    let captureID: UUID
    let remediationRequestID: UUID?
    let x: Double
    let y: Double
    let createdBy: UUID
    let note: String?

    init(captureID: UUID, flag: CaptureFlag, facilityID: UUID, remediationRequestID: UUID?) {
        id = flag.id
        self.facilityID = facilityID
        self.captureID = captureID
        self.remediationRequestID = remediationRequestID
        x = flag.x
        y = flag.y
        createdBy = flag.createdBy.id
        note = flag.note
    }

    enum CodingKeys: String, CodingKey {
        case id
        case facilityID = "facility_id"
        case captureID = "capture_id"
        case remediationRequestID = "remediation_request_id"
        case x
        case y
        case createdBy = "created_by"
        case note
    }
}

private struct VerificationPayload: Encodable {
    let id: UUID
    let facilityID: UUID
    let orderID: UUID
    let verifiedBy: UUID
    let verifiedAt: Date
    let decision: VerificationDecision
    let rejectionReason: String?

    init(orderID: UUID, record: VerificationRecord, facilityID: UUID) {
        id = record.id
        self.facilityID = facilityID
        self.orderID = orderID
        verifiedBy = record.verifiedBy.id
        verifiedAt = record.verifiedAt
        decision = record.decision
        rejectionReason = record.rejectionReason
    }

    enum CodingKeys: String, CodingKey {
        case id
        case facilityID = "facility_id"
        case orderID = "order_id"
        case verifiedBy = "verified_by"
        case verifiedAt = "verified_at"
        case decision
        case rejectionReason = "rejection_reason"
    }
}

private struct RemediationRequestPayload: Encodable {
    let id: UUID
    let facilityID: UUID
    let orderID: UUID
    let requestedBy: UUID
    let requestedAt: Date
    let reason: String
    let completedBy: UUID?
    let completedAt: Date?

    init(orderID: UUID, remediation: RemediationRequest, facilityID: UUID) {
        id = remediation.id
        self.facilityID = facilityID
        self.orderID = orderID
        requestedBy = remediation.requestedBy.id
        requestedAt = remediation.requestedAt
        reason = remediation.reason
        completedBy = remediation.completedBy?.id
        completedAt = remediation.completedAt
    }

    enum CodingKeys: String, CodingKey {
        case id
        case facilityID = "facility_id"
        case orderID = "order_id"
        case requestedBy = "requested_by"
        case requestedAt = "requested_at"
        case reason
        case completedBy = "completed_by"
        case completedAt = "completed_at"
    }
}

private struct RemediationCapturePayload: Encodable {
    let id: UUID
    let facilityID: UUID
    let remediationRequestID: UUID
    let capturedBy: UUID
    let capturedAt: Date
    let imageURL: String?
    let imageName: String?
    let note: String?

    init(capture: RemediationCapture, facilityID: UUID) {
        id = capture.id
        self.facilityID = facilityID
        remediationRequestID = capture.remediationRequestID
        capturedBy = capture.capturedBy.id
        capturedAt = capture.capturedAt
        imageURL = capture.imageURL?.absoluteString
        imageName = capture.imageName
        note = capture.note
    }

    enum CodingKeys: String, CodingKey {
        case id
        case facilityID = "facility_id"
        case remediationRequestID = "remediation_request_id"
        case capturedBy = "captured_by"
        case capturedAt = "captured_at"
        case imageURL = "image_url"
        case imageName = "image_name"
        case note
    }
}

private struct RemediationLotChangePayload: Encodable {
    let id: UUID
    let facilityID: UUID
    let remediationRequestID: UUID
    let componentID: UUID
    let lotID: UUID
    let changeType: String
    let madeBy: UUID
    let madeAt: Date
    let descr: String?

    init(change: RemediationLotChange, facilityID: UUID) {
        id = change.id
        self.facilityID = facilityID
        remediationRequestID = change.remediationRequestID
        componentID = change.componentID
        lotID = change.lotID
        changeType = change.changeType
        madeBy = change.madeBy.id
        madeAt = change.madeAt
        descr = change.descr
    }

    enum CodingKeys: String, CodingKey {
        case id
        case facilityID = "facility_id"
        case remediationRequestID = "remediation_request_id"
        case componentID = "component_id"
        case lotID = "lot_id"
        case changeType = "change_type"
        case madeBy = "made_by"
        case madeAt = "made_at"
        case descr
    }
}

private struct RemediationCompletePatch: Encodable {
    let completedBy: UUID?
    let completedAt: Date?

    enum CodingKeys: String, CodingKey {
        case completedBy = "completed_by"
        case completedAt = "completed_at"
    }
}

private struct AuditEventPayload: Encodable {
    let id: UUID
    let facilityID: UUID
    let orderID: UUID
    let actorID: UUID
    let occurredAt: Date
    let actionData: JSONValue
    let context: String?

    init(orderID: UUID, event: AuditEvent, facilityID: UUID) {
        id = event.id
        self.facilityID = facilityID
        self.orderID = orderID
        actorID = event.actor.id
        occurredAt = event.timestamp
        actionData = (try? JSONDecoder.supabase.decode(JSONValue.self, from: event.actionData)) ?? .object([:])
        context = event.context
    }

    enum CodingKeys: String, CodingKey {
        case id
        case facilityID = "facility_id"
        case orderID = "order_id"
        case actorID = "actor_id"
        case occurredAt = "occurred_at"
        case actionData = "action_data"
        case context
    }
}

enum JSONValue: Codable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: JSONValue].self))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }
}
