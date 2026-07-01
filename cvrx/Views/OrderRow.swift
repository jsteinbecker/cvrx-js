import SwiftUI

struct OrderRow: View {
    let order: CSPOrder

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
            Text(order.patient.room)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Image(systemName: "person.crop.square", variableValue: 1.00)
                    .foregroundColor(Color.secondary)
                    .font(.system(.caption, weight: .thin))
                Text(order.patient.initials)
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
        case .pending:            .gray
        case .staging:            .blue
        case .preparing:          .teal
        case .waitingForApproval: .orange
        case .remediation:        .purple
        case .approved:           .green
        case .rejected:           .red
        }
    }
}
