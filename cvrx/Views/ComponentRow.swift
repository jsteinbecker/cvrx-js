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

    var isValid: Bool {
        !lotNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (parsedQuantity ?? 0) > 0
            && !isExpired
    }

    /// The first field that needs attention, for keyboard-driven validation.
    var firstInvalidCell: ComponentRow.Cell? {
        if lotNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .lot(id)
        }
        if (parsedQuantity ?? 0) <= 0 {
            return .qty(id)
        }
        // isExpired is shown as an inline warning; caller decides whether to
        // block or let the user fix via the date picker — surface lot focus.
        if isExpired {
            return .lot(id)
        }
        return nil
    }
}

struct ComponentRow: View {
    let component: CompoundComponent
    var canMutate: Bool
    let onAddLot: (CompoundUtilizedLot) -> Void
    let onRemoveLot: (CompoundUtilizedLot) -> Void
    var onOverrideLot: ((CompoundUtilizedLot) -> Void)? = nil
    var onMutate: ((CompoundComponent) -> Void)? = nil

    @State private var drafts: [DraftLotEntry] = []
    @State private var didInit = false
    @State private var lotPendingRemoval: CompoundUtilizedLot?
    @FocusState private var focus: Cell?
    @State private var highlightedIndex: Int? = nil
    @State private var isEditing = false
    
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var hSizeClass
    #endif

    static let quantityTolerance = 0.001

    enum Cell: Hashable {
        case lot(UUID), qty(UUID), mfg(UUID)

        var draftID: UUID {
            switch self {
            case let .lot(id), let .qty(id), let .mfg(id): id
            }
        }
    }

    private enum Status { case empty, scannedIncomplete, insufficient, sufficient, over }

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
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(.thickMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(statusColor.opacity(0.1), lineWidth: 2)
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
                    addDraft()
                }
            }
            .zIndex(mfgDropdownActive ? 1 : 0)
    }

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
            if shouldShowEditToggle { editToggle }
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
        canMutate && (isEditing || (drafts.isEmpty && !component.utilizedLots.isEmpty))
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
                    Grid(alignment: .leading, horizontalSpacing: 3, verticalSpacing: 6) {
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
                HStack(spacing: 12) {
                    #if os(iOS)
                    HStack(spacing: 4) {
                        Button(action: focusPreviousLot) {
                            Image(systemName: "chevron.left")
                                .font(.caption.weight(.semibold))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(!canFocusPrevious)
                        
                        Button(action: focusNextLot) {
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(!canFocusNext)
                    }
                    #endif
                    
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
            columnLabel("DOSE (\(unit))")
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
        GridRow(alignment: .center) {
            HStack {
                Text(Self.format(lot.strengthQuantity))
                    .font(.subheadline.monospacedDigit())
            }
            
            HStack(spacing: 6) {
                Image(systemName: lotIconName(for: lot))
                    .font(.caption)
                    .foregroundStyle(lotColor(for: lot))
                Text(lotLabel(for: lot))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(lotRequiresDetails(lot) ? .blue : .primary)
            }
            
            Text(lot.expiration.map { $0.formatted(date: .abbreviated, time: .omitted) } ?? (lotRequiresDetails(lot) ? "Add expiry" : "—"))
                .font(.caption)
                .foregroundStyle(lotRequiresDetails(lot) ? .blue : (lot.isExpired ? .red : .secondary))

            Text(lot.mfg ?? "—")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 4) {
                if canMutate {
                    Button {
                        editCommitted(lot)
                    } label: {
                        Image(systemName: "pencil").font(.caption)
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    
                    Button(role: .destructive) {
                        lotPendingRemoval = lot
                    } label: {
                        Image(systemName: "trash").font(.caption)
                    }
                    .buttonStyle(.borderless)
                }
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
                // Quantity badge
                HStack(spacing: 2) {
                    Text(Self.format(lot.strengthQuantity))
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                    Text(unit)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                if canMutate {
                    HStack(spacing: 2) {
                        Button { editCommitted(lot) } label: {
                            Image(systemName: "pencil")
                                .font(.caption2)
                                .padding(6)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                        Button(role: .destructive) { lotPendingRemoval = lot } label: {
                            Image(systemName: "trash")
                                .font(.caption2)
                                .padding(6)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                    }
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
                    Text(lot.expiration.map { $0.formatted(date: .abbreviated, time: .omitted) } ?? (lotRequiresDetails(lot) ? "Add expiry" : "—"))
                        .font(.subheadline)
                        .foregroundStyle(lotRequiresDetails(lot) ? .blue : (lot.isExpired ? .red : .primary))
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
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.secondary.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
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
        draft.hasExpiration = lot.expiration != nil
        if let exp = lot.expiration { draft.expiration = exp }
        draft.mfg = lot.mfg ?? ""
        draft.quantityText = Self.format(lot.strengthQuantity)
        
        // 3. Insert and focus
        drafts.append(draft)
        isEditing = true
        
        // Slight delay ensures the UI has rendered the new text fields before focusing
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            focus = .qty(draft.id)
        }
    }

    // MARK: - Submission & Validation

    private func handleSubmit(from cell: Cell) {
        switch cell {
        case .lot:
            return // Caller already handles moving focus to mfg
        case .qty:
            focus = .mfg(cell.draftID)
        case .mfg:
            // Instead of evaluating all drafts globally, just commit this specific row.
            commitDraft(id: cell.draftID)
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
                .padding(.leading, 5)
            Button(role: .destructive) { removeDraft(entry.id) } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
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
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.secondary.opacity(0.07))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
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
    
    @ViewBuilder
    private func mfgAutocompleteField(_ draft: Binding<DraftLotEntry>) -> some View {
        let entry = draft.wrappedValue
        let isFocused = focus == .mfg(entry.id)
        let matches: [String] = {
            guard isFocused, !entry.mfg.isEmpty else { return [] }
            let query = entry.mfg

            return LabelerStore.names
                .filter { $0.localizedCaseInsensitiveContains(query) }
                .sorted { lhs, rhs in
                    let lhsPrefix = lhs.range(of: query, options: [.caseInsensitive, .anchored]) != nil
                    let rhsPrefix = rhs.range(of: query, options: [.caseInsensitive, .anchored]) != nil

                    if lhsPrefix != rhsPrefix {
                        return lhsPrefix && !rhsPrefix
                    }
                    return lhs.localizedStandardCompare(rhs) == .orderedAscending
                }
                .prefix(8)
                .map { $0 }
        }()

        let select: (String) -> Void = { name in
            draft.mfg.wrappedValue = name
            highlightedIndex = nil
            // Treat autocomplete selection as a submit from mfg
            handleSubmit(from: .mfg(entry.id))
        }

        TextField("", text: draft.mfg)
            .textFieldStyle(.roundedBorder)
            .frame(minWidth: 70)
            .focused($focus, equals: .mfg(entry.id))
            .submitLabel(.done)
            .onSubmit { handleSubmit(from: .mfg(entry.id)) }
            .onChange(of: entry.mfg) { highlightedIndex = nil }
            .onKeyPress(.downArrow) {
                guard isFocused, !matches.isEmpty else { return .ignored }
                highlightedIndex = min((highlightedIndex ?? -1) + 1, matches.count - 1)
                return .handled
            }
            .onKeyPress(.upArrow) {
                guard isFocused, !matches.isEmpty else { return .ignored }
                highlightedIndex = max((highlightedIndex ?? matches.count) - 1, 0)
                return .handled
            }
            .onKeyPress(.return) {
                guard isFocused, let i = highlightedIndex, matches.indices.contains(i)
                else { return .ignored }
                select(matches[i])
                return .handled
            }
            .onKeyPress(.tab) {
                guard isFocused, let i = highlightedIndex, matches.indices.contains(i)
                else { return .ignored }
                select(matches[i])
                return .handled
            }
            .onKeyPress(.escape) {
                guard isFocused, !matches.isEmpty else { return .ignored }
                highlightedIndex = nil
                focus = nil
                return .handled
            }
            .overlay(alignment: .topLeading) {
                if !matches.isEmpty {
                    mfgAutocompleteDropdown(matches: matches, select: select)
                }
            }
    }

    @ViewBuilder
    private func mfgAutocompleteDropdown(matches: [String], select: @escaping (String) -> Void) -> some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: 32)
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(matches.enumerated()), id: \.element) { index, name in
                    Button { select(name) } label: {
                        Text(name)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .background(highlightedIndex == index ? Color.accentColor : Color.clear)
                    .foregroundStyle(highlightedIndex == index ? Color.white : Color.primary)

                    if index != matches.count - 1 {
                        Divider()
                    }
                }
            }
            .zIndex(20)
            .frame(minWidth: 150, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 6)
                    .fill(.ultraThickMaterial)
                    .blur(radius: 6)
            }
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.primary.opacity(0.4), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.15), radius: 6, x: 0, y: 3)
        }
    }

    private func startEditing() {
        isEditing = true
        if drafts.isEmpty && component.utilizedLots.count != 0 { addDraft() }
        else if let first = firstCellNeedingAttention() {
            focus = first
        }
    }

    /// Returns all lots (committed + draft) in display order.
    private func allLots() -> [(type: LotType, index: Int)] {
        var result: [(LotType, Int)] = []
        for (i, _) in component.utilizedLots.enumerated() {
            result.append((.committed(i), i))
        }
        for (i, _) in drafts.enumerated() {
            result.append((.draft(i), i))
        }
        return result
    }

    private enum LotType: Hashable {
        case committed(Int), draft(Int)
    }

    /// Finds the current focused lot in the display order.
    private func currentFocusedLotIndex() -> Int? {
        let allLots = allLots()
        guard let currentFocus = focus else { return nil }
        let focusedDraftID = currentFocus.draftID

        for (i, lotType) in allLots.enumerated() {
            switch lotType.0 {
            case .draft(let draftIndex):
                if drafts[draftIndex].id == focusedDraftID {
                    return i
                }
            case .committed:
                // Committed lots aren't focusable directly; they're converted
                // to drafts via editCommitted() before they can be focused.
                break
            }
        }
        return nil
    }

    private var canFocusPrevious: Bool {
        guard let current = currentFocusedLotIndex() else { return false }
        return current > 0
    }

    private var canFocusNext: Bool {
        guard let current = currentFocusedLotIndex() else { return false }
        return current < allLots().count - 1
    }

    private func focusPreviousLot() {
        let allLots = allLots()
        guard let current = currentFocusedLotIndex(), current > 0 else { return }
        let previousType = allLots[current - 1].0
        focusLot(type: previousType)
    }

    private func focusNextLot() {
        let allLots = allLots()
        guard let current = currentFocusedLotIndex(), current < allLots.count - 1 else { return }
        let nextType = allLots[current + 1].0
        focusLot(type: nextType)
    }

    private func focusLot(type: LotType) {
        switch type {
        case .draft(let index):
            guard index < drafts.count else { return }
            focus = .lot(drafts[index].id)
        case .committed(let index):
            // For committed lots, we'd need to put them in edit mode first
            // Pull them into drafts and focus
            guard index < component.utilizedLots.count else { return }
            editCommitted(component.utilizedLots[index])
        }
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
        case .empty:        .secondary
        case .scannedIncomplete: .blue
        case .insufficient: .orange
        case .sufficient:   .green
        case .over:         .yellow
        }
    }

    private var iconName: String {
        switch status {
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


private enum LabelerStore {
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
