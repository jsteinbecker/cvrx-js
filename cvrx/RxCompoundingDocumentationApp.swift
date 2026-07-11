import SwiftUI
import SwiftData

@main
struct RxCompoundingDocumentationApp: App {
    
    @State private var currentUser: User?

    private let container: ModelContainer
    private let store: CompoundingStore
    private let supabaseAuth: SupabaseAuthService?

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
        let configuration = ModelConfiguration(schema: schema)

        do {
                container = try ModelContainer(for: schema, configurations: configuration)
            } catch {
                print("ModelContainer creation failed: \(error)")
                if let url = configuration.url as URL? {
                    let fm = FileManager.default
                    for suffix in ["", "-shm", "-wal"] {
                        let fileURL = URL(fileURLWithPath: url.path + suffix)
                        do {
                            try fm.removeItem(at: fileURL)
                        } catch {
                            print("Failed to remove \(fileURL): \(error)")
                        }
                    }
                }
                do {
                    container = try ModelContainer(for: schema, configurations: configuration)
                } catch {
                    fatalError("Could not create ModelContainer: \(error)")
                }
            }
        store = CompoundingStore(modelContext: container.mainContext)
        supabaseAuth = SupabaseConfig.bundled.map(SupabaseAuthService.init(config:))
        store.configureSupabaseAuth(supabaseAuth)
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if let currentUser {
                    MainScene(store: store) {
                        store.stopSupabaseRealtime()
                        Task { await supabaseAuth?.signOut() }
                        self.currentUser = nil
                    }
                    .environment(\.currentUser, currentUser)
                } else {
                    LoginScene(store: store, supabaseAuth: supabaseAuth) { user in
                        currentUser = user
                        if let supabaseAuth {
                            Task {
                                do {
                                    try await store.syncLabelersFromSupabase()
                                } catch {
                                    print("Supabase labeler sync failed: \(error.localizedDescription)")
                                }
                                await store.syncOrdersFromSupabase(supabaseAuth, currentUser: user)
                                await MainActor.run {
                                    store.startSupabaseRealtime(currentUser: user)
                                }
                            }
                        }
                    }
                }
            }
            .modelContainer(container)
        }
    }
}
