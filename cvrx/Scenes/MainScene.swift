import SwiftUI
import SwiftData


struct MainScene: View {
    @Environment(\.currentUser) private var currentUser

    let store: CompoundingStore
    let onLogout: () -> Void

    @State private var destination: Destination? = nil

    enum Destination { case orders, verification }

    var body: some View {
        Group {
            switch destination {
            case .orders:
                OrdersTab(store: store)
            case .verification:
                VerificationTab(store: store)
            case nil:
                NavigationStack {
                    tileMenu
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Menu {
                    Button(role: .destructive, action: onLogout) {
                        Label("Log Out", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                } label: {
                    Label(currentUser?.name ?? "User", systemImage: "person.crop.circle")
                }
            }
        }
    }

    private var tileMenu: some View {
        VStack {
            Spacer()
            HStack(spacing: 24) {
                Button { destination = .orders } label: {
                    MenuTile(title: "Preparation & Compounding", systemImage: "cross.vial.fill")
                }
                Button { destination = .verification } label: {
                    MenuTile(title: "Verification", systemImage: "checkmark.seal.fill")
                }
            }
            .buttonStyle(.plain)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
        .navigationTitle("CVRx")
    }
}

private struct MenuTile: View {
    let title: String
    let systemImage: String

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: systemImage)
                .font(.system(size: 52, weight: .regular))
                .symbolRenderingMode(.hierarchical)

            Text(title)
                .font(.headline)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(.tint)
        .frame(width: 200, height: 200)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(.separator, lineWidth: 0.5)
        )
        .contentShape(RoundedRectangle(cornerRadius: 20)) // full tile is tappable
    }
}
