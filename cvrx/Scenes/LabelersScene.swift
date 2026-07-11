import SwiftUI
import SwiftData

struct LabelersScene: View {
    let store: CompoundingStore

    @Query(filter: #Predicate<Labeler> { $0.hidden != true }, sort: \Labeler.name)
    private var visibleLabelers: [Labeler]

    @Query(filter: #Predicate<Labeler> { $0.hidden == true }, sort: \Labeler.name)
    private var hiddenLabelers: [Labeler]

    @Query private var allLabelers: [Labeler]

    @State private var showingAddLabelersSheet = false
    @State private var searchText = ""

    private var filteredVisible: [Labeler] {
        guard !searchText.isEmpty else { return visibleLabelers }
        return visibleLabelers.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.fullName.localizedCaseInsensitiveContains(searchText) ||
            $0.labelerCodes.contains { $0.localizedCaseInsensitiveContains(searchText) }
        }
    }

    private var filteredHidden: [Labeler] {
        guard !searchText.isEmpty else { return hiddenLabelers }
        return hiddenLabelers.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.fullName.localizedCaseInsensitiveContains(searchText) ||
            $0.labelerCodes.contains { $0.localizedCaseInsensitiveContains(searchText) }
        }
    }

    var body: some View {
        List {
            if !filteredVisible.isEmpty {
                Section("Active") {
                    ForEach(filteredVisible) { labeler in
                        LabelerRow(labeler: labeler)
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button {
                                    withAnimation { labeler.hidden = true }
                                } label: {
                                    Label("Hide", systemImage: "eye.slash")
                                }
                                .tint(.orange)
                            }
                    }
                }
            }

            if !filteredHidden.isEmpty {
                Section {
                    ForEach(filteredHidden) { labeler in
                        HiddenLabelerRow(labeler: labeler)
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button {
                                    withAnimation { labeler.hidden = false }
                                } label: {
                                    Label("Restore", systemImage: "eye")
                                }
                                .tint(.blue)
                            }
                    }
                } header: {
                    Label("Hidden", systemImage: "eye.slash")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .listStyle(.inset)
        .overlay {
            if allLabelers.isEmpty {
                ContentUnavailableView(
                    "No Labelers",
                    systemImage: "building.2",
                    description: Text("No manufacturers imported yet.")
                )
            } else if filteredVisible.isEmpty && filteredHidden.isEmpty {
                ContentUnavailableView.search(text: searchText)
            }
        }
        .searchable(text: $searchText, prompt: "Search labelers")
        .navigationTitle("Labelers")
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button {
                    showingAddLabelersSheet = true
                } label: {
                    Image(systemName: "link")
                }
            }
        }
        .sheet(isPresented: $showingAddLabelersSheet) {
            AddLabelersSheet(store: store)
        }
    }
}

private struct LabelerRow: View {
    let labeler: Labeler

    private var codesDisplay: String {
        labeler.labelerCodes.joined(separator: ", ")
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(labeler.name)
                Text(codesDisplay)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 5)
            Text(labeler.fullName)
                .foregroundStyle(.secondary)
                .font(.subheadline)
        }
    }
}

private struct HiddenLabelerRow: View {
    let labeler: Labeler

    private var codesDisplay: String {
        labeler.labelerCodes.joined(separator: ", ")
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(labeler.name)
                    .foregroundStyle(.tertiary)
                Text(codesDisplay)
                    .font(.caption.monospaced())
                    .foregroundStyle(.quaternary)
            }
            Spacer(minLength: 5)
            Text(labeler.fullName)
                .foregroundStyle(.quaternary)
                .font(.subheadline)
        }
    }
}
