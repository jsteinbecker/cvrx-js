import SwiftUI

struct OrderRow: View {
    let order: CSPOrder

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(order.medicationName)
                    .font(.headline)
                Spacer()
                if order.isActivelyLocked {
                    LiveOrderPresenceIcon(order: order)
                }
                StatusPill(status: order.status)
            }
            Text(order.orderNumber)
                .font(.subheadline)
                .foregroundStyle(.primary)
            HStack {
                Text(order.patient.room)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let bed = order.patient.bed, !bed.isEmpty {
                    Text(bed)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
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

struct LiveOrderPresenceIcon: View {
    let order: CSPOrder

    var body: some View {
        Image(systemName: "person.crop.circle.fill.badge.checkmark")
            .font(.caption.weight(.semibold))
            .symbolRenderingMode(.palette)
            .foregroundStyle(.white, .green)
            .padding(5)
            .background(Circle().fill(Color.green.opacity(0.18)))
            .help(helpText)
            .accessibilityLabel(helpText)
    }

    private var helpText: String {
        if let name = order.activeEditorDisplayName {
            return "\(name) is in this order"
        }
        return "Someone is in this order"
    }
}

struct StatusPill: View {
    let status: OrderStatus

    var body: some View {
        PillLabel(
            text: status.rawValue,
            tone: statusColor,
            font: .caption2.weight(.semibold)
        )
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
