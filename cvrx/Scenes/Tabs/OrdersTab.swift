import Foundation
import SwiftUI
import SwiftData


struct OrdersTab: View {
    let store: CompoundingStore

    @Environment(\.currentUser)
    private var user
    @State
    private var selection: SidebarSelection? = .status(.pending)
    @State
    private var showingAddLabelersSheet = false

    @Query(sort: \CompoundOrder.dueTime)
    private var orders: [CompoundOrder]

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section {
                    ForEach(OrderStatusFilter.allCases) { status in
                        Label(status.title, systemImage: status.systemImage)
                            .tag(SidebarSelection.status(status))   // tag type must match the binding
                    }
                }
            }
            .navigationTitle("Orders")
            .safeAreaInset(edge: .bottom, spacing: 2) {
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
                    HStack {
                        Image(systemName: "person.crop.circle.badge.checkmark", variableValue: 1.00)
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(Color.green, Color.white, Color.gray)
                            .font(.system(size: 16, weight: .regular))

                        Text(user.name)
                    }
                }

                ToolbarItem(placement: .automatic) {
                    Button {
                        showingAddLabelersSheet = true
                    } label: {
                        Image(systemName: "link", variableValue: 1.00)
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(Color.gray, Color.white, Color.gray)
                            .font(.system(size: 16, weight: .regular))
                    }
                    .buttonStyle(.plain)
                }
            }
        } detail: {
            switch selection {
            case .status(let status):
                ordersDetail(for: status)
            case .extra(.labelers):
                NavigationStack {
                    LabelersScene()
                }
            case nil:
                ContentUnavailableView(
                    "Select a Category",
                    systemImage: "sidebar.left"
                )
            }
        }
        .sheet(isPresented: $showingAddLabelersSheet) {
            AddLabelersSheet()
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
            .navigationDestination(for: CompoundOrder.ID.self) { orderID in
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
    case waitingForApproval
    case remediation
    case approved
    case rejected

    var id: Self { self }

    var title: String {
        switch self {
        case .pending:
            "Pending"
        case .waitingForApproval:
            "Waiting for Approval"
        case .remediation:
            "Remediation"
        case .approved:
            "Recently Approved"
        case .rejected:
            "Recently Rejected"
        }
    }

    var systemImage: String {
        switch self {
        case .pending:
            "clock"
        case .waitingForApproval:
            "hourglass"
        case .remediation:
            "wrench.and.screwdriver"
        case .approved:
            "checkmark.circle"
        case .rejected:
            "xmark.circle"
        }
    }

    func matches(_ order: CompoundOrder) -> Bool {
        switch self {
        case .pending:
            order.status == .pending
        case .waitingForApproval:
            order.status == .waitingForApproval
        case .remediation:
            order.status == .remediation
        case .approved:
            order.status == .approved
        case .rejected:
            order.status == .rejected
        }
    }
}

private enum SidebarExtra: String, CaseIterable, Identifiable {
    case labelers

    var id: Self { self }

    var title: String {
        switch self {
        case .labelers: "Labelers"
        }
    }

    var systemImage: String {
        switch self {
        case .labelers: "building.2"
        }
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
                for: CompoundOrder.self,
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
