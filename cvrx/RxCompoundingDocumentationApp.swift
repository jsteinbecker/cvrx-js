import SwiftUI

@main
struct RxCompoundingDocumentationApp: App {
    // `User` is an ObservableObject (reference type with @Published fields),
    // so the owner of the single source-of-truth instance must use
    // @StateObject — not @State. @State would not subscribe to
    // objectWillChange, so mutations to user.role / user.username would
    // never re-render the UI.
    @StateObject private var user = MockData.makeUserMsm()

    var body: some Scene {
        WindowGroup {
            MainScene()
                .environmentObject(user)
        }
    }
}
