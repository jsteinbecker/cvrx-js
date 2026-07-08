import Foundation
import SwiftUI
import SwiftData


struct OrdersTab: View {
    let store: CompoundingStore

    @Environment(\.currentUser) private var user
    @State private var selection: SidebarSelection? = .status(.pending)

    @Query(sort: \CSPOrder.dueTime)
    private var orders: [CSPOrder]
    
    private func count(for status: OrderStatusFilter) -> Int {
        orders.filter { status.matches($0) }.count   // swap in your real predicate
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section {
                    ForEach(OrderStatusFilter.allCases) { status in
                        let ct = count(for: status)
                        HStack {
                            Label(status.title, systemImage: status.systemImage)
                            Spacer()
                            if ct > 0 {
                                Badge(text: "\(ct)", color: .secondary)
                            }
                        }
                        .tag(SidebarSelection.status(status))
                    }
                }
            }
            .navigationTitle("Orders")
            .safeAreaInset(edge: .bottom, spacing: 4) {
                VStack(spacing: 0) {
                    Divider()
                    ForEach(SidebarExtra.allCases) { extra in
                        Button {
                            selection = .extra(extra)             // drives the detail column
                        } label: {
                            Label(extra.title, systemImage: extra.systemImage)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                        }
                        .buttonStyle(.plain)
                        .background(
                            selection == .extra(extra)
                                ? Color.accentColor.opacity(0.15)
                                : Color.clear
                        )
                    }
                }
                .background(.bar)
            }
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    CurrentUserBadge(user: user)
                }
            }
        } detail: {
            switch selection {
                case .status(let status):
                    ordersDetail(for: status)
                case .extra(.facility):
                    NavigationStack { FacilityOverviewScene() }
                case .extra(.labelers):
                    NavigationStack { LabelersScene() }
                case .extra(.productSearch):
                    NavigationStack { RxNormSearchView().navigationTitle("Product Search") }
                case nil:
                    ContentUnavailableView("Select a Category",
                        systemImage: "sidebar.left"
                    )
            }
        }
    }

    @ViewBuilder
    private func ordersDetail(for status: OrderStatusFilter) -> some View {
        let filtered = orders.filter { status.matches($0) }

        NavigationStack {
            HStack {
                Spacer()
                OrderGeneratorButton()
            }
            List(filtered) { order in
                NavigationLink(value: order.id) {
                    OrderRow(order: order)
                }
            }
            .navigationTitle(status.title)
            .navigationDestination(for: CSPOrder.ID.self) { orderID in
                if let order = orders.first(where: { $0.id == orderID }) {
                    OrderDetailScene(order: order, store: store)
                } else {
                    ContentUnavailableView(
                        "Order Not Found",
                        systemImage: "exclamationmark.triangle"
                    )
                }
            }
            .overlay {
                if filtered.isEmpty {
                    ContentUnavailableView(
                        "No \(status.title) Orders",
                        systemImage: status.systemImage
                    )
                }
            }
        }
    }
}

private enum SidebarSelection: Hashable {
    case status(OrderStatusFilter)
    case extra(SidebarExtra)
}

private enum OrderStatusFilter: String, CaseIterable, Identifiable {
    case pending
    case staging
    case preparing
    case waitingForApproval
    case remediation
    case approved
    case rejected

    var id: Self { self }

    var title: String {
        switch self {
        case .pending:            "Pending"
        case .staging:            "Staging"
        case .preparing:          "Preparing"
        case .waitingForApproval: "Waiting for Approval"
        case .remediation:        "Remediation"
        case .approved:           "Recently Approved"
        case .rejected:           "Recently Rejected"
        }
    }

    var systemImage: String {
        switch self {
        case .pending:            "clock"
        case .staging:            "rectangle.grid.3x1"
        case .preparing:          "syringe"
        case .waitingForApproval: "hourglass"
        case .remediation:        "wrench.and.screwdriver"
        case .approved:           "checkmark.circle"
        case .rejected:           "xmark.circle"
        }
    }

    func matches(_ order: CSPOrder) -> Bool {
        switch self {
        case .pending:            order.status == .pending
        case .staging:            order.status == .staging
        case .preparing:          order.status == .preparing
        case .waitingForApproval: order.status == .waitingForApproval
        case .remediation:        order.status == .remediation
        case .approved:           order.status == .approved
        case .rejected:           order.status == .rejected
        }
    }
}

private enum SidebarExtra: String, CaseIterable, Identifiable {
    case facility
    case labelers
    case productSearch

    var id: Self { self }

    var title: String {
        switch self {
        case .facility: "Facility"
        case .labelers: "Labelers"
        case .productSearch: "Product Search"
        }
    }

    var systemImage: String {
        switch self {
        case .facility: "building.2.fill"
        case .labelers: "shippingbox.fill"
        case .productSearch: "box.fill"
        }
    }
}

struct Badge: View {
    let text: String
    let color: Color

    init(text: String = "Badge", color: Color = .accentColor) {
        self.text = text
        self.color = color
    }

    var body: some View {
        PillLabel(text: text, tone: color)
    }
}

private extension Date {
    var isRecent: Bool {
        self >= Calendar.current.date(byAdding: .day, value: -7, to: Date())!
    }
}

@MainActor
struct OrdersTabPreview: View {
    private let container: ModelContainer
    private let store: CompoundingStore

    init() {
        do {
            let configuration = ModelConfiguration(
                isStoredInMemoryOnly: true
            )

            let container = try ModelContainer(
                for: CSPOrder.self,
                Labeler.self,
                configurations: configuration
            )

            self.container = container
            self.store = CompoundingStore(
                modelContext: container.mainContext
            )
        } catch {
            fatalError("Unable to create preview container: \(error)")
        }
    }

    var body: some View {
        OrdersTab(store: store)
            .modelContainer(container)
            .environment(\.currentUser, PreviewFixtures.currentUser)
    }
}

#Preview {
    OrdersTabPreview()
}
