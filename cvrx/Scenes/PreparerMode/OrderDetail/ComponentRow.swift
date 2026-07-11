import SwiftUI


private struct DraftLotEntry: Identifiable {
    let id = UUID()
    var barcodeValue: String?
    var lotNumber = ""
    var hasExpiration = true
    var expiration = Calendar.current.date(byAdding: .year, value: 1, to: .now) ?? .now
    var mfg = ""
    var quantityText = ""

    var parsedQuantity: Double? {
        Double(quantityText.replacingOccurrences(of: ",", with: ""))
    }

    var isExpired: Bool {
        guard hasExpiration else { return false }
        let startOfExpiry = Calendar.current.startOfDay(for: expiration)
        guard let dayAfterExpiry = Calendar.current.date(
            byAdding: .day, value: 1, to: startOfExpiry
        ) else { return false }
        return dayAfterExpiry < .now
    }

    var isEmpty: Bool {
        (barcodeValue ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && lotNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && quantityText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && mfg.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var requiresScannedDetails: Bool {
        !(barcodeValue ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var isValid: Bool {
        !lotNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (!requiresScannedDetails || hasExpiration)
            && (parsedQuantity ?? 0) > 0
            && !isExpired
    }

    /// The first field that needs attention, for keyboard-driven validation.
    var firstInvalidCell: ComponentRow.Cell? {
        if lotNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .lot(id)
        }
        if requiresScannedDetails && !hasExpiration {
            return .exp(id)
        }
        if (parsedQuantity ?? 0) <= 0 {
            return .qty(id)
        }
        if isExpired {
            return .exp(id)
        }
        return nil
    }
}

struct ComponentRow: View {
    let component: CompoundComponent
    var canMutate: Bool
    let onAddLot: (CompoundUtilizedLot) -> Void
    let onRemoveLot: (CompoundUtilizedLot) -> Void
    var onRemoveComponent: (() -> Void)? = nil
    var onOverrideLot: ((CompoundUtilizedLot) -> Void)? = nil
    var onMutate: ((CompoundComponent) -> Void)? = nil

    @State private var drafts: [DraftLotEntry] = []
    @State private var didInit = false
    @State private var lotPendingRemoval: CompoundUtilizedLot?
    @FocusState private var focus: Cell?
    @State private var isEditing = false
    
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var hSizeClass
    #endif

    static let quantityTolerance = 0.001

    enum Cell: Hashable {
        case lot(UUID), exp(UUID), qty(UUID), mfg(UUID)

        var draftID: UUID {
            switch self {
            case let .lot(id), let .exp(id), let .qty(id), let .mfg(id): id
            }
        }
    }

    private enum Status { case unexpected, empty, scannedIncomplete, insufficient, sufficient, over }

    private var isCompact: Bool {
        #if os(iOS)
        return hSizeClass == .compact
        #else
        return false
        #endif
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            header
            Divider()
            lotTable
        }
            .padding(.vertical, 8)
            .padding(.horizontal, 6)
            .roundedPanel(
                fill: .thickMaterial,
                borderColor: statusColor.opacity(0.1),
                lineWidth: 2
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
                if canMutate && !component.isUnexpected && component.utilizedLots.isEmpty {
                    addDraft()
                }
            }
            .zIndex(mfgDropdownActive ? 1 : 0)
            #if os(iOS)
            .toolbar { keyboardNavigationToolbar }
            #endif
    }

    #if os(iOS)
    /// The Tab/Shift-Tab equivalent: an accessory bar above the keyboard with
    /// Previous/Next chevrons that walk `focusOrder`, plus a Done button.
    @ToolbarContentBuilder
    private var keyboardNavigationToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .keyboard) {
            Button(action: focusPreviousField) {
                Image(systemName: "chevron.up")
            }
            .disabled(!canFocusPrevious)

            Button(action: focusNextField) {
                Image(systemName: "chevron.down")
            }
            .disabled(!canFocusNext)

            Spacer()

            Button("Done") { focus = nil }
        }
    }
    #endif

    private var mfgDropdownActive: Bool {
        if case .mfg = focus { return true }
        return false
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: iconName)
                .font(.title3)
                .foregroundStyle(statusColor)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(component.product.name)
                        .font(.body.weight(.medium))
                        .lineLimit(2)

                    AcceptableNDCInfoButton(
                        productName: component.product.name,
                        ndcs: component.product.linkedNDCs
                    )
                }

                HStack(spacing: 6) {
                    Text("Need \(Self.format(component.totalQuantity)) \(unit)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    if component.isUnexpected {
                        Text("Unexpected")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.red)
                    } else if !component.utilizedLots.isEmpty {
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
            if component.isUnexpected {
                Button(role: .destructive, action: { onRemoveComponent?() }) {
                    Image(systemName: "trash.fill")
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(!canMutate || onRemoveComponent == nil)
                .accessibilityLabel("Delete unexpected component")
            } else if shouldShowEditToggle {
                editToggle
            }
        }
    }

    private var editToggle: some View {
        Group {
            if isEditing {
                Button(action: finishEditing) {
                    Label("Done", systemImage: "checkmark.circle.fill")
                }
                .buttonStyle(.bordered)
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

    private var shouldShowEditToggle: Bool {
        canMutate && !component.isUnexpected && (isEditing || (drafts.isEmpty && !component.utilizedLots.isEmpty))
    }

    // MARK: - Lot table

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

    private var lotTable: some View {
        VStack(alignment: .leading, spacing: 8) {
            if component.utilizedLots.isEmpty && drafts.isEmpty {
                Text(canMutate ? "No lots recorded yet." : "No lots recorded.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                if isCompact {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(component.utilizedLots) { committedCardCompact($0) }
                        ForEach(drafts) { draft in
                            if let binding = binding(for: draft.id) {
                                draftCardCompact(binding)
                            }
                        }
                    }
                    draftWarnings
                } else {
                    Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
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
            }
            if isEditing {
                HStack {
                    Spacer()
                    Button(action: addDraft) {
                        Label("Add Lot", systemImage: "plus")
                            .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
    }

    private var columnHeader: some View {
        GridRow {
            columnLabel("DOSE UTILIZED")
            EmptyView()
            columnLabel("LOT/BATCH #")
            columnLabel("EXPIRY")
            columnLabel("MANUFACTURER")
            Color.clear.frame(width: 28, height: 1)
        }
    }

    private func columnLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption2.weight(.bold))
            .foregroundStyle(.tertiary)
            .gridColumnAlignment(.leading)
    }

    private func committedRow(_ lot: CompoundUtilizedLot) -> some View {
        GridRow(alignment: .center, ) {
            HStack(spacing: 2) {
                Text(Self.format(lot.strengthQuantity))
                    .font(.subheadline.monospacedDigit())
                Text(unit)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            EmptyView()
            HStack(spacing: 6) {
                Image(systemName: lotIconName(for: lot))
                    .font(.caption)
                    .foregroundStyle(lotColor(for: lot))
                Text(lotLabel(for: lot))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(lotRequiresDetails(lot) ? .blue : .primary)
            }
            HStack(spacing: 4) {
                Text(lot.expiration.map { $0.formatted(date: .abbreviated, time: .omitted) } ?? (lotRequiresDetails(lot) ? "Add expiry" : "—"))
                    .font(.caption)
                    .foregroundStyle(lotRequiresDetails(lot) ? .blue : (lot.isExpired ? .red : .secondary))

                if let hint = expiryRelativeHint(for: lot.expiration) {
                    Text(hint)
                        .font(.caption2.weight(.medium).monospacedDigit())
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.secondary.opacity(0.12)))
                }
            }

            Text(lot.mfg ?? "—")
                .font(.caption)
                .foregroundStyle(.secondary)
            
            if lotRequiresDetails(lot), canMutate {
                Button { editCommitted(lot) } label: {
                    Image(systemName: "square.and.pencil")
                        .font(.body)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Edit lot details")
            } else {
                Color.clear.frame(width: 28)
            }
        }
    }

    private func committedCardCompact(_ lot: CompoundUtilizedLot) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 6) {
                Image(systemName: lotIconName(for: lot))
                    .font(.caption2)
                    .foregroundStyle(lotColor(for: lot))
                Text(lotLabel(for: lot))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(lotRequiresDetails(lot) ? .blue : .primary)
                    .lineLimit(1)
                Spacer()
                if lotRequiresDetails(lot), canMutate {
                    Button { editCommitted(lot) } label: {
                        Image(systemName: "square.and.pencil")
                            .font(.body)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Edit lot details")
                }
                // Quantity badge
                HStack(spacing: 2) {
                    Text(Self.format(lot.strengthQuantity))
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                    Text(unit)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 8)

            Divider().padding(.horizontal, 12)

            // Two-column detail: Expires | Manufacturer
            HStack(alignment: .top, spacing: 0) {
                VStack(alignment: .leading, spacing: 3) {
                    compactFieldLabel("Expires")
                    HStack(spacing: 5) {
                        Text(lot.expiration.map { $0.formatted(date: .abbreviated, time: .omitted) } ?? (lotRequiresDetails(lot) ? "Add expiry" : "—"))
                            .font(.subheadline)
                            .foregroundStyle(lotRequiresDetails(lot) ? .blue : (lot.isExpired ? .red : .primary))

                        if let hint = expiryRelativeHint(for: lot.expiration) {
                            Text(hint)
                                .font(.caption2.weight(.medium).monospacedDigit())
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Color.secondary.opacity(0.12)))
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.trailing, 6)

                Divider().frame(maxHeight: 36)

                VStack(alignment: .leading, spacing: 3) {
                    compactFieldLabel("Manufacturer")
                    Text(lot.mfg ?? "—")
                        .font(.subheadline)
                        .foregroundStyle(lot.mfg != nil ? .primary : .tertiary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 6)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .roundedPanel(
            cornerRadius: 10,
            fill: Color.secondary.opacity(0.04),
            borderColor: Color.primary.opacity(0.06)
        )
    }

    /// Pulls a committed lot back into the draft state for seamless inline editing.
    private func editCommitted(_ lot: CompoundUtilizedLot) {
        // 1. Remove from the committed source of truth
        onRemoveLot(lot)
        
        // 2. Map data back to a draft state
        var draft = DraftLotEntry()
        draft.barcodeValue = lot.barcodeValue
        draft.lotNumber = lot.lot
        draft.hasExpiration = lot.expiration != nil || lotRequiresDetails(lot)
        if let exp = lot.expiration { draft.expiration = exp }
        draft.mfg = lot.mfg ?? ""
        draft.quantityText = Self.format(lot.strengthQuantity)

        // 3. Insert and focus
        drafts.append(draft)
        isEditing = true

        // Slight delay ensures the UI has rendered the new text fields before focusing.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            focus = draft.firstInvalidCell ?? .qty(draft.id)
        }
    }

    // MARK: - Submission & Validation

    /// Per-row submit chain: Qty → Lot → Mfg → commit. This is what fires when
    /// the person taps the keyboard's return/next key, as opposed to the
    /// cross-row Previous/Next accessory buttons (see `focusOrder`).
    private func handleSubmit(from cell: Cell) {
        switch cell {
        case .qty(let id): focus = .lot(id)
        case .lot(let id): focus = .exp(id)
        case .exp(let id): focus = .mfg(id)
        case .mfg(let id): commitDraft(id: id)
        }
    }

    /// Evaluates a single draft. If valid, commits it and intelligently decides what to do next.
    private func commitDraft(id: UUID) {
        guard let index = drafts.firstIndex(where: { $0.id == id }) else { return }
        let draft = drafts[index]

        // Handle empty draft exit
        if draft.isEmpty {
            drafts.remove(at: index)
            if drafts.isEmpty { isEditing = false }
            return
        }

        // Commit logic
        if draft.isValid {
            guard let qty = draft.parsedQuantity else { return }
            let trimmedMfg = draft.mfg.trimmingCharacters(in: .whitespacesAndNewlines)
            
            onAddLot(CompoundUtilizedLot(
                barcodeValue: draft.barcodeValue,
                lot: draft.lotNumber.trimmingCharacters(in: .whitespacesAndNewlines),
                expiration: draft.hasExpiration ? draft.expiration : nil,
                mfg: trimmedMfg.isEmpty ? nil : trimmedMfg,
                strengthQuantity: qty
            ))
            
            drafts.remove(at: index)

            // Flow-State UX: If we still need more quantity, automatically tee up the next draft.
            if remainingNeed() > Self.quantityTolerance {
                addDraft()
            } else if drafts.isEmpty {
                isEditing = false
                focus = nil
            } else if let next = firstCellNeedingAttention() {
                focus = next
            }
        } else if let target = draft.firstInvalidCell {
            // Keep user locked in the row if they missed something
            focus = target
        }
    }

    private func draftRow(_ draft: Binding<DraftLotEntry>) -> some View {
        let entry = draft.wrappedValue

        return GridRow(alignment: .center) {
            MeasurementInput(magnitudeText: draft.quantityText, unit: unit)
                .frame(minWidth: 55)
                .focused($focus, equals: .qty(entry.id))
                .submitLabel(.next)
                .onSubmit { handleSubmit(from: .qty(entry.id)) }
            TextField("", text: draft.lotNumber)
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 90, maxWidth: 130)
                .padding(.leading, 5)
                .focused($focus, equals: .lot(entry.id))
                .submitLabel(.next)
                .onSubmit { handleSubmit(from: .lot(entry.id)) }
                #if os(iOS)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                #endif
            expiryCell(draft)
                .padding(.leading, 5)
            mfgAutocompleteField(draft)
                .frame(minWidth: 100, maxWidth: 140)
                .padding(.leading, 5)
            Button(role: .destructive) { removeDraft(entry.id) } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .padding(5)
        }
    }

    private func draftCardCompact(_ draft: Binding<DraftLotEntry>) -> some View {
        let entry = draft.wrappedValue
        return VStack(alignment: .leading, spacing: 0) {
            // Card header
            HStack {
                Text("New Lot")
                    .font(.caption2.weight(.bold))
                    .textCase(.uppercase)
                    .foregroundStyle(.tertiary)
                    .tracking(0.4)
                Spacer()
                Button(role: .destructive) { removeDraft(entry.id) } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.body)
                        .foregroundStyle(.quaternary)
                }
                .buttonStyle(.borderless)
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 8)

            Divider().padding(.horizontal, 12)

            // Top row: Qty | Lot
            HStack(alignment: .top, spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    compactFieldLabel("Qty (\(unit))")
                    MeasurementInput(magnitudeText: draft.quantityText, unit: unit)
                        .focused($focus, equals: .qty(entry.id))
                        .submitLabel(.next)
                        .onSubmit { handleSubmit(from: .qty(entry.id)) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.trailing, 6)

                Divider().frame(maxHeight: 52)

                VStack(alignment: .leading, spacing: 4) {
                    compactFieldLabel("Lot / Batch")
                    TextField("Required", text: draft.lotNumber)
                        .textFieldStyle(.roundedBorder)
                        .focused($focus, equals: .lot(entry.id))
                        .submitLabel(.next)
                        .onSubmit { handleSubmit(from: .lot(entry.id)) }
                        #if os(iOS)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                        #endif
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 6)
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)

            Divider().padding(.horizontal, 12).padding(.top, 10)

            // Bottom row: MFG | Expires
            HStack(alignment: .top, spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    compactFieldLabel("Manufacturer")
                    mfgAutocompleteField(draft)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.trailing, 6)

                Divider().frame(maxHeight: 52)

                VStack(alignment: .leading, spacing: 4) {
                    compactFieldLabel("Expires")
                    expiryCell(draft)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 6)
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 12)
        }
        .roundedPanel(
            cornerRadius: 10,
            fill: Color.secondary.opacity(0.07),
            borderColor: Color.primary.opacity(0.08)
        )
    }

    private func compactFieldLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .textCase(.uppercase)
            .foregroundStyle(.tertiary)
            .tracking(0.3)
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
        let entry = draft.wrappedValue
        if entry.hasExpiration {
            HStack(spacing: 2) {
                DatePicker("", selection: draft.expiration, displayedComponents: .date)
                    .datePickerStyle(.compact)
                    .labelsHidden()
                    .focused($focus, equals: .exp(entry.id))
                Button { draft.wrappedValue.hasExpiration = false } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.borderless)
            }
        } else {
            Button("Set date") {
                draft.wrappedValue.hasExpiration = true
                focus = .exp(entry.id)
            }
            .font(.caption)
            .buttonStyle(.borderless)
        }
    }
    
    private func mfgAutocompleteField(_ draft: Binding<DraftLotEntry>) -> some View {
        let entry = draft.wrappedValue

        return MfgAutoCompleteField(
            text: draft.mfg,
            isFocused: focus == .mfg(entry.id),
            onSubmit: { handleSubmit(from: .mfg(entry.id)) },
            onSelect: { _ in handleSubmit(from: .mfg(entry.id)) },
            onEscape: { focus = nil }
        )
        .focused($focus, equals: .mfg(entry.id))
    }

    private func startEditing() {
        isEditing = true
        if drafts.isEmpty && component.utilizedLots.count != 0 { addDraft() }
        else if let first = firstCellNeedingAttention() {
            focus = first
        }
    }

    // MARK: - Field navigation (iOS "Tab" equivalent)

    /// Every focusable cell across all draft rows, in tab order: for each
    /// draft, Qty → Lot → Mfg, then on to the next draft. Committed lots
    /// aren't included since they must be pulled into a draft via
    /// `editCommitted` before they're focusable.
    private var focusOrder: [Cell] {
        drafts.flatMap { [Cell.qty($0.id), .lot($0.id), .exp($0.id), .mfg($0.id)] }
    }

    private func moveFocus(by offset: Int) {
        let order = focusOrder
        guard let current = focus, let index = order.firstIndex(of: current) else { return }
        let target = index + offset
        guard order.indices.contains(target) else { return }
        focus = order[target]
    }

    private var canFocusPrevious: Bool {
        guard let current = focus, let index = focusOrder.firstIndex(of: current) else { return false }
        return index > 0
    }

    private var canFocusNext: Bool {
        guard let current = focus, let index = focusOrder.firstIndex(of: current) else { return false }
        return index < focusOrder.count - 1
    }

    private func focusPreviousField() { moveFocus(by: -1) }
    private func focusNextField() { moveFocus(by: 1) }

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
        if focus.map(\.draftID) == id { focus = nil }
        drafts.removeAll { $0.id == id }
    }

    /// Returns the `Cell` for the first invalid non-empty draft field, scanning
    /// rows in order (lot → qty, skipping mfg which is optional).
    private func firstCellNeedingAttention() -> Cell? {
        for draft in drafts where !draft.isEmpty {
            if let cell = draft.firstInvalidCell { return cell }
        }
        return nil
    }

    private var canFinish: Bool {
        drafts.allSatisfy { $0.isEmpty || $0.isValid }
    }

    private func finishEditing() {
        for draft in drafts where !draft.isEmpty && draft.isValid {
            guard let qty = draft.parsedQuantity else { continue }
            let trimmedMfg = draft.mfg.trimmingCharacters(in: .whitespacesAndNewlines)
            onAddLot(CompoundUtilizedLot(
                barcodeValue: draft.barcodeValue,
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
           qty > remainingNeed(excludingDraft: draft.id) + Self.quantityTolerance {
            return ("Exceeds remaining need", .orange)
        }
        return nil
    }

    private func remainingNeed(excludingDraft excludedID: UUID? = nil) -> Double {
        let pending = drafts
            .filter { $0.id != excludedID && !$0.isEmpty }
            .compactMap(\.parsedQuantity)
            .reduce(0, +)
        return component.quantityRemaining - pending
    }

    private var status: Status {
        if component.isUnexpected { return .unexpected }
        if hasScannedLotNeedingDetails { return .scannedIncomplete }
        let drawn = component.quantityAccountedFor
        let target = component.totalQuantity
        if drawn <= Self.quantityTolerance { return .empty }
        if drawn < target - Self.quantityTolerance { return .insufficient }
        if drawn > target + Self.quantityTolerance { return .over }
        return .sufficient
    }

    private var statusColor: Color {
        switch status {
        case .unexpected:   .red
        case .empty:        .secondary
        case .scannedIncomplete: .blue
        case .insufficient: .orange
        case .sufficient:   .green
        case .over:         .yellow
        }
    }

    private var iconName: String {
        switch status {
        case .unexpected: "exclamationmark.triangle.fill"
        case .sufficient: "checkmark.circle.fill"
        case .over:       "exclamationmark.circle.fill"
        case .scannedIncomplete: "barcode.viewfinder"
        case .insufficient, .empty:
            component.isScanned ? "circle.lefthalf.filled" : "barcode.viewfinder"
        }
    }

    private var hasScannedLotNeedingDetails: Bool {
        component.utilizedLots.contains(where: lotRequiresDetails)
    }

    private func lotRequiresDetails(_ lot: CompoundUtilizedLot) -> Bool {
        guard let barcode = lot.barcodeValue?.trimmingCharacters(in: .whitespacesAndNewlines),
              !barcode.isEmpty
        else { return false }

        return lot.lot.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || lot.expiration == nil
    }

    private func lotIconName(for lot: CompoundUtilizedLot) -> String {
        if lotRequiresDetails(lot) { return "barcode.viewfinder" }
        return lot.isExpired ? "exclamationmark.triangle.fill" : "shippingbox.fill"
    }

    private func lotColor(for lot: CompoundUtilizedLot) -> Color {
        if lotRequiresDetails(lot) { return .blue }
        return lot.isExpired ? .red : Color.accentColor
    }

    private func lotLabel(for lot: CompoundUtilizedLot) -> String {
        let trimmedLot = lot.lot.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedLot.isEmpty ? "Details needed" : trimmedLot
    }

    private func expiryRelativeHint(for expiration: Date?) -> String? {
        guard let expiration else { return nil }

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let expiryDay = calendar.startOfDay(for: expiration)

        if expiryDay == today { return "(today)" }

        let isFuture = expiryDay > today
        let components = isFuture
            ? calendar.dateComponents([.year, .month, .day], from: today, to: expiryDay)
            : calendar.dateComponents([.year, .month, .day], from: expiryDay, to: today)

        let years = components.year ?? 0
        let months = components.month ?? 0
        let days = components.day ?? 0
        let valueAndUnit: (value: Int, unit: String)

        if years > 0 {
            valueAndUnit = (years, "y")
        } else if months > 0 {
            valueAndUnit = (months, "mo.")
        } else {
            valueAndUnit = (max(days, 1), "d")
        }

        if isFuture {
            return "(in \(valueAndUnit.value)\(valueAndUnit.unit))"
        }
        return "(\(valueAndUnit.value)\(valueAndUnit.unit) ago)"
    }

    private var unit: String { component.quantityUnit.rawValue }

    private var progressText: String {
        "\(Self.format(component.quantityAccountedFor)) / \(Self.format(component.totalQuantity)) \(unit)"
    }

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


private enum   cx {
    static let names: [String] = {
        guard
            let url = Bundle.main.url(forResource: "Labelers", withExtension: "json"),
            let data = try? Data(contentsOf: url),
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: [String: Any]]
        else { return [] }
        var seen = Set<String>()
        return root.values
            .compactMap { $0["name"] as? String }
            .filter { seen.insert($0).inserted }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }()
}
