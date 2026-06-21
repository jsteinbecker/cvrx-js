import SwiftUI

struct VerifyComponentRow: View {
    let component: CompoundComponent
    let onAddScan: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header: Product name + quantity
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(component.product.name)
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Text("\(component.totalQuantity.formatted()) \(component.quantityUnit.rawValue)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VerificationStatusBadge(
                    isScanned: component.isScanned,
                    isFulfilled: component.isFulfilled(),
                    hasExpired: component.utilizedLots.contains(where: \.isExpired)
                )
            }
            
            Divider()
            
            // Utilized lots
            if component.utilizedLots.isEmpty {
                Text("No lots scanned")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 8)
            } else {
                VStack(spacing: 6) {
                    ForEach(component.utilizedLots) { lot in
                        UtilizedLotRow(lot: lot, quantityUnit: component.quantityUnit)
                    }
                }
            }
            
            // Fulfillment progress
            VStack(spacing: 4) {
                HStack {
                    Text("Progress")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(component.quantityAccountedFor.formatted()) / \(component.totalQuantity.formatted()) \(component.quantityUnit.rawValue)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                ProgressView(value: min(component.quantityAccountedFor / component.totalQuantity, 1.0))
                    .tint(component.isFulfilled() ? .green : .blue)
            }
            
            // Add scan button
            Button(action: onAddScan) {
                Label("Add Scan", systemImage: "plus.circle")
                    .frame(maxWidth: .infinity)
                    .font(.caption.weight(.medium))
            }
            .buttonStyle(.bordered)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(
                    component.isFulfilled() ? Color.green : Color.gray.opacity(0.3),
                    lineWidth: 1
                )
        )
    }
}

struct UtilizedLotRow: View {
    let lot: CompoundUtilizedLot
    let quantityUnit: QuantityUnit
    
    var body: some View {
        HStack(spacing: 8) {
            // Lot number
            VStack(alignment: .leading, spacing: 2) {
                Text("Lot")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                Text(lot.lot)
                    .font(.caption.monospacedDigit())
                    .fontWeight(.semibold)
                    .lineLimit(1)
            }
            
            // Expiration
            VStack(alignment: .leading, spacing: 2) {
                Text("Exp")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                Text(formattedExpDate(lot.expiration))
                    .font(.caption.monospacedDigit())
                    .fontWeight(.semibold)
                    .foregroundStyle(lot.isExpired ? .red : .primary)
            }
            
            // Quantity drawn
            VStack(alignment: .leading, spacing: 2) {
                Text("Qty")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                Text("\(lot.strengthQuantity.formatted()) \(quantityUnit.rawValue)")
                    .font(.caption.monospacedDigit())
                    .fontWeight(.semibold)
            }
            
            Spacer()
            
            // Barcode indicator
            if let barcode = lot.barcodeValue {
                HStack(spacing: 2) {
                    Image(systemName: "barcode")
                        .font(.caption)
                    Text(barcode.prefix(6) + "...")
                        .font(.caption2.monospacedDigit())
                }
                .foregroundStyle(.secondary)
            }
        }
        .padding(6)
        .background(lot.isExpired ? Color.red.opacity(0.05) : Color.blue.opacity(0.02))
        .cornerRadius(4)
    }
    
    private func formattedExpDate(_ date: Date?) -> String {
        guard let date else { return "—" }
        let formatter = DateFormatter()
        formatter.dateFormat = "MM/yy"
        return formatter.string(from: date)
    }
}

struct VerificationStatusBadge: View {
    let isScanned: Bool
    let isFulfilled: Bool
    let hasExpired: Bool
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: statusIcon)
                .font(.caption)
            Text(statusLabel)
                .font(.caption.weight(.medium))
        }
        .foregroundStyle(statusColor)
    }
    
    private var statusIcon: String {
        if hasExpired {
            return "exclamation.circle.fill"
        } else if isFulfilled {
            return "checkmark.circle.fill"
        } else if isScanned {
            return "circle.dashed"
        } else {
            return "circle"
        }
    }
    
    private var statusLabel: String {
        if hasExpired {
            return "Expired"
        } else if isFulfilled {
            return "Complete"
        } else if isScanned {
            return "Partial"
        } else {
            return "Pending"
        }
    }
    
    private var statusColor: Color {
        if hasExpired {
            return .red
        } else if isFulfilled {
            return .green
        } else if isScanned {
            return .blue
        } else {
            return .orange
        }
    }
}

#Preview {
    VStack(spacing: 12) {
        // Fulfilled component with one scanned lot
        VerifyComponentRow(
            component: {
                let product = Product(
                    name: "Iron Sucrose",
                    strength: 50,
                    strengthUnit: .mg,
                    mlConcentration: 1
                )
                let lot = CompoundUtilizedLot(
                    barcodeValue: "SN123456789",
                    lot: "LOT-2024-001",
                    expiration: Calendar.current.date(byAdding: .month, value: 6, to: Date()),
                    strengthQuantity: 50
                )
                return CompoundComponent(
                    product: product,
                    totalQuantity: 50,
                    quantityUnit: .mg,
                    utilizedLots: [lot]
                )
            }(),
            onAddScan: { print("Add scan") }
        )
        
        // Partial component with one lot of multiple needed
        VerifyComponentRow(
            component: {
                let product = Product(
                    name: "Sodium Chloride 0.9%",
                    strength: 0.9,
                    strengthUnit: .g,
                    mlConcentration: 100
                )
                let lot1 = CompoundUtilizedLot(
                    barcodeValue: "SN987654321",
                    lot: "LOT-2024-002",
                    expiration: Calendar.current.date(byAdding: .month, value: 3, to: Date()),
                    strengthQuantity: 50
                )
                return CompoundComponent(
                    product: product,
                    totalQuantity: 100,
                    quantityUnit: .mL,
                    utilizedLots: [lot1]
                )
            }(),
            onAddScan: { print("Add scan") }
        )
        
        // Unscanned component
        VerifyComponentRow(
            component: {
                let product = Product(
                    name: "Amiodarone",
                    strength: 50,
                    strengthUnit: .mg,
                    mlConcentration: 1
                )
                return CompoundComponent(
                    product: product,
                    totalQuantity: 150,
                    quantityUnit: .mg,
                    utilizedLots: []
                )
            }(),
            onAddScan: { print("Add scan") }
        )
    }
    .padding()
}
