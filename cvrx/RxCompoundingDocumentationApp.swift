import SwiftUI
import SwiftData

@main
struct RxCompoundingDocumentationApp: App {
    @State private var user = MockData.makeUserMsm()

    private let container: ModelContainer
    private let store: CompoundingStore
    
    init() {
        do {
            container = try ModelContainer(for:
                                           CompoundOrder.self,
                                           Labeler.self
            )
            store = CompoundingStore(modelContext: container.mainContext)
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            MainScene(store: store)
                .modelContainer(container)
                .environment(\.currentUser, user)
        }
    }
}
