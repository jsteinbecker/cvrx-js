// Views.swift
// All SwiftUI views, matching the HTML/CSS structure and visual design.

import SwiftUI
import SwiftData


// MARK: - Palette

private extension Color {
    static let brand = Color.accentColor
    static let pillBlue = Color.blue
    static let pillGreen = Color.green
    static let pillAmber = Color.orange
    static let pillGrp = Color.brand
    static let border = Color.primary.opacity(0.10)
    static let rowBg1 = Color.rxCardBackground
    static let rowBg2 = Color.brand.opacity(0.045)
    static let rowBg3 = Color.secondary.opacity(0.055)
    static let accent1 = Color.brand.opacity(0.28)
    static let accent2 = Color.brand.opacity(0.42)
    static let accent3 = Color.brand.opacity(0.56)
    static let searchBarBackground = Color.rxCardBackground
    static let searchControlBackground = Color.secondary.opacity(0.10)
    static let searchInsetBackground = Color.secondary.opacity(0.08)
}

// MARK: - Root app view

struct RxNormSearchView: View {
    @State var vm = SearchViewModel()
    @Environment(\.modelContext) var ctx

    var body: some View {
        VStack(spacing: 0) {
            SearchBarView(vm: vm)
            ConfigBarView(vm: vm)
            TabContentView(vm: vm)
        }
        .background(Color.rxGroupedBackground.ignoresSafeArea())
        .onAppear { vm.modelContext = ctx }
    }
}

// MARK: - Search bar

struct SearchBarView: View {
    @Bindable var vm: SearchViewModel

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            TextField("Drug name…", text: $vm.query)
                .textFieldStyle(.plain)
                .font(.body)
                .onChange(of: vm.query) { _, _ in vm.scheduleSearch() }
                .onSubmit { Task { await vm.doSearch() } }
            Button {
                Task { await vm.doSearch() }
            } label: {
                Image(systemName: "arrow.forward.circle.fill")
                    .font(.title3)
                    .symbolRenderingMode(.hierarchical)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.tint)
            .accessibilityLabel("Search")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.searchControlBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.searchBarBackground)
        .overlay(Divider(), alignment: .bottom)
    }
}

// MARK: - Config bar (TTY badges + toggles)

struct ConfigBarView: View {
    @Bindable var vm: SearchViewModel

    private let tty1: [TTY] = [.SCDF, .SBDF, .SCDFP, .SBDFP, .SCDG, .SBDG, .SCDGP]
    private let tty2: [TTY] = [.SCD, .SBD, .GPCK, .BPCK]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(tty1, id: \.self) { tty in
                    TTYBadge(tty: tty, active: vm.activeTTY1.contains(tty), style: .blue) {
                        if vm.activeTTY1.contains(tty) { vm.activeTTY1.remove(tty) }
                        else { vm.activeTTY1.insert(tty) }
                        if !vm.query.isEmpty { vm.scheduleSearch() }
                    }
                }
                Divider().frame(height: 20)
                ForEach(tty2, id: \.self) { tty in
                    TTYBadge(tty: tty, active: vm.activeTTY2.contains(tty), style: .green) {
                        if vm.activeTTY2.contains(tty) { vm.activeTTY2.remove(tty) }
                        else { vm.activeTTY2.insert(tty) }
                        if !vm.query.isEmpty { vm.scheduleSearch() }
                    }
                }
                Divider().frame(height: 20)
                MiniToggle(label: "SCD↔SBD", on: $vm.crossPop)
                    .onChange(of: vm.crossPop) { _, _ in if !vm.query.isEmpty { vm.scheduleSearch() } }
                MiniToggle(label: "Combos", on: $vm.includeCombos)
                    .onChange(of: vm.includeCombos) { _, _ in vm.applyNameFilter() }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .background(Color.searchBarBackground)
        .overlay(Divider(), alignment: .bottom)
    }
}

struct TTYBadge: View {
    let tty: TTY; let active: Bool; let style: BadgeStyle; let action: () -> Void
    enum BadgeStyle { case blue, green }
    var body: some View {
        Button(action: action) {
            Text(tty.rawValue)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 9).padding(.vertical, 5)
                .background(
                    active
                    ? (style == .blue ? Color.pillBlue.opacity(0.16) : Color.pillGreen.opacity(0.16))
                    : Color.secondary.opacity(0.10)
                )
                .foregroundStyle(active ? (style == .blue ? Color.pillBlue : Color.pillGreen) : Color.secondary)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(active ? Color.border : Color.clear, lineWidth: 1))
        }.buttonStyle(.plain)
    }
}

struct MiniToggle: View {
    let label: String; @Binding var on: Bool
    var body: some View {
        Button { on.toggle() } label: {
            HStack(spacing: 6) {
                Image(systemName: on ? "checkmark.circle.fill" : "circle")
                    .font(.caption)
                    .symbolRenderingMode(.hierarchical)
                Text(label).font(.caption.weight(.semibold))
            }
            .foregroundStyle(on ? Color.brand : Color.secondary)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(on ? Color.brand.opacity(0.14) : Color.secondary.opacity(0.10), in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Tab content

struct TabContentView: View {
    var vm: SearchViewModel
    @State private var tab: Int = 0

    var body: some View {
        VStack(spacing: 0) {
            Picker("View", selection: $tab) {
                Text("Results").tag(0)
                Text("Pipeline").tag(1)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color.rxCardBackground)
            .overlay(Divider(), alignment: .bottom)

            if tab == 0 {
                ResultsView(vm: vm)
            } else {
                PipelineView(vm: vm)
            }
        }
    }
}

struct TabButton: View {
    let title: String; let index: Int; @Binding var selected: Int
    var body: some View {
        Button { selected = index } label: {
            Text(title)
                .font(.system(size: 12))
                .padding(.horizontal, 12).padding(.vertical, 4)
                .foregroundStyle(selected == index ? Color.primary : Color.secondary)
                .overlay(alignment: .bottom) {
                    if selected == index { Color.brand.frame(height: 2) }
                }
        }.buttonStyle(.plain)
    }
}

// MARK: - Results view

struct ResultsView: View {
    var vm: SearchViewModel

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                StatusBarView(vm: vm)

                if !vm.dfgTree.isEmpty {
                    DFGFilterBarView(vm: vm)
                }

                switch vm.phase {
                case .idle:
                    EmptyStateView(text: "Enter a drug name to search")
                case .searching(let msg):
                    HStack(spacing: 6) {
                        ProgressView().scaleEffect(0.7)
                        Text(msg).font(.system(size: 11)).foregroundStyle(Color.secondary)
                    }.padding(12)
                case .noResults(let msg):
                    EmptyStateView(text: msg)
                case .error(let msg):
                    EmptyStateView(text: "Error: \(msg)")
                case .results:
                    ForestView(vm: vm)
                }
            }
            .padding(16)
        }
        .background(Color.rxGroupedBackground)
        .scrollDismissesKeyboard(.immediately)
    }
}

struct StatusBarView: View {
    var vm: SearchViewModel
    var body: some View {
        if !vm.statusText.isEmpty {
            HStack {
                Text(vm.statusText)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(Color.rxCardBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }
}

struct EmptyStateView: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .padding(28)
            .frame(maxWidth: .infinity)
            .background(Color.rxCardBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

// MARK: - DFG filter bar (segmented units)

struct DFGFilterBarView: View {
    var vm: SearchViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text("DOSE FORM GROUPS")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                Spacer()
                let allOn = vm.dfgTree.flatMap { $0.allKeys() }.allSatisfy { vm.selectedGroups.contains($0) }
                Button(allOn ? "clear all" : "select all") {
                    if allOn { vm.clearAllGroups() } else { vm.selectAllGroups() }
                }
                .font(.caption.weight(.semibold))
            }

            FlowLayout(spacing: 6) {
                ForEach(vm.dfgTree) { node in
                    SegmentedGroupUnit(node: node, vm: vm)
                }
            }
        }
        .padding(12)
        .background(Color.rxCardBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.border, lineWidth: 0.5)
        }
    }
}

struct SegmentedGroupUnit: View {
    let node: DFGNode; var vm: SearchViewModel

    var body: some View {
        HStack(spacing: 0) {
            SegButton(label: node.label, count: vm.dfgNodeCount(node), state: vm.dfgNodeState(node), isParent: true) {
                vm.toggleDFGSubtree(node)
            }
            if !node.children.isEmpty {
                Color.border.frame(width: 1)
                ForEach(Array(node.children.enumerated()), id: \.element.id) { idx, child in
                    if idx > 0 { Color.border.frame(width: 1) }
                    SegButton(label: child.label, count: vm.dfgNodeCount(child),
                              state: vm.selectedGroups.contains(child.key) ? .on : .off,
                              isParent: false) {
                        vm.toggleDFGSubtree(child)
                    }
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Color.border, lineWidth: 1))
    }
}

struct SegButton: View {
    let label: String; let count: Int; let state: DFGState; let isParent: Bool; let action: () -> Void

    private var bg: Color {
        switch state {
        case .on: return Color.brand
        case .mixed: return Color.brand.opacity(0.18)
        case .off: return isParent ? Color.secondary.opacity(0.12) : Color.clear
        }
    }
    private var fg: Color {
        switch state {
        case .on: return .white
        case .mixed: return Color.brand
        case .off: return isParent ? Color.primary : Color.secondary
        }
    }
    private var check: String {
        switch state { case .on: return "✓ "; case .mixed: return "– "; case .off: return "" }
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 3) {
                Text(check + label)
                    .font(.caption.weight(isParent ? .semibold : .regular))
                Text("\(count)")
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(state == .on ? Color.white.opacity(0.22) : Color.secondary.opacity(0.14))
                    .clipShape(Capsule())
            }
            .foregroundStyle(fg)
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(bg)
        }.buttonStyle(.plain)
    }
}

// MARK: - Forest (concept tree)

struct ForestView: View {
    var vm: SearchViewModel

    var body: some View {
        LazyVStack(spacing: 0, pinnedViews: []) {
            ForEach(vm.forestRoots) { root in
                ConceptCardView(root: root, vm: vm)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.border, lineWidth: 0.5)
        }
    }
}

struct ConceptCardView: View {
    let root: ForestNode; var vm: SearchViewModel
    @State private var expanded = false

    var allRows: [ForestNode] { flattenForest(root) }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(allRows) { node in
                ConceptRowView(node: node, vm: vm)
                if node !== allRows.last {
                    Divider().padding(.leading, 0.75 + CGFloat(node.depth + 1) * 1.1 * 16)
                        .opacity(0.5)
                }
            }
        }
    }
}

struct ConceptRowView: View {
    @State var node: ForestNode
    var vm: SearchViewModel
    @State private var isExpanded = false

    private var indentPad: CGFloat { 12 + CGFloat(node.depth) * 17.6 }
    private var accentColor: Color {
        switch node.depth {
        case 1: return Color.accent1
        case 2: return Color.accent2
        case 3: return Color.accent3
        default: return .clear
        }
    }
    private var rowBG: Color {
        switch node.depth {
        case 1: return Color.rowBg1; case 2: return Color.rowBg2; case 3: return Color.rowBg3
        default: return Color.rxCardBackground
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.easeOut(duration: 0.15)) { isExpanded.toggle() }
                if isExpanded { vm.loadNDCs(for: node) }
            } label: {
                HStack(alignment: .center, spacing: 6) {
                    if node.depth > 0 {
                        accentColor.frame(width: 2)
                    }
                    ConceptNameView(name: node.concept.name, depth: node.depth)
                    Spacer(minLength: 4)
                    Link(node.concept.rxcui,
                         destination: URL(string: "https://rxnav.nlm.nih.gov/REST/rxcui/\(node.concept.rxcui)/properties.json")!)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Color.secondary.opacity(0.6))
                    TTYPillView(tty: node.concept.tty)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Color.secondary.opacity(0.6))
                        .rotationEffect(isExpanded ? .degrees(180) : .zero)
                        .animation(.easeOut(duration: 0.15), value: isExpanded)
                }
                .padding(.leading, indentPad)
                .padding(.trailing, 12)
                .padding(.vertical, 9)
                .background(rowBG)
            }
            .buttonStyle(.plain)

            if isExpanded {
                NDCPanelView(node: node, vm: vm)
                    .padding(.leading, indentPad)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}

// MARK: - Concept name display (per-depth progressive disclosure)

struct ConceptNameView: View {
    let name: String; let depth: Int

    var body: some View {
        let label = displayLabel(for: name, depth: depth)
        Group {
            switch label {
            case .doseForm(let ing, let form):
                HStack(spacing: 0) {
                    Text(ing).font(.system(size: 12, weight: .semibold)).foregroundStyle(Color.primary)
                    if !form.isEmpty {
                        Text(" · ").font(.system(size: 11)).foregroundStyle(Color.secondary.opacity(0.6))
                        Text(form).font(.system(size: 11)).foregroundStyle(Color.secondary)
                    }
                }
            case .strength(let s):
                Text(s)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.primary)
            case .quantity(let q):
                Text(q)
                    .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.pillAmber)
            case .brand(let b):
                Text(b)
                    .font(.system(size: 11.5, weight: .medium).italic())
                    .foregroundStyle(Color.brand)
            case .raw(let r):
                Text(r).font(.system(size: 12)).foregroundStyle(Color.primary)
            }
        }
        .lineLimit(2)
        .multilineTextAlignment(.leading)
    }
}

// MARK: - TTY pill

struct TTYPillView: View {
    let tty: TTY
    private var fg: Color {
        switch tty.pillColor { case .blue: return .pillBlue; case .green: return .pillGreen; case .amber: return .pillAmber }
    }
    private var bg: Color {
        switch tty.pillColor {
        case .blue: return Color.pillBlue.opacity(0.16)
        case .green: return Color.pillGreen.opacity(0.16)
        case .amber: return Color.pillAmber.opacity(0.16)
        }
    }
    var body: some View {
        Text(tty.rawValue)
            .font(.system(size: 10))
            .fontWeight(.semibold)
            .foregroundStyle(fg)
            .padding(.horizontal, 6).padding(.vertical, 3)
            .background(bg)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(fg.opacity(0.4), lineWidth: 0.5))
    }
}

// MARK: - NDC panel

struct NDCPanelView: View {
    let node: ForestNode; var vm: SearchViewModel

    @ViewBuilder private var content: some View {
        switch node.ndcState {
        case .idle:
            EmptyView()
        case .loading:
            HStack(spacing: 5) {
                ProgressView().scaleEffect(0.6)
                Text("Loading…").font(.caption).foregroundStyle(.secondary)
            }.padding(.vertical, 8)
        case .loaded:
            if let result = node.ndcResult {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Text("\(result.ndcs.count) NDC\(result.ndcs.count == 1 ? "" : "s")")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 7).padding(.vertical, 3)
                            .background(Color.secondary.opacity(0.10))
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(Color.border))
                            .foregroundStyle(.secondary)
                        Text(result.path)
                            .font(.caption2.italic())
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 8)
                        Button {
                            vm.importProduct(from: node)
                        } label: {
                            Label(vm.importingNodeID == node.id ? "Importing" : "Import", systemImage: "tray.and.arrow.down")
                        }
                        .font(.caption.weight(.semibold))
                        .controlSize(.small)
                        .buttonStyle(.bordered)
                        .disabled(result.ndcs.isEmpty || vm.importingNodeID == node.id)
                    }
                    if !vm.importSummary.isEmpty {
                        Text(vm.importSummary)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    FlowLayout(spacing: 5) {
                        ForEach(result.ndcs, id: \.self) { ndc in
                            NDCChipView(ndc: ndc, vm: vm)
                        }
                    }
                }
                .padding(.vertical, 10)
                .padding(.trailing, 12)
            }
        case .failed(let msg):
            Text("Failed: \(msg)")
                .font(.caption).foregroundStyle(.red)
                .padding(.vertical, 8)
        }
    }

    var body: some View {
        content
            .padding(.bottom, 4)
            .background(Color.searchInsetBackground)
    }
}

struct NDCChipView: View {
    let ndc: String; @Bindable var vm: SearchViewModel
    @State private var isSelected = false

    var body: some View {
        Button {
            isSelected.toggle()
            if isSelected { Task { await vm.loadNDCInfo(ndc) } }
        } label: {
            Text(ndc)
                .font(.system(size: 11, design: .monospaced))
                .fontWeight(.medium)
                .padding(.horizontal, 7).padding(.vertical, 4)
                .background(isSelected ? Color.brand.opacity(0.16) : Color.rxCardBackground)
                .foregroundStyle(isSelected ? Color.brand : Color.primary)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(isSelected ? Color.brand.opacity(0.7) : Color.border, lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .sheet(item: $vm.selectedNDC) { info in
            NDCPopoverSheet(info: info)
                .presentationDetents([.height(160)])
                .presentationDragIndicator(.visible)
        }
    }
}

struct NDCPopoverSheet: View {
    let info: NDCInfo
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(info.ndc)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
            if let name = info.productName {
                Text(name).font(.system(size: 14)).foregroundStyle(Color.primary)
            } else {
                Text("Name unavailable").font(.system(size: 14).italic()).foregroundStyle(Color.secondary)
            }
            if let status = info.status {
                let active = info.marketed ?? false
                Text(status + (active ? " · marketed" : " · not marketed"))
                    .font(.system(size: 11))
                    .foregroundStyle(status == "ACTIVE" ? Color.pillGreen : .red)
            }
            Spacer()
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.rxGroupedBackground)
    }
}

// MARK: - Pipeline view

struct PipelineView: View {
    var vm: SearchViewModel

    private var pipeline: String {
        let t1 = vm.activeTTY1.map(\.rawValue).joined(separator: " ")
        let t2 = vm.activeTTY2.map(\.rawValue).joined(separator: " ")
        return """
For SCDG / SBDG / SCDGP (dose form group TTYs):
  concept.rxcui
    → getRelatedByType(\(t1))
    → getRelatedByType(SCD+SBD+GPCK+BPCK)
    → filter: single-ingredient only
    → getNDCs per SCD + pool + dedup

For SCDF / SBDF (dose form TTYs):
  concept.rxcui
    → getRelatedByType(SCD+SBD+GPCK+BPCK)
    → filter: single-ingredient only
    → getNDCs per SCD + pool + dedup

For SCD / SBD / GPCK / BPCK (direct):
  concept.rxcui → getNDCs directly
  \(vm.crossPop ? "+ cross-populate SCD↔SBD" : "")

tty group 1: \(t1)
tty group 2: \(t2)
"""
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let url = vm.rxMixURL() {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(url.absoluteString)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(Color.secondary)
                            .textSelection(.enabled)
                        HStack(spacing: 8) {
                            Button("Copy") {
                                #if canImport(UIKit)
                                UIPasteboard.general.string = url.absoluteString
                                #else
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(url.absoluteString, forType: .string)
                                #endif
                            }
                            .font(.caption)
                            .controlSize(.small)
                            .buttonStyle(.bordered)
                            Link("Open in RxMix", destination: url)
                                .font(.caption)
                        }
                    }
                    .padding(12)
                    .background(Color.rxCardBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(Color.border, lineWidth: 0.5)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("TRAVERSAL STRATEGY")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                    Text(pipeline)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Color.primary)
                        .textSelection(.enabled)
                }
                .padding(12)
                .background(Color.rxCardBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.border, lineWidth: 0.5)
                }
            }
            .padding(16)
        }
        .background(Color.rxGroupedBackground)
    }
}

// MARK: - Flow layout (wrapping HStack for badges/NDCs)

struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let width = proposal.width ?? 0
        var x: CGFloat = 0; var y: CGFloat = 0; var rowH: CGFloat = 0
        for sub in subviews {
            let s = sub.sizeThatFits(.unspecified)
            if x + s.width > width && x > 0 { y += rowH + spacing; x = 0; rowH = 0 }
            rowH = max(rowH, s.height); x += s.width + spacing
        }
        return CGSize(width: width, height: y + rowH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        var x = bounds.minX; var y = bounds.minY; var rowH: CGFloat = 0
        for sub in subviews {
            let s = sub.sizeThatFits(.unspecified)
            if x + s.width > bounds.maxX && x > bounds.minX { y += rowH + spacing; x = bounds.minX; rowH = 0 }
            sub.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            rowH = max(rowH, s.height); x += s.width + spacing
        }
    }
}
