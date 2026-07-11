import SwiftUI
import SwiftData

struct NDCProductsScene: View {
    let store: CompoundingStore

    @Environment(\.currentUser) private var currentUser
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \Product.name)
    private var products: [Product]

    @Query private var components: [CompoundComponent]

    @State private var searchText = ""
    @State private var isShowingAddSheet = false
    @State private var editingProduct: Product?
    @State private var blockedDeleteProduct: Product?

    private var facilityID: String? {
        currentUser?.facilityID
    }

    private var facilityProducts: [Product] {
        guard let facilityID else { return [] }
        return products.filter { product in
            product.facilityID == facilityID || product.facilityID == nil
        }
    }

    private var filteredProducts: [Product] {
        let trimmedSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSearch.isEmpty else { return facilityProducts }
        return facilityProducts.filter { product in
            product.name.localizedCaseInsensitiveContains(trimmedSearch)
                || product.linkedNDCs.contains { $0.localizedCaseInsensitiveContains(trimmedSearch) }
                || (product.importedRxCUI?.localizedCaseInsensitiveContains(trimmedSearch) == true)
        }
    }

    private var ndcCount: Int {
        Set(facilityProducts.flatMap(\.linkedNDCs)).count
    }

    var body: some View {
        List {
            Section {
                NDCProductsSummaryRow(
                    productCount: facilityProducts.count,
                    ndcCount: ndcCount,
                    facilityID: facilityID
                )
            }

            if !filteredProducts.isEmpty {
                Section("Products") {
                    ForEach(filteredProducts) { product in
                        Button {
                            editingProduct = product
                        } label: {
                            NDCProductRow(
                                product: product,
                                usageCount: usageCount(for: product)
                            )
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                delete(product)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }

                            Button {
                                editingProduct = product
                            } label: {
                                Label("Edit", systemImage: "pencil")
                            }
                            .tint(.blue)
                        }
                    }
                }
            }
        }
        .listStyle(.inset)
        .overlay {
            if facilityID == nil {
                ContentUnavailableView(
                    "No Facility",
                    systemImage: "building.2",
                    description: Text("Sign in with a facility to manage NDC products.")
                )
            } else if facilityProducts.isEmpty {
                ContentUnavailableView(
                    "No NDC Products",
                    systemImage: "shippingbox",
                    description: Text("Add a product or import one from Product Search.")
                )
            } else if filteredProducts.isEmpty {
                ContentUnavailableView.search(text: searchText)
            }
        }
        .searchable(text: $searchText, prompt: "Search products or NDCs")
        .navigationTitle("NDC Products")
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button {
                    isShowingAddSheet = true
                } label: {
                    Image(systemName: "plus")
                }
                .disabled(facilityID == nil)
                .accessibilityLabel("Add NDC product")
            }
        }
        .sheet(isPresented: $isShowingAddSheet) {
            NDCProductEditor(product: nil, facilityID: facilityID, store: store)
        }
        .sheet(item: $editingProduct) { product in
            NDCProductEditor(product: product, facilityID: facilityID, store: store)
        }
        .alert("Product In Use", isPresented: blockedDeleteBinding) {
            Button("OK", role: .cancel) { blockedDeleteProduct = nil }
        } message: {
            if let blockedDeleteProduct {
                Text("\(blockedDeleteProduct.name) is linked to existing order components and cannot be deleted from the catalog.")
            }
        }
    }

    private var blockedDeleteBinding: Binding<Bool> {
        Binding(
            get: { blockedDeleteProduct != nil },
            set: { isPresented in
                if !isPresented { blockedDeleteProduct = nil }
            }
        )
    }

    private func usageCount(for product: Product) -> Int {
        components.filter { $0.product.id == product.id }.count
    }

    private func delete(_ product: Product) {
        guard usageCount(for: product) == 0 else {
            blockedDeleteProduct = product
            return
        }
        modelContext.delete(product)
        try? modelContext.save()
    }
}

private struct NDCProductsSummaryRow: View {
    let productCount: Int
    let ndcCount: Int
    let facilityID: String?

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: "shippingbox.fill")
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 34, height: 34)
                .background(.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 3) {
                Text(facilityID ?? "Facility")
                    .font(.headline)
                Text("\(productCount) products · \(ndcCount) linked NDCs")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)
        }
        .padding(.vertical, 4)
    }
}

private struct NDCProductRow: View {
    let product: Product
    let usageCount: Int

    private var ndcPreview: String {
        guard !product.linkedNDCs.isEmpty else { return "No linked NDCs" }
        return product.linkedNDCs.prefix(3).joined(separator: ", ")
    }

    private var strengthDisplay: String {
        let value = product.strength.formatted(.number.precision(.fractionLength(0...3)))
        return "\(value) \(product.strengthUnit.rawValue)"
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text(product.name)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                Text(ndcPreview)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(product.linkedNDCs.isEmpty ? .tertiary : .secondary)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    Label(strengthDisplay, systemImage: "scalemass")
                    if let importedRxCUI = product.importedRxCUI {
                        Label(importedRxCUI, systemImage: "tray.and.arrow.down")
                    }
                    if usageCount > 0 {
                        Label("Used", systemImage: "lock.fill")
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            Text("\(product.linkedNDCs.count)")
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(minWidth: 28)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(.secondary.opacity(0.10), in: Capsule())
        }
        .contentShape(Rectangle())
    }
}

private struct NDCProductEditor: View {
    let product: Product?
    let facilityID: String?
    let store: CompoundingStore

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var name: String
    @State private var linkedNDCs: [String]
    @State private var strength: String
    @State private var strengthUnit: QuantityUnit
    @State private var mlConcentration: String
    @State private var importedRxCUI: String
    @State private var importedTTY: String

    init(product: Product?, facilityID: String?, store: CompoundingStore) {
        self.product = product
        self.facilityID = facilityID
        self.store = store
        _name = State(initialValue: product?.name ?? "")
        _linkedNDCs = State(initialValue: product?.linkedNDCs ?? [])
        _strength = State(initialValue: product?.strength.formatted(.number.precision(.fractionLength(0...3))) ?? "")
        _strengthUnit = State(initialValue: product?.strengthUnit ?? .unitless)
        _mlConcentration = State(initialValue: product?.mlConcentration?.formatted(.number.precision(.fractionLength(0...3))) ?? "")
        _importedRxCUI = State(initialValue: product?.importedRxCUI ?? "")
        _importedTTY = State(initialValue: product?.importedTTY ?? "")
    }

    private var normalizedNDCs: [String] {
        var seen = Set<String>()
        return linkedNDCs.compactMap { value in
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            let key = ndcMatchKeys(for: trimmed).sorted().first ?? trimmed
            guard seen.insert(key).inserted else { return nil }
            return trimmed
        }
    }

    private var parsedStrength: Double? {
        Double(strength.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private var parsedConcentration: Double? {
        let trimmed = mlConcentration.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return Double(trimmed)
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !normalizedNDCs.isEmpty
            && parsedStrength != nil
            && facilityID != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Product") {
                    TextField("Name", text: $name)
                    HStack {
                        TextField("Strength", text: $strength)
                        Picker("Unit", selection: $strengthUnit) {
                            ForEach(QuantityUnit.allCases, id: \.self) { unit in
                                Text(unit.rawValue).tag(unit)
                            }
                        }
                        .labelsHidden()
                        .frame(maxWidth: 160)
                    }
                    TextField("mL concentration", text: $mlConcentration)
                }

                Section("NDCs") {
                    NDCListEditor(ndcs: $linkedNDCs)
                        .frame(minHeight: 160)
                        .listRowInsets(EdgeInsets())
                }

                Section("Import Metadata") {
                    TextField("RxCUI", text: $importedRxCUI)
                    TextField("TTY", text: $importedTTY)
                }
            }
            .navigationTitle(product == nil ? "Add NDC Product" : "Edit NDC Product")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!canSave)
                }
            }
        }
    }

    private func save() {
        guard let facilityID, let parsedStrength else { return }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedRxCUI = importedRxCUI.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedTTY = importedTTY.trimmingCharacters(in: .whitespacesAndNewlines)

        let target = product ?? Product(
            name: trimmedName,
            linkedNDCs: [],
            facilityID: facilityID,
            strength: parsedStrength,
            strengthUnit: strengthUnit
        )

        if product == nil {
            modelContext.insert(target)
        }

        target.name = trimmedName
        target.linkedNDCs = normalizedNDCs
        target.facilityID = facilityID
        target.strength = parsedStrength
        target.strengthUnit = strengthUnit
        target.mlConcentration = parsedConcentration
        target.importedRxCUI = trimmedRxCUI.isEmpty ? nil : trimmedRxCUI
        target.importedTTY = trimmedTTY.isEmpty ? nil : trimmedTTY
        if target.importedAt == nil, target.importedRxCUI != nil {
            target.importedAt = .now
        }

        try? modelContext.save()
        store.writeToSupabase { writer in
            try await writer.upsertProduct(target)
        }
        dismiss()
    }
}
