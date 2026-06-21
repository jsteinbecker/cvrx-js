import SwiftUI
import SwiftData

struct AddLabelersSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var isImporting = false
    @State private var errorMessage: String?
    @State private var importedCount: Int?
    
    @Query(sort: \Labeler.labelerCode)
    private var allLabelers: [Labeler]

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text("Add Labelers to Database")
                    .font(.title)
                    .padding(5)
                Button {
                    Task { await importLabelers() }
                } label: {
                    if isImporting {
                        ProgressView()
                    } else {
                        if (allLabelers.count == 0) {
                            Text("Import")
                        } else {
                            Text("Update")
                        }
                    }
                }
                .disabled(isImporting)
                Text("Current Environment")
                    .font(.title3)
                Text("Total Labeler Count: \(allLabelers.count)")

                if let importedCount {
                    Text("Imported \(importedCount) labelers.")
                        .foregroundStyle(.secondary)
                }
                if let errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                        .font(.callout)
                }
            }
            .padding()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .disabled(isImporting)
                }
            }
        }
    }

    @MainActor
    private func importLabelers() async {
        isImporting = true
        errorMessage = nil
        importedCount = nil

        do {
            let labelers = try await importLabelerData()
            for labeler in labelers {
                modelContext.insert(labeler)
            }
            try modelContext.save()
            importedCount = labelers.count
        } catch {
            errorMessage = error.localizedDescription
        }

        isImporting = false
    }
}
