//
//  NDCListEditor.swift
//  cvrx
//
//  macOS-style "table + add/remove segmented control" editor for a plain
//  `[String]` list of NDC codes — e.g. `Product.linkedNDCs`. Wired to
//  NDCParser, so typed input is normalized/validated live and ambiguous
//  10-digit NDCs surface a picker rather than silently trusting the
//  best-guess config. The labeler name (looked up from the 5-digit prefix
//  via LabelerCodeLookup) is shown on a secondary line.
//
//  Usage:
//
//      NDCListEditor(ndcs: $product.linkedNDCs)
//          .frame(height: 220)
//
//  Unlike the NDCEntity-backed variant, this stores canonical 5-4-2 billing
//  strings directly in the bound array — no SwiftData insert/delete, so no
//  modelContext is required. Rows are keyed by a stable internal identity so
//  editing a value doesn't scramble focus or draft state.
//

import SwiftUI

struct NDCListEditor: View {
    @Binding var ndcs: [String]

    // Stable per-row identity, decoupled from the string value (which
    // changes as the user types and on normalization). Kept in sync with
    // `ndcs` by index.
    @State private var rowIDs: [UUID] = []

    @State private var selection: Set<UUID> = []
    @State private var draftText: [UUID: String] = [:]
    @State private var invalidRowIDs: Set<UUID> = []
    @State private var ambiguousResults: [UUID: NDCParseResult] = [:]
    @State private var placeholderIDs: Set<UUID> = []
    @FocusState private var focusedRowID: UUID?

    var body: some View {
        VStack(spacing: 0) {
            // MARK: Table
            List(selection: $selection) {
                ForEach(Array(rowIDs.enumerated()), id: \.element) { index, id in
                    rowView(index: index, id: id)
                        .tag(id)
                }
            }
            .listStyle(.inset(alternatesRowBackgrounds: true))
            .environment(\.defaultMinListRowHeight, 30)
            .onDeleteCommand(perform: removeSelected)

            Divider()

            // MARK: Footer (+ / - segmented control)
            HStack(spacing: 0) {
                footerButton(systemName: "plus", action: addRow)
                Divider().frame(height: 12)
                footerButton(systemName: "minus", action: removeSelected, disabled: selection.isEmpty)
                Spacer()
                if !ndcs.isEmpty {
                    Text("\(ndcs.count) NDC\(ndcs.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.trailing, 8)
                }
            }
            .frame(height: 22)
            .background(.thinMaterial)
        }
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(Color.gray.opacity(0.35), lineWidth: 1)
        )
        .onChange(of: focusedRowID) { oldValue, newValue in
            if let old = oldValue, old != newValue {
                commit(id: old)
            }
        }
        .onAppear(perform: syncRowIDs)
        // If the bound array changes from outside (e.g. reset on load), keep
        // the id list length in step. Value edits we make ourselves don't
        // change the count, so this stays quiet during normal typing.
        .onChange(of: ndcs.count) { _, _ in syncRowIDs() }
    }

    // MARK: Row identity bookkeeping

    /// Ensure `rowIDs` has exactly one stable id per element of `ndcs`.
    private func syncRowIDs() {
        if rowIDs.count < ndcs.count {
            rowIDs.append(contentsOf: (0..<(ndcs.count - rowIDs.count)).map { _ in UUID() })
        } else if rowIDs.count > ndcs.count {
            rowIDs.removeLast(rowIDs.count - ndcs.count)
        }
    }

    // MARK: Row rendering

    @ViewBuilder
    private func rowView(index: Int, id: UUID) -> some View {
        let isPlaceholder = placeholderIDs.contains(id)
        let isInvalid = invalidRowIDs.contains(id)

        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 6) {
                TextField(isPlaceholder ? "Enter NDC" : "", text: bindingForRow(index: index, id: id))
                    .textFieldStyle(.plain)
                    .font(.system(.body, design: .monospaced))
                    .focused($focusedRowID, equals: id)
                    .foregroundStyle(isInvalid ? .red : .primary)
                    .onSubmit { commit(id: id) }

                if isInvalid {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                        .help("Not a recognizable NDC — expects 10–11 digits, optionally dash-separated")
                } else if let result = ambiguousResults[id] {
                    ambiguityMenu(index: index, id: id, result: result)
                }
            }

            // Secondary line: labeler name (looked up by 5-digit labeler
            // prefix). Shown for committed, valid, unambiguous rows.
            if !isPlaceholder, !isInvalid, ambiguousResults[id] == nil,
               index < ndcs.count {
                secondaryLine(for: ndcs[index])
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func secondaryLine(for value: String) -> some View {
        if let name = LabelerCodeLookup.name(forNDC: value) {
            Text(name)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    /// Inline menu shown when a bare 10-digit NDC is genuinely ambiguous
    /// between legacy segment configurations — every candidate is offered.
    @ViewBuilder
    private func ambiguityMenu(index: Int, id: UUID, result: NDCParseResult) -> some View {
        Menu {
            ForEach(Array(zip(NDCConfiguration.allCases, result.candidates)), id: \.0) { config, candidate in
                Button("\(config.rawValue): \(NDCParser.billingFormatted(candidate))") {
                    apply(candidate: candidate, index: index, id: id)
                }
            }
        } label: {
            Image(systemName: "questionmark.circle.fill")
                .font(.caption2)
                .foregroundStyle(.yellow)
        }
        .menuStyle(.borderlessButton)
        .frame(width: 16)
        .help("10-digit NDC is ambiguous between legacy formats — using best guess; tap to pick the correct one")
    }

    // MARK: Draft text binding

    private func bindingForRow(index: Int, id: UUID) -> Binding<String> {
        Binding(
            get: {
                if let draft = draftText[id] { return draft }
                return index < ndcs.count ? ndcs[index] : ""
            },
            set: { draftText[id] = $0 }
        )
    }

    // MARK: Commit / parse

    private func commit(id: UUID) {
        guard let draft = draftText[id] else { return }
        guard let index = rowIDs.firstIndex(of: id) else { return }
        defer { draftText[id] = nil }

        guard !draft.trimmingCharacters(in: .whitespaces).isEmpty else {
            // Left blank — drop a never-committed placeholder row entirely.
            if placeholderIDs.contains(id) {
                removeRow(id: id)
            }
            return
        }

        do {
            let result = try NDCParser.normalize(draft)
            if index < ndcs.count {
                ndcs[index] = billing(from: result)
            }
            invalidRowIDs.remove(id)
            placeholderIDs.remove(id)
            ambiguousResults[id] = result.isAmbiguous ? result : nil
        } catch {
            invalidRowIDs.insert(id)
        }
    }

    /// Canonical 5-4-2 billing string from a parse result's segments.
    private func billing(from result: NDCParseResult) -> String {
        "\(result.labelerCode)-\(result.productCode)-\(result.packageCode)"
    }

    private func apply(candidate normalized11: String, index: Int, id: UUID) {
        if index < ndcs.count {
            ndcs[index] = NDCParser.billingFormatted(normalized11)
        }
        ambiguousResults[id] = nil
    }

    // MARK: Footer buttons

    @ViewBuilder
    private func footerButton(systemName: String, action: @escaping () -> Void, disabled: Bool = false) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 22, height: 21)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.35 : 1)
        .contentShape(Rectangle())
    }

    // MARK: Mutations

    private func addRow() {
        let id = UUID()
        ndcs.append("")
        rowIDs.append(id)
        placeholderIDs.insert(id)
        draftText[id] = ""
        selection = [id]
        focusedRowID = id
    }

    private func removeSelected() {
        guard !selection.isEmpty else { return }
        for id in selection { removeRow(id: id) }
        selection.removeAll()
    }

    private func removeRow(id: UUID) {
        guard let index = rowIDs.firstIndex(of: id) else { return }
        if index < ndcs.count { ndcs.remove(at: index) }
        rowIDs.remove(at: index)
        draftText[id] = nil
        invalidRowIDs.remove(id)
        ambiguousResults[id] = nil
        placeholderIDs.remove(id)
    }
}

// MARK: - Preview

#Preview {
    struct PreviewHost: View {
        @State private var ndcs: [String] = [
            "00069-2587-68",
            "63739-0555-10",
            "00093-7146-01"
        ]

        var body: some View {
            NDCListEditor(ndcs: $ndcs)
                .frame(width: 340, height: 200)
                .padding()
        }
    }

    return PreviewHost()
}
