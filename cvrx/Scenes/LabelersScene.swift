import SwiftUI
import SwiftData



struct LabelersScene: View {
    @Environment(\.modelContext)
    var modelContext
    
    @Query(filter:
            #Predicate<Labeler> { $0.hidden != true }, sort: \Labeler.name)
    private var visibleLabelers: [Labeler]

    @Query(filter:
            #Predicate<Labeler> { $0.hidden == true }, sort: \Labeler.name)
    private var hiddenLabelers: [Labeler]

    @Query private var allLabelers: [Labeler]

    private let visibleSectionID = "visible_section"
    private let hiddenSectionID = "hidden_section"

    private var visibleAlphabetIndexes: [String] {
        Array(Set(visibleLabelers.compactMap { $0.name.first?.uppercased() })).sorted()
    }

    var body: some View {
        ScrollViewReader { proxy in
            ZStack(alignment: .trailing) {
                VStack(alignment: .leading, spacing: 0) {
                    header

                    List {
                        Section {
                            ForEach(visibleLabelers) { labeler in
                                LabelerRow(labeler: labeler)
                                    // Anchor ID combining the first letter for alphabetical jump
                                    .id("visible_\(labeler.name.first?.uppercased() ?? "")")
                                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                        Button {
                                            withAnimation { labeler.hidden = true }
                                        } label: {
                                            Label("Hide", systemImage: "eye.slash")
                                        }
                                        .tint(.orange)
                                    }
                            }
                        } header: {
                            Text("Active").id(visibleSectionID)
                        }

                        if !hiddenLabelers.isEmpty {
                            Section {
                                ForEach(hiddenLabelers) { labeler in
                                    HiddenLabelerRow(labeler: labeler)
                                        .id("hidden_\(labeler.name.first?.uppercased() ?? "")")
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
                                    .id(hiddenSectionID)
                            }
                        }
                    }
                    .overlay {
                        if allLabelers.isEmpty {
                            ContentUnavailableView(
                                "No Labelers",
                                systemImage: "building.2",
                                description: Text("No manufacturers imported yet.")
                            )
                        }
                    }
                }
                
                if !visibleLabelers.isEmpty {
                    alphabetIndexSidebar(proxy: proxy)
                }
            }
            .navigationTitle("Labelers")
            .toolbar {
                if !hiddenLabelers.isEmpty {
                    ToolbarItem(placement: .automatic) {
                        Button {
                            withAnimation(.easeInOut) {
                                proxy.scrollTo(hiddenSectionID, anchor: .top)
                            }
                        } label: {
                            Label("Go to Hidden", systemImage: "eye.slash.circle")
                        }
                    }
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading) {
            Text("Labelers")
                .font(.title)
                .fontWeight(.bold)
            Text("\(visibleLabelers.count) records\(hiddenLabelers.isEmpty ? "" : " · \(hiddenLabelers.count) hidden")")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
    }

    // Sidebar View Component for A-Z Indexing
    @ViewBuilder
    private func alphabetIndexSidebar(proxy: ScrollViewProxy) -> some View {
        VStack(spacing: 4) {
            ForEach(visibleAlphabetIndexes, id: \.self) { letter in
                Button {
                    withAnimation {
                        proxy.scrollTo("visible_\(letter)", anchor: .top)
                    }
                } label: {
                    Text(letter)
                        .font(.caption2.bold())
                        .foregroundColor(.blue)
                        .frame(width: 18, height: 18)
                }
            }
        }
        .padding(.vertical, 8)
        .background(Color(.black).opacity(0.1))
        .shadow(radius: 3)
        .cornerRadius(8)
        .padding(.trailing, 4)
    }
}

private struct LabelerRow: View {
    let labeler: Labeler

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(labeler.name)
                Text(labeler.labelerCode)
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

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(labeler.name)
                    .foregroundStyle(.tertiary)
                Text(labeler.labelerCode)
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
