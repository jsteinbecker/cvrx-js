import SwiftUI

/// Sheet for correcting a scanned lot's barcode, lot number, or expiration.
/// Each changed field is emitted individually via `onOverride` so the caller
/// can dispatch one `correctScannedLotField` store call per correction.
/// All changes are logged to the audit trail and flagged for verifier co-sign.
struct ScanOverrideSheet: View {
    let component: CompoundComponent
    let lot: CompoundUtilizedLot
    /// Called once per changed field with (fieldName, newValue).
    /// fieldName is one of "barcode", "lot", or "expiration".
    /// For expiration, newValue is formatted with DateFormatter.dateStyle = .medium
    /// to match the store's parseDate expectation.
    let onOverride: (String, String) -> Void

    @State private var newLot: String
    @State private var newBarcode: String
    @State private var newExpiration: Date
    @State private var hasExpiration: Bool

    @Environment(\.dismiss) private var dismiss
    @Environment(\.currentUser) private var currentUser

    init(
        component: CompoundComponent,
        lot: CompoundUtilizedLot,
        onOverride: @escaping (String, String) -> Void
    ) {
        self.component = component
        self.lot = lot
        self.onOverride = onOverride
        _newLot = State(initialValue: lot.lot)
        _newBarcode = State(initialValue: lot.barcodeValue ?? "")
        _newExpiration = State(
            initialValue: lot.expiration
                ?? Calendar.current.date(byAdding: .year, value: 1, to: .now)
                ?? .now
        )
        _hasExpiration = State(initialValue: lot.expiration != nil)
    }

    var body: some View {
        NavigationStack {
            Form {
                currentDataSection
                correctionsSection
                auditSection
            }
            .navigationTitle("Override Scan Data")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        applyOverrides()
                        dismiss()
                    }
                    .bold()
                    .disabled(!canApply)
                }
            }
        }
    }

    // MARK: - Sections

    private var currentDataSection: some View {
        Section("Current Data") {
            LabeledContent("Product", value: component.product.name)
            LabeledContent("Lot", value: lot.lot)
            LabeledContent("Barcode", value: lot.barcodeValue ?? "—")
            LabeledContent(
                "Expiration",
                value: lot.expiration.map {
                    $0.formatted(date: .abbreviated, time: .omitted)
                } ?? "None"
            )
            if let scannedBy = lot.scannedBy {
                LabeledContent("Scanned by", value: scannedBy.username)
            }
        }
    }

    private var correctionsSection: some View {
        Section {
            TextField("Lot Number", text: $newLot)
                #if os(iOS)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                #endif

            TextField("Barcode (optional)", text: $newBarcode)
                #if os(iOS)
                .keyboardType(.numbersAndPunctuation)
                .autocorrectionDisabled()
                #endif

            Toggle("Has Expiration Date", isOn: $hasExpiration)

            if hasExpiration {
                DatePicker(
                    "Expiration",
                    selection: $newExpiration,
                    displayedComponents: [.date]
                )
            }
        } header: {
            Text("Corrections")
        } footer: {
            if let user = currentUser, !user.role.canOverrideScan {
                Label(
                    "Your role does not permit scan overrides.",
                    systemImage: "lock.fill"
                )
                .foregroundStyle(.red)
            }
        }
    }

    private var auditSection: some View {
        Section {
            Label(
                "Each correction is logged to the audit trail and requires a verifier co-signature before the order can be approved.",
                systemImage: "doc.text.magnifyingglass"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    // MARK: - Logic

    private var canApply: Bool {
        guard let user = currentUser, user.role.canOverrideScan else { return false }
        guard !newLot.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        return !changedFields.isEmpty
    }

    private var changedFields: [(field: String, newValue: String)] {
        var changes: [(field: String, newValue: String)] = []

        let trimmedLot = newLot.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedLot.isEmpty && trimmedLot != lot.lot {
            changes.append(("lot", trimmedLot))
        }

        let trimmedBarcode = newBarcode.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedBarcode != (lot.barcodeValue ?? "") {
            changes.append(("barcode", trimmedBarcode))
        }

        if hasExpiration {
            let newStr = Self.mediumDateFormatter.string(from: newExpiration)
            let oldStr = lot.expiration.map { Self.mediumDateFormatter.string(from: $0) } ?? ""
            if newStr != oldStr {
                changes.append(("expiration", newStr))
            }
        } else if lot.expiration != nil {
            changes.append(("expiration", ""))
        }

        return changes
    }

    private func applyOverrides() {
        for (field, value) in changedFields {
            onOverride(field, value)
        }
    }

    private static let mediumDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        return f
    }()
}
