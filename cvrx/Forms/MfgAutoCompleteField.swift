import SwiftData
import SwiftUI

struct MfgAutoCompleteField: View {
    @Binding var text: String

    let isFocused: Bool
    let onSubmit: () -> Void
    let onSelect: (String) -> Void
    let onEscape: () -> Void

    @Query(filter: #Predicate<Labeler> { $0.hidden != true }, sort: \Labeler.name)
    private var labelers: [Labeler]

    @State private var highlightedIndex: Int? = nil

    private var matches: [String] {
        guard isFocused else { return [] }

        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return [] }

        return labelers
            .map(\.name)
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
    }

    var body: some View {
        TextField("", text: $text)
            .textFieldStyle(.roundedBorder)
            .frame(minWidth: 70)
            .submitLabel(.done)
            .onSubmit(onSubmit)
            .onChange(of: text) { highlightedIndex = nil }
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
                onEscape()
                return .handled
            }
            .overlay(alignment: .topLeading) {
                if !matches.isEmpty {
                    dropdown
                }
            }
    }

    private var dropdown: some View {
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
            }
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.primary.opacity(0.4), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.15), radius: 6, x: 0, y: 3)
        }
    }

    private func select(_ name: String) {
        text = name
        highlightedIndex = nil
        onSelect(name)
    }
}
