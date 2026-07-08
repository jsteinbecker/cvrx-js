import SwiftUI
import SwiftData

struct VerificationTab: View {
    let store: CompoundingStore
    @Environment(\.currentUser) private var user
    @Query(sort: \CSPOrder.dueTime) private var orders: [CSPOrder]

    private var ordersReadyForVerification: [CSPOrder] {
        orders.filter { $0.status == .waitingForApproval }
    }

    var body: some View {
        NavigationStack {
            Group {
                if ordersReadyForVerification.isEmpty {
                    ContentUnavailableView(
                        "Nothing to Verify",
                        systemImage: "tray",
                        description: Text("Compounds marked ready for verification will appear here.")
                    )
                } else {
                    List(ordersReadyForVerification) { order in
                        NavigationLink(value: order.id) {
                            VerifyQueueRow(order: order)
                        }
                    }
                }
            }
            .navigationTitle("Verification Queue")
            .navigationDestination(for: CSPOrder.ID.self) { orderID in
                if let order = orders.first(where: { $0.id == orderID }) {
                    VerifyScene(order: order, store: store)
                } else {
                    ContentUnavailableView("Order Not Found", systemImage: "exclamationmark.triangle")
                }
            }
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    CurrentUserBadge(user: user)
                }
            }
        }
    }
}

struct VerifyQueueRow: View {
    let order: CSPOrder

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: order.remediation != nil ? "arrow.uturn.left.circle.fill" : "photo.stack")
                .font(.title2)
                .foregroundStyle(order.remediation != nil ? .purple : .orange)
                .frame(width: 40)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(order.orderNumber)
                        .font(.headline)
                    if order.remediation != nil {
                        PillLabel(
                            text: "RE-VERIFY",
                            tone: .purple,
                            foregroundStyle: .white,
                            font: .caption2.weight(.bold),
                            horizontalPadding: 6,
                            verticalPadding: 2,
                            backgroundOpacity: 1.0
                        )
                    }
                }
                Text(order.medicationName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text("\(order.captures.count) image\(order.captures.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }
}
