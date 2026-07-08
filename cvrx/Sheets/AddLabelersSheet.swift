import SwiftUI
import SwiftData

struct AddLabelersSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var operation: DatabaseOperation?
    @State private var errorMessage: String?
    @State private var importSummary: ImportSummary?
    @State private var showDeleteConfirmation = false

    @Query(sort: \Labeler.name)
    private var allLabelers: [Labeler]

    private var isWorking: Bool {
        operation != nil
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text("Add Labelers to Database")
                    .font(.title)
                    .padding(5)

                Button {
                    Task {
                        await importLabelers()
                    }
                } label: {
                    if operation == .importing {
                        ProgressView()
                    } else {
                        Text(allLabelers.isEmpty ? "Import" : "Update")
                    }
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
            let records = try await importLabelerData()
            let existingLabelers = try modelContext.fetch(
                FetchDescriptor<Labeler>()
            )

            var existingByKey: [String: Labeler] = [:]

            for labeler in existingLabelers {
                let key = labeler.name.normalizedLabelerKey

                if existingByKey[key] == nil {
                    existingByKey[key] = labeler
                }
            }

            var insertedCount = 0
            var updatedCount = 0
            var unchangedCount = 0

            for record in records {
                let key = record.name.normalizedLabelerKey

                if let existing = existingByKey[key] {
                    let normalizedCodes = Array(Set(record.codes)).sorted()

                    let hasChanges =
                        existing.name != record.name ||
                        existing.fullName != record.fullName ||
                        existing.labelerCodes != normalizedCodes

                    if hasChanges {
                        existing.name = record.name
                        existing.fullName = record.fullName
                        existing.labelerCodes = normalizedCodes
                        updatedCount += 1
                    } else {
                        unchangedCount += 1
                    }
                } else {
                    let labeler = Labeler(
                        name: record.name,
                        fullName: record.fullName,
                        labelerCodes: record.codes
                    )

                    modelContext.insert(labeler)
                    existingByKey[key] = labeler
                    insertedCount += 1
                }
            }

            try modelContext.save()

            importSummary = ImportSummary(
                inserted: insertedCount,
                updated: updatedCount,
                unchanged: unchangedCount
            )
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

private struct ImportSummary {
    let inserted: Int
    let updated: Int
    let unchanged: Int

    var description: String {
        [
            inserted == 1
                ? "Added 1 labeler"
                : "Added \(inserted) labelers",

            updated == 1
                ? "updated 1"
                : "updated \(updated)",

            unchanged == 1
                ? "1 unchanged"
                : "\(unchanged) unchanged"
        ]
        .joined(separator: ", ") + "."
    }
}

private extension String {
    var normalizedLabelerKey: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: .current
            )
    }
}
