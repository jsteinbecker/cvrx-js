import SwiftUI

/// Root scene. Splits the app into two independent workflows:
/// 1. **Orders** — browsing and compounding (capture happens here).
/// 2. **Verification** — a queue of orders that are ready for verification.
struct MainScene: View {
    // CompoundingStore is marked @Observable (new Observation framework),
    // so @State is the correct wrapper for owning it — not @StateObject.
    @State private var store = CompoundingStore()

    // User is read from the environment (injected by the App). MainScene
    // does not need to forward it to its children explicitly — each child
    // can pull it from the environment itself, which avoids prop drilling
    // and the @StateObject-from-parameter bug below.
    @EnvironmentObject var user: User

    var body: some View {
        NavigationStack {
            TabView {
                OrdersTab(store: store)
                    .tabItem {
                        Label("Orders", systemImage: "list.bullet.rectangle.portrait")
                    }
                
                VerificationTab(store: store)
                    .tabItem {
                        Label("Verification", systemImage: "checkmark.seal")
                    }
                    .badge(store.ordersReadyForVerification.count)
            }
        }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Text(user.username)
                Text(user.role.rawValue)
                Button("Profile", systemImage: "person.crop.circle") {}
            }
        }
    }
}


