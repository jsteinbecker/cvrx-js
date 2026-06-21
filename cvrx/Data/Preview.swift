import SwiftData
import SwiftUI

@MainActor
enum PreviewFixtures {
    static let container: ModelContainer = {
        let configuration = ModelConfiguration(
            isStoredInMemoryOnly: true
        )

        do {
            return try ModelContainer(
                for:
                    CompoundOrder.self,
                    Labeler.self,
                configurations: configuration
            )
        } catch {
            fatalError("Failed to create preview container: \(error)")
        }
    }()

    static let store = CompoundingStore(
        modelContext: container.mainContext
    )

    static let currentUser = User(
        username: "preview.pharmacist",
        deptId: "ncmcrx",
        name: "Preview Pharmacist",
        role: .rph
    )
}
