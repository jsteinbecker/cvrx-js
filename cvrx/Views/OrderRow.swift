import SwiftUI

struct OrderRow: View {
    let order: CompoundOrder

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(order.orderNumber)
                    .font(.headline)
                Spacer()
                StatusPill(status: order.status)
            }

            Text(order.medicationName)
                .font(.subheadline)
                .foregroundStyle(.primary)

            Text(order.patient.name)
                .font(.caption)
                .foregroundStyle(.secondary)

            ProgressView(value: Double(order.fulfilledComponentCount), total: Double(max(order.components.count, 1))) {
                Text("Components: \(order.fulfilledComponentCount)/\(order.components.count)")
                    .font(.caption2)
            }
        }
        .padding(.vertical, 4)
    }
}

struct StatusPill: View {
    let status: OrderStatus

    var body: some View {
        Text(status.rawValue)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(statusColor.opacity(0.15), in: Capsule())
            .foregroundStyle(statusColor)
    }

    private var statusColor: Color {
        switch status {
        case .pending: .secondary
        case .compounding: .blue
        case .waitingForApproval: .orange
        case .remediation: .purple
        case .approved: .green
        case .rejected: .red
        }
    }
}
