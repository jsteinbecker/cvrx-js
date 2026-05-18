import SwiftUI

/// Sheet for entering a new utilized lot for a component. Captures barcode
/// (optional), lot number, expiration, and the quantity drawn (defaults to the
/// component's remaining need).
struct AddLotSheet: View {
    let component: CompoundComponent
    let onCancel: () -> Void
    let onSubmit: (CompoundUtilizedLot) -> Void

    @State private var barcodeValue: String = ""
    @State private var lotNumber: String = ""
    @State private var quantityText: String
    @State private var hasExpiration: Bool = true
    @State private var expiration: Date

    @Environment(\.dismiss) private var dismiss

    init(
        component: CompoundComponent,
        onCancel: @escaping () -> Void,
        onSubmit: @escaping (CompoundUtilizedLot) -> Void
    ) {
        self.component = component
        self.onCancel = onCancel
        self.onSubmit = onSubmit
        // Default the quantity field to whatever is still needed; if fully
        // fulfilled already, default to the component's full target.
        let remaining = component.quantityRemaining
        let defaultQty = remaining > 0 ? remaining : component.totalQuantity
        _quantityText = State(initialValue: AddLotSheet.formatForField(defaultQty))
        // 1-year default expiration is a sensible starting point for sterile
        // products; the user will overwrite it from the label.
        _expiration = State(initialValue: Calendar.current.date(
            byAdding: .year, value: 1, to: .now) ?? .now)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Product") {
                    LabeledContent("Name", value: component.product.name)
                    LabeledContent("Need", value: "\(ComponentRow.format(component.totalQuantity)) \(component.quantityUnit.rawValue)")
                    LabeledContent(
                        "Already drawn",
                        value: "\(ComponentRow.format(component.quantityAccountedFor)) \(component.quantityUnit.rawValue)"
                    )
                    LabeledContent(
                        "Remaining",
                        value: "\(ComponentRow.format(component.quantityRemaining)) \(component.quantityUnit.rawValue)"
                    )
                }

                Section("Lot") {
                    TextField("Lot number", text: $lotNumber)
                        .frame(width: 300)
                        .padding(10)
                        #if os(iOS)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        #endif

                    TextField("Barcode (optional)", text: $barcodeValue)
                        .frame(width: 300)
                        .padding(10)
                        #if os(iOS)
                        .keyboardType(.numbersAndPunctuation)
                        .autocorrectionDisabled()
                        #endif

                    Toggle("Has expiration date", isOn: $hasExpiration)

                    if hasExpiration {
                        DatePicker("Expiration", selection: $expiration, displayedComponents: [.date])
                            .padding(10)

                        if isExpired {
                            Text("Component cannot be expired")
                                .foregroundStyle(.red)
                        }
                    }
                }

                Section {
                    HStack {
                        TextField("Quantity", text: $quantityText)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .frame(maxWidth: 200, alignment: .init(horizontal: .leading, vertical: .center))
                            .padding(10)
                            #if os(iOS)
                            .keyboardType(.decimalPad)
                            #endif
                        Text(component.quantityUnit.rawValue)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Quantity Drawn")
                } footer: {
                    if let qty = parsedQuantity, qty > component.quantityRemaining + 0.001 {
                        Text("This quantity exceeds the remaining need. The component will still be marked fulfilled.")
                            .frame(maxWidth: 800)
                            .foregroundStyle(.orange)
                    }
                }
            }
            .navigationTitle("Add Lot")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onCancel()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        guard let qty = parsedQuantity, qty > 0 else { return }
                        let trimmedLot = lotNumber.trimmingCharacters(in: .whitespacesAndNewlines)
                        let trimmedBarcode = barcodeValue.trimmingCharacters(in: .whitespacesAndNewlines)
                        let lot = CompoundUtilizedLot(
                            barcodeValue: trimmedBarcode.isEmpty ? nil : trimmedBarcode,
                            lot: trimmedLot,
                            expiration: hasExpiration ? expiration : nil,
                            strengthQuantity: qty
                        )
                        onSubmit(lot)
                        dismiss()
                    }
                    .bold()
                    .disabled(!canSubmit)
                }
            }
        }
    }

    // MARK: form helpers

    private var parsedQuantity: Double? {
        Double(quantityText.replacingOccurrences(of: ",", with: "."))
    }

    private var isExpired: Bool {
        guard hasExpiration else { return false }
        let endOfDay = Calendar.current.startOfDay(for: expiration).addingTimeInterval(86_400)
        return endOfDay < Date()
    }

    private var canSubmit: Bool {
        let lotOK = !lotNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let qtyOK = (parsedQuantity ?? 0) > 0
        return lotOK && qtyOK && !isExpired
    }

    private static func formatForField(_ value: Double) -> String {
        // Keep up to three decimals but strip trailing zeros for a clean field.
        let f = NumberFormatter()
        f.minimumFractionDigits = 0
        f.maximumFractionDigits = 3
        f.numberStyle = .decimal
        f.usesGroupingSeparator = false
        return f.string(from: NSNumber(value: value)) ?? "\(value)"
    }
}
