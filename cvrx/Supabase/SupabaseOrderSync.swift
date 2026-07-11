import Foundation
import SwiftData

struct SupabaseOrderSyncService: Sendable {
    let authService: SupabaseAuthService

    func fetchOrders() async throws -> [RemoteOrder] {
        let authenticated = try await authService.makeAuthenticatedClient()
        let select = "id,order_number,medication_name,final_container,route,due_time,recipe_text,status,current_step_index,active_editor_id,active_editor_username,active_editor_name,active_editor_last_seen_at,patients(id,name,floor,room,bed,dob),ordered_components(id,total_quantity,quantity_unit,is_unexpected,unexpected_barcode_value,rxcui_concepts(id,name,rxcui,tty,imported_at,strength,strength_unit,ml_concentration,rxcui_concept_ndc_products(ndc)),utilized_lots(id,barcode_value,lot,expiration,mfg,strength_quantity,photo_bucket_id,scanned_by,scanned_at)),compound_captures(id,kind,captured_by,captured_at,image_url,image_name,note,capture_flags(id,x,y,created_by,note)),verification_records(id,verified_by,verified_at,decision,rejection_reason)"
        let path = "orders?select=\(select)&facility_id=eq.\(authenticated.facilityID.uuidString)&order=due_time.asc"
        return try await authenticated.client.restRequest(path: path, responseType: [RemoteOrder].self)
    }
}

struct RemoteOrder: Decodable, Sendable {
    let id: UUID
    let orderNumber: String
    let medicationName: String
    let finalContainer: String
    let route: String
    let dueTime: Date
    let recipeText: String
    let status: OrderStatus
    let currentStepIndex: Int
    let activeEditorID: UUID?
    let activeEditorUsername: String?
    let activeEditorName: String?
    let activeEditorLastSeenAt: Date?
    let patient: RemotePatient
    let components: [RemoteComponent]
    let captures: [RemoteCapture]
    let verificationRecords: [RemoteVerificationRecord]

    private enum CodingKeys: String, CodingKey {
        case id
        case orderNumber = "order_number"
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
        case patient = "patients"
        case components = "ordered_components"
        case captures = "compound_captures"
        case verificationRecords = "verification_records"
    }
}

struct RemotePatient: Decodable, Sendable {
    let id: UUID
    let name: String
    let floor: String
    let room: String
    let bed: String?
    let dob: Date?
}

struct RemoteComponent: Decodable, Sendable {
    let id: UUID
    let totalQuantity: Double
    let quantityUnit: QuantityUnit
    let isUnexpected: Bool
    let unexpectedBarcodeValue: String?
    let product: RemoteProduct
    let utilizedLots: [RemoteUtilizedLot]

    private enum CodingKeys: String, CodingKey {
        case id
        case totalQuantity = "total_quantity"
        case quantityUnit = "quantity_unit"
        case isUnexpected = "is_unexpected"
        case unexpectedBarcodeValue = "unexpected_barcode_value"
        case product = "rxcui_concepts"
        case utilizedLots = "utilized_lots"
    }
}

struct RemoteProduct: Decodable, Sendable {
    let id: UUID
    let name: String
    let importedRxCUI: String?
    let importedTTY: String?
    let importedAt: Date?
    let strength: Double
    let strengthUnit: QuantityUnit
    let mlConcentration: Double?
    let ndcProducts: [RemoteNDCProduct]

    var linkedNDCs: [String] {
        ndcProducts.map(\.ndc)
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case importedRxCUI = "rxcui"
        case importedTTY = "tty"
        case importedAt = "imported_at"
        case strength
        case strengthUnit = "strength_unit"
        case mlConcentration = "ml_concentration"
        case ndcProducts = "rxcui_concept_ndc_products"
    }
}

struct RemoteNDCProduct: Decodable, Sendable {
    let ndc: String
}

struct RemoteUtilizedLot: Decodable, Sendable {
    let id: UUID
    let barcodeValue: String?
    let lot: String
    let expiration: Date?
    let mfg: String?
    let strengthQuantity: Double
    let photoBucketID: UUID?
    let scannedBy: UUID?
    let scannedAt: Date

    private enum CodingKeys: String, CodingKey {
        case id
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

struct RemoteCapture: Decodable, Sendable {
    let id: UUID
    let kind: CaptureKind
    let capturedBy: UUID?
    let capturedAt: Date
    let imageURL: URL?
    let imageName: String?
    let note: String?
    let flags: [RemoteCaptureFlag]

    private enum CodingKeys: String, CodingKey {
        case id
        case kind
        case capturedBy = "captured_by"
        case capturedAt = "captured_at"
        case imageURL = "image_url"
        case imageName = "image_name"
        case note
        case flags = "capture_flags"
    }
}

struct RemoteCaptureFlag: Decodable, Sendable {
    let id: UUID
    let x: Double
    let y: Double
    let createdBy: UUID
    let note: String?

    private enum CodingKeys: String, CodingKey {
        case id
        case x
        case y
        case createdBy = "created_by"
        case note
    }
}

struct RemoteVerificationRecord: Decodable, Sendable {
    let id: UUID
    let verifiedBy: UUID
    let verifiedAt: Date
    let decision: VerificationDecision
    let rejectionReason: String?

    private enum CodingKeys: String, CodingKey {
        case id
        case verifiedBy = "verified_by"
        case verifiedAt = "verified_at"
        case decision
        case rejectionReason = "rejection_reason"
    }
}

@MainActor
extension CompoundingStore {
    func syncOrdersFromSupabase(_ authService: SupabaseAuthService, currentUser: User) async {
        do {
            let snapshots = try await SupabaseOrderSyncService(authService: authService).fetchOrders()
            replaceLocalOrders(with: snapshots, currentUser: currentUser)
        } catch {
            print("Supabase order sync failed: \(error.localizedDescription)")
        }
    }

    private func replaceLocalOrders(with snapshots: [RemoteOrder], currentUser: User) {
        do {
            for order in try modelContext.fetch(FetchDescriptor<CSPOrder>()) {
                modelContext.delete(order)
            }

            let localCurrentUser = localUser(for: currentUser)

            for snapshot in snapshots {
                let patient = Patient(
                    id: snapshot.patient.id,
                    name: snapshot.patient.name,
                    floor: snapshot.patient.floor,
                    room: snapshot.patient.room,
                    bed: snapshot.patient.bed,
                    dob: snapshot.patient.dob
                )

                let order = CSPOrder(
                    id: snapshot.id,
                    orderNumber: snapshot.orderNumber,
                    patient: patient,
                    medicationName: snapshot.medicationName,
                    finalContainer: snapshot.finalContainer,
                    route: snapshot.route,
                    dueTime: snapshot.dueTime,
                    recipeText: snapshot.recipeText,
                    status: snapshot.status,
                    currentStepIndex: snapshot.currentStepIndex,
                    activeEditorID: snapshot.activeEditorID,
                    activeEditorUsername: snapshot.activeEditorUsername,
                    activeEditorName: snapshot.activeEditorName,
                    activeEditorLastSeenAt: snapshot.activeEditorLastSeenAt
                )

                order.components = snapshot.components.map { remoteComponent in
                    let product = Product(
                        id: remoteComponent.product.id,
                        name: remoteComponent.product.name,
                        linkedNDCs: remoteComponent.product.linkedNDCs,
                        importedRxCUI: remoteComponent.product.importedRxCUI,
                        importedTTY: remoteComponent.product.importedTTY,
                        importedAt: remoteComponent.product.importedAt,
                        facilityID: currentUser.facilityID,
                        strength: remoteComponent.product.strength,
                        strengthUnit: remoteComponent.product.strengthUnit,
                        mlConcentration: remoteComponent.product.mlConcentration
                    )

                    let component = CompoundComponent(
                        id: remoteComponent.id,
                        product: product,
                        totalQuantity: remoteComponent.totalQuantity,
                        quantityUnit: remoteComponent.quantityUnit,
                        isUnexpected: remoteComponent.isUnexpected,
                        unexpectedBarcodeValue: remoteComponent.unexpectedBarcodeValue
                    )

                    component.cspOrder = order
                    component.utilizedLots = remoteComponent.utilizedLots.map { remoteLot in
                        CompoundUtilizedLot(
                            id: remoteLot.id,
                            barcodeValue: remoteLot.barcodeValue,
                            lot: remoteLot.lot,
                            expiration: remoteLot.expiration,
                            mfg: remoteLot.mfg,
                            strengthQuantity: remoteLot.strengthQuantity,
                            photoBucketID: remoteLot.photoBucketID,
                            scannedBy: remoteLot.scannedBy.flatMap { localUser(for: $0, currentUser: localCurrentUser) },
                            scannedAt: remoteLot.scannedAt
                        )
                    }

                    return component
                }

                order.captures = snapshot.captures.map { remoteCapture in
                    let capture = CompoundCapture(
                        id: remoteCapture.id,
                        cspOrder: order,
                        kind: remoteCapture.kind,
                        capturedBy: remoteCapture.capturedBy.flatMap { localUser(for: $0, currentUser: localCurrentUser) },
                        timestamp: remoteCapture.capturedAt,
                        imageURL: remoteCapture.imageURL,
                        imageName: remoteCapture.imageName,
                        note: remoteCapture.note
                    )

                    capture.preparerFlags = remoteCapture.flags.map { remoteFlag in
                        CaptureFlag(
                            id: remoteFlag.id,
                            captureID: remoteCapture.id,
                            x: remoteFlag.x,
                            y: remoteFlag.y,
                            createdBy: localUser(for: remoteFlag.createdBy, currentUser: localCurrentUser),
                            note: remoteFlag.note
                        )
                    }

                    return capture
                }

                if let remoteVerification = snapshot.verificationRecords.first {
                    order.verificationRecord = VerificationRecord(
                        id: remoteVerification.id,
                        verifiedBy: localUser(for: remoteVerification.verifiedBy, currentUser: localCurrentUser),
                        verifiedAt: remoteVerification.verifiedAt,
                        decision: remoteVerification.decision,
                        rejectionReason: remoteVerification.rejectionReason
                    )
                }

                modelContext.insert(patient)
                modelContext.insert(order)
            }

            try modelContext.save()
        } catch {
            print("Applying Supabase order snapshot failed: \(error.localizedDescription)")
        }
    }

    @discardableResult
    func upsertLocalUser(from remoteUser: User) -> User {
        let descriptor = FetchDescriptor<User>(
            predicate: #Predicate { $0.id == remoteUser.id }
        )

        if let existing = try? modelContext.fetch(descriptor).first {
            existing.username = remoteUser.username
            existing.deptId = remoteUser.deptId
            existing.facilityID = remoteUser.facilityID
            existing.name = remoteUser.name
            existing.role = remoteUser.role
            existing.active = remoteUser.active
            existing.passwordHash = remoteUser.passwordHash
            return existing
        }

        let localUser = User(
            id: remoteUser.id,
            username: remoteUser.username,
            deptId: remoteUser.deptId,
            facilityID: remoteUser.facilityID,
            passwordHash: remoteUser.passwordHash,
            name: remoteUser.name,
            role: remoteUser.role,
            active: remoteUser.active
        )
        modelContext.insert(localUser)
        return localUser
    }

    private func localUser(for remoteUser: User) -> User {
        upsertLocalUser(from: remoteUser)
    }

    private func localUser(for userID: UUID, currentUser: User) -> User {
        if userID == currentUser.id {
            return currentUser
        }

        let descriptor = FetchDescriptor<User>(
            predicate: #Predicate { $0.id == userID }
        )

        if let existing = try? modelContext.fetch(descriptor).first {
            return existing
        }

        let unknownUser = User(
            id: userID,
            username: "unknown-\(userID.uuidString.prefix(8).lowercased())",
            deptId: currentUser.deptId,
            facilityID: currentUser.facilityID,
            passwordHash: "remote-user",
            name: "Remote User",
            role: .cpht,
            active: false
        )
        modelContext.insert(unknownUser)
        return unknownUser
    }
}
