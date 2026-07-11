import SwiftUI
import SwiftData

struct AddLabelersSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let store: CompoundingStore

    @State private var operation: DatabaseOperation?
    @State private var errorMessage: String?
    @State private var importSummary: LabelerSyncSummary?
    @State private var showDeleteConfirmation = false

    @Query(sort: \Labeler.name)
    private var allLabelers: [Labeler]

    private var isWorking: Bool {
        operation != nil
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text("Sync Labelers")
                    .font(.title)
                    .padding(5)

                Button {
                    Task { await importLabelers() }
                } label: {
                    if operation == .importing { ProgressView() }
                    else { Text(allLabelers.isEmpty ? "Import" : "Update") }
                }
                .disabled(isWorking)

                if !allLabelers.isEmpty {
                    Button("Delete All", role: .destructive) {
                        showDeleteConfirmation = true
                    }
                    .disabled(isWorking)
                }

                Divider()

                Text("Current Environment")
                    .font(.title3)

                Text("Total Labeler Count: \(allLabelers.count)")

                if let importSummary {
                    Text(importSummary.description)
                        .foregroundStyle(.secondary)
                        .font(.callout)
                }

                if operation == .deleting {
                    ProgressView("Deleting labelers…")
                }

                if let errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                        .font(.callout)
                        .multilineTextAlignment(.center)
                }
            }
            .padding()
            .interactiveDismissDisabled(isWorking)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .disabled(isWorking)
                }
            }
            .confirmationDialog(
                "Delete all \(allLabelers.count) labelers?",
                isPresented: $showDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete All", role: .destructive) {
                    deleteAllLabelers()
                }

                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This cannot be undone.")
            }
        }
    }

    @MainActor
    private func importLabelers() async {
        guard operation == nil else {
            return
        }

        operation = .importing
        errorMessage = nil
        importSummary = nil

        defer {
            operation = nil
        }

        do {
            importSummary = try await store.syncLabelersFromSupabase()
        } catch is CancellationError {
            modelContext.rollback()
            errorMessage = "The import was cancelled."
        } catch {
            modelContext.rollback()
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func deleteAllLabelers() {
        guard operation == nil else {
            return
        }

        operation = .deleting
        errorMessage = nil
        importSummary = nil

        defer {
            operation = nil
        }

        do {
            try modelContext.delete(model: Labeler.self)
            try modelContext.save()
            store.refreshLabelerLookupCache()
        } catch {
            modelContext.rollback()
            errorMessage = error.localizedDescription
        }
    }
}

private enum DatabaseOperation {
    case importing
    case deleting
}

