import SwiftUI
import SwiftData

struct MainScene: View {
    let store: CompoundingStore
    @Query private var orders: [CompoundOrder]

    var body: some View {
        TabView {
            OrdersTab(store: store)
                .tabItem {
                    Label("Orders", systemImage: "list.bullet.rectangle.portrait")
                }

            VerificationTab(store: store)
                .tabItem {
                    Label("Verification", systemImage: "checkmark.seal")
                }
                .badge(orders.filter { $0.status == .waitingForApproval }.count)
        }
    }
}
