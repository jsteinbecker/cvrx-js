import SwiftUI
import SwiftData

@main
struct RxCompoundingDocumentationApp: App {
    
    @State private var user: User = MockData.makeUserJts()
    @State private var appMode: AppMode = .prepare

    private let container: ModelContainer
    private let store: CompoundingStore

    init() {
        let schema = Schema([
            CSPOrder.self,
            CSPEvent.self,
            VerificationRecord.self,
            AuditEvent.self,
            RemediationRequest.self,
            RemediationCapture.self,
            RemediationLotChange.self,
            BUDMultidosePolicy.self,
            CaptureFlag.self,
            CompoundComponent.self,
            CompoundUtilizedLot.self,
            ScanOverride.self,
            ScanEvent.self,
            CompoundCapture.self,
            Compound.self,
            Product.self,
            Patient.self,
            User.self,
            Labeler.self,
            NDCProduct.self,
            Facility.self,
            FloorUnit.self,
            Room.self,
            Bed.self,
            SearchHistoryEntry.self,
            CachedNDCName.self
        ])

        do {
            container = try ModelContainer(for: schema)
        } catch {
            let fm = FileManager.default
            if let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
                for suffix in ["", "-shm", "-wal"] {
                    try? fm.removeItem(at: appSupport.appendingPathComponent("default.store\(suffix)"))
                }
            }
            do {
                container = try ModelContainer(for: schema)
            } catch {
                fatalError("Could not create ModelContainer: \(error)")
            }
        }
        store = CompoundingStore(modelContext: container.mainContext)
    }

    var body: some Scene {
        WindowGroup {
            MainScene(store: store)
                .modelContainer(container)
                .environment(\.currentUser, user)
        }
    }
}


enum AppMode {
    case prepare
    case verify
}
