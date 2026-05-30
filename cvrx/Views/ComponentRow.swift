import SwiftUI

// MARK: - Draft lot entry (local state for an uncommitted editable row)

private struct DraftLotEntry: Identifiable {
    let id = UUID()
    var lotNumber = ""
    var hasExpiration = true
    var expiration = Calendar.current.date(byAdding: .year, value: 1, to: .now) ?? .now
    var mfg = ""
    var quantityText = ""

    var parsedQuantity: Double? {
        Double(quantityText.replacingOccurrences(of: ",", with: "."))
    }

    /// A lot is considered expired once the whole expiration day has elapsed,
    /// i.e. the start of the *following* day is in the past.
    ///
    /// Uses calendar day arithmetic rather than adding a fixed 86,400 s so the
    /// boundary stays correct across DST transitions (where a day is 23 or 25 h).
    var isExpired: Bool {
        guard hasExpiration else { return false }
        let startOfExpiry = Calendar.current.startOfDay(for: expiration)
        guard let dayAfterExpiry = Calendar.current.date(
            byAdding: .day, value: 1, to: startOfExpiry
        ) else { return false }
        return dayAfterExpiry < .now
    }

    /// A pristine row the user never touched — ignored on commit, never blocks "Done".
    var isEmpty: Bool {
        lotNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && quantityText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && mfg.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var isValid: Bool {
        !lotNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (parsedQuantity ?? 0) > 0
            && !isExpired
    }
}

// MARK: - Component row

/// A component with a spreadsheet-style lot table.
///
/// **View mode** – committed lots render as a compact, read-only grid.
/// **Edit mode** – each new lot is an editable grid row; move freely between
/// cells, then tap the section's **Done** checkmark to validate, commit every
/// filled row, and return to view mode.
///
/// Committed lots stay read-only to preserve the verification record — to change
/// one, remove it in edit mode and re-add (or wire up an `onUpdateLot` callback).
struct ComponentRow: View {
    let component: CompoundComponent
    var canMutate: Bool
    let onAddLot: (CompoundUtilizedLot) -> Void
    let onRemoveLot: (CompoundUtilizedLot) -> Void

    @State private var drafts: [DraftLotEntry] = []
    @State private var isEditing = false
    @State private var didInit = false
    @State private var lotPendingRemoval: CompoundUtilizedLot?
    @FocusState private var focus: Cell?

    static let quantityTolerance = 0.001

    private enum Cell: Hashable {
        case lot(UUID), qty(UUID), mfg(UUID)

        var draftID: UUID {
            switch self {
            case let .lot(id), let .qty(id), let .mfg(id): id
            }
        }
    }
    private enum Status { case empty, insufficient, sufficient, over }

    // MARK: Body

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            Divider()
            lotTable
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous).fill(rowBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(statusColor.opacity(0.5), lineWidth: 2)
        )
        .confirmationDialog(
            "Remove lot \(lotPendingRemoval?.lot ?? "")?",
            isPresented: Binding(
                get: { lotPendingRemoval != nil },
                set: { if !$0 { lotPendingRemoval = nil } }
            ),
            titleVisibility: .visible,
            presenting: lotPendingRemoval
        ) { lot in
            Button("Remove Lot", role: .destructive) {
                onRemoveLot(lot)
                lotPendingRemoval = nil
            }
            Button("Cancel", role: .cancel) { lotPendingRemoval = nil }
        }
        .onAppear {
            guard !didInit else { return }
            didInit = true
            if canMutate && component.utilizedLots.isEmpty {
                isEditing = true
                addDraft()
            }
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: iconName)
                .font(.title3)
                .foregroundStyle(statusColor)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 3) {
                Text(component.product.name)
                    .font(.body.weight(.medium))
                    .lineLimit(2)

                HStack(spacing: 6) {
                    Text("Need \(Self.format(component.totalQuantity)) \(unit)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    if !component.utilizedLots.isEmpty {
                        Text("·").font(.caption).foregroundStyle(.tertiary)
                        Text(progressText)
                            .font(.caption.weight(.semibold).monospacedDigit())
                            .foregroundStyle(statusColor)
                    }

                    if status == .over {
                        Text("· over-drawn")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.yellow)
                    }
                }
            }

            Spacer()

            if canMutate { editToggle }
        }
    }

    private var editToggle: some View {
        Group {
            if isEditing {
                Button(action: finishEditing) {
                    Label("Done", systemImage: "checkmark.circle.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canFinish)
            } else {
                Button(action: startEditing) {
                    Label("Edit", systemImage: "square.and.pencil")
                }
                .buttonStyle(.bordered)
            }
        }
        .labelStyle(.titleAndIcon)
        .controlSize(.small)
        .font(.caption.weight(.semibold))
    }
    
    private func binding(for id: UUID) -> Binding<DraftLotEntry>? {
        guard drafts.contains(where: { $0.id == id }) else { return nil }
        return Binding(
            get: { self.drafts.first(where: { $0.id == id }) ?? DraftLotEntry() },
            set: { newValue in
                if let i = self.drafts.firstIndex(where: { $0.id == id }) {
                    self.drafts[i] = newValue
                }
            }
        )
    }

    // MARK: Lot table

    private var lotTable: some View {
        VStack(alignment: .leading, spacing: 8) {
            if component.utilizedLots.isEmpty && drafts.isEmpty {
                Text(canMutate ? "No lots recorded yet." : "No lots recorded.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 6) {
                    columnHeader
                    ForEach(component.utilizedLots) { committedRow($0) }
                    ForEach(drafts) { draft in
                        if let binding = binding(for: draft.id) {
                            draftRow(binding)
                        }
                    }
                }

                draftWarnings
            }

            if isEditing {
                Button(action: addDraft) {
                    Label("Add Lot", systemImage: "plus")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }

    private var columnHeader: some View {
        GridRow {
            columnLabel("Lot / Batch")
            columnLabel("Qty (\(unit))")
            columnLabel("Expires")
            columnLabel("MFG")
            Color.clear.frame(width: 28, height: 1)
        }
    }

    private func columnLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption2.weight(.bold))
            .textCase(.uppercase)
            .foregroundStyle(.tertiary)
            .gridColumnAlignment(.leading)
    }

    // Committed lot — read-only; removable while editing.
    private func committedRow(_ lot: CompoundUtilizedLot) -> some View {
        GridRow(alignment: .center) {
            HStack(spacing: 6) {
                Image(systemName: lot.isExpired ? "exclamationmark.triangle.fill" : "shippingbox.fill")
                    .font(.caption)
                    .foregroundStyle(lot.isExpired ? .red : Color.accentColor)
                Text(lot.lot).font(.subheadline.weight(.semibold))
            }

            Text(Self.format(lot.strengthQuantity))
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)

            Text(lot.expiration.map { $0.formatted(date: .abbreviated, time: .omitted) } ?? "—")
                .font(.caption)
                .foregroundStyle(lot.isExpired ? .red : .secondary)

            Text(lot.mfg ?? "—")
                .font(.caption)
                .foregroundStyle(.secondary)

            if isEditing {
                Button(role: .destructive) { lotPendingRemoval = lot } label: {
                    Image(systemName: "trash").font(.caption)
                }
                .buttonStyle(.borderless)
            } else {
                Color.clear.frame(width: 1, height: 1)
            }
        }
    }

    // Editable draft — exactly one GridRow so the grid's shape stays fixed.
    // Warnings render below the grid (see `draftWarnings`): a full-width
    // spanning GridRow crashes Grid layout when a committed row is inserted
    // in the same update pass (e.g. on "Done").
    private func draftRow(_ draft: Binding<DraftLotEntry>) -> some View {
        let entry = draft.wrappedValue

        return GridRow(alignment: .center) {
            TextField("Lot #", text: draft.lotNumber)
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 90)
                .focused($focus, equals: .lot(entry.id))
                .submitLabel(.next)
                .onSubmit { focus = .qty(entry.id) }
#if os(iOS)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
#endif

            TextField("0", text: draft.quantityText)
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 56, maxWidth: 72)
                .focused($focus, equals: .qty(entry.id))
#if os(iOS)
                .keyboardType(.decimalPad)
#endif

            expiryCell(draft)

            TextField("—", text: draft.mfg)
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 70)
                .focused($focus, equals: .mfg(entry.id))

            Button(role: .destructive) { removeDraft(entry.id) } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
        }
    }

    @ViewBuilder
    private var draftWarnings: some View {
        let active = drafts.compactMap { draft -> (id: UUID, text: String, color: Color)? in
            guard let w = warning(for: draft) else { return nil }
            return (draft.id, w.text, w.color)
        }
        if !active.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(active, id: \.id) { warning in
                    Label(warning.text, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption2)
                        .foregroundStyle(warning.color)
                }
            }
        }
    }

    @ViewBuilder
    private func expiryCell(_ draft: Binding<DraftLotEntry>) -> some View {
        if draft.wrappedValue.hasExpiration {
            HStack(spacing: 2) {
                DatePicker("", selection: draft.expiration, displayedComponents: .date)
                    .datePickerStyle(.compact)
                    .labelsHidden()
                Button { draft.wrappedValue.hasExpiration = false } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.borderless)
            }
        } else {
            Button("Set date") { draft.wrappedValue.hasExpiration = true }
                .font(.caption)
                .buttonStyle(.borderless)
        }
    }

    // MARK: Editing actions

    private func startEditing() {
        isEditing = true
        if drafts.isEmpty && component.utilizedLots.isEmpty { addDraft() }
    }

    private func addDraft() {
        var entry = DraftLotEntry()
        let remaining = remainingNeed()
        if remaining > Self.quantityTolerance {
            entry.quantityText = Self.format(remaining)
        }
        drafts.append(entry)
        focus = .lot(entry.id)
    }

    private func removeDraft(_ id: UUID) {
        // Drop focus first if it lives on the row being removed, otherwise the
        // FocusState points at a cell that no longer exists.
        if focus.map(\.draftID) == id { focus = nil }
        drafts.removeAll { $0.id == id }
    }

    /// Need still uncovered, accounting for both committed lots *and* the
    /// quantities entered in other in-progress drafts (optionally excluding one).
    ///
    /// Used for prefill and the over-draw warning so that splitting a single
    /// component across several new lots doesn't double-count the remaining need.
    private func remainingNeed(excludingDraft excludedID: UUID? = nil) -> Double {
        let pending = drafts
            .filter { $0.id != excludedID && !$0.isEmpty }
            .compactMap(\.parsedQuantity)
            .reduce(0, +)
        return component.quantityRemaining - pending
    }

    private var canFinish: Bool {
        drafts.allSatisfy { $0.isEmpty || $0.isValid }
    }

    private func finishEditing() {
        for draft in drafts where !draft.isEmpty && draft.isValid {
            guard let qty = draft.parsedQuantity else { continue }
            let trimmedMfg = draft.mfg.trimmingCharacters(in: .whitespacesAndNewlines)
            onAddLot(CompoundUtilizedLot(
                lot: draft.lotNumber.trimmingCharacters(in: .whitespacesAndNewlines),
                expiration: draft.hasExpiration ? draft.expiration : nil,
                mfg: trimmedMfg.isEmpty ? nil : trimmedMfg,
                strengthQuantity: qty
            ))
        }
        drafts.removeAll()
        focus = nil
        isEditing = false
    }

    private func warning(for draft: DraftLotEntry) -> (text: String, color: Color)? {
        if !draft.isEmpty && draft.isExpired {
            return ("This lot is expired", .red)
        }
        if let qty = draft.parsedQuantity,
           component.quantityRemaining > Self.quantityTolerance,
           qty > remainingNeed(excludingDraft: draft.id) + Self.quantityTolerance {
            return ("Exceeds remaining need", .orange)
        }
        return nil
    }

    // MARK: Derived status

    private var status: Status {
        let drawn = component.quantityAccountedFor
        let target = component.totalQuantity
        if drawn <= Self.quantityTolerance { return .empty }
        if drawn < target - Self.quantityTolerance { return .insufficient }
        if drawn > target + Self.quantityTolerance { return .over }
        return .sufficient
    }

    private var statusColor: Color {
        switch status {
        case .empty:        .secondary
        case .insufficient: .orange
        case .sufficient:   .green
        case .over:         .yellow
        }
    }

    private var rowBackground: Color {
        switch status {
        case .empty:        .secondary.opacity(0.05)
        case .insufficient: .orange.opacity(0.08)
        case .sufficient:   component.isScanned ? .green.opacity(0.08) : .yellow.opacity(0.05)
        case .over:         .yellow.opacity(0.10)
        }
    }

    private var iconName: String {
        switch status {
        case .sufficient: "checkmark.circle.fill"
        case .over:       "exclamationmark.circle.fill"
        case .insufficient, .empty:
            component.isScanned ? "circle.lefthalf.filled" : "barcode.viewfinder"
        }
    }

    private var unit: String { component.quantityUnit.rawValue }

    private var progressText: String {
        "\(Self.format(component.quantityAccountedFor)) / \(Self.format(component.totalQuantity)) \(unit)"
    }

    // MARK: Formatting

    private static let formatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.minimumFractionDigits = 0
        f.maximumFractionDigits = 3
        f.usesGroupingSeparator = false
        return f
    }()

    static func format(_ value: Double) -> String {
        formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }
}
