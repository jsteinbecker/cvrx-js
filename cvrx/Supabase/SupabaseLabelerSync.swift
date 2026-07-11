import Foundation
import SwiftData

struct SupabaseLabelerSyncService: Sendable {
    let authService: SupabaseAuthService

    func fetchLabelers() async throws -> [RemoteLabeler] {
        let authenticated = try await authService.makeAuthenticatedClient()
        return try await authenticated.client.restRequest(
            path: "labelers?select=name,full_name,labeler_codes,hidden&order=name.asc",
            responseType: [RemoteLabeler].self
        )
    }
}

struct RemoteLabeler: Decodable, Sendable {
    let name: String
    let fullName: String
    let labelerCodes: [String]
    let hidden: Bool?

    private enum CodingKeys: String, CodingKey {
        case name
        case fullName = "full_name"
        case labelerCodes = "labeler_codes"
        case hidden
    }

    var record: LabelerRecord {
        LabelerRecord(name: name, fullName: fullName, codes: labelerCodes)
    }
}

struct LabelerSyncSummary: Sendable {
    let inserted: Int
    let updated: Int
    let unchanged: Int
    let deleted: Int

    var description: String {
        [
            inserted == 1 ? "Added 1 labeler" : "Added \(inserted) labelers",
            updated == 1 ? "updated 1" : "updated \(updated)",
            unchanged == 1 ? "1 unchanged" : "\(unchanged) unchanged",
            deleted == 1 ? "deleted 1 stale labeler" : "deleted \(deleted) stale labelers"
        ]
        .joined(separator: ", ") + "."
    }
}

@MainActor
extension CompoundingStore {
    @discardableResult
    func syncLabelersFromSupabase(deleteMissing: Bool = true) async throws -> LabelerSyncSummary {
        guard let supabaseAuth else {
            throw SupabaseAuthService.AuthError.notConfigured
        }

        let remoteLabelers = try await SupabaseLabelerSyncService(authService: supabaseAuth).fetchLabelers()
        return try replaceLocalLabelers(with: remoteLabelers, deleteMissing: deleteMissing)
    }

    func refreshLabelerLookupCache() {
        let labelers = (try? modelContext.fetch(FetchDescriptor<Labeler>())) ?? []
        LabelerCodeLookup.replaceRecords(with: labelers)
    }

    private func replaceLocalLabelers(with remoteLabelers: [RemoteLabeler], deleteMissing: Bool) throws -> LabelerSyncSummary {
        let existingLabelers = try modelContext.fetch(FetchDescriptor<Labeler>())
        var existingByKey: [String: Labeler] = [:]

        for labeler in existingLabelers {
            let key = labeler.name.normalizedLabelerKey
            if existingByKey[key] == nil {
                existingByKey[key] = labeler
            }
        }

        var incomingKeys = Set<String>()
        var insertedCount = 0
        var updatedCount = 0
        var unchangedCount = 0
        var deletedCount = 0

        for remoteLabeler in remoteLabelers {
            let record = remoteLabeler.record.normalized
            let key = record.name.normalizedLabelerKey
            incomingKeys.insert(key)

            if let existing = existingByKey[key] {
                let hidden = remoteLabeler.hidden ?? existing.hidden
                let hasChanges =
                    existing.name != record.name ||
                    existing.fullName != record.fullName ||
                    existing.labelerCodes != record.codes ||
                    existing.hidden != hidden

                if hasChanges {
                    existing.name = record.name
                    existing.fullName = record.fullName
                    existing.labelerCodes = record.codes
                    existing.hidden = hidden
                    updatedCount += 1
                } else {
                    unchangedCount += 1
                }
            } else {
                let labeler = Labeler(
                    name: record.name,
                    fullName: record.fullName,
                    labelerCodes: record.codes,
                    hidden: remoteLabeler.hidden ?? false
                )
                modelContext.insert(labeler)
                existingByKey[key] = labeler
                insertedCount += 1
            }
        }

        if deleteMissing {
            for labeler in existingLabelers where !incomingKeys.contains(labeler.name.normalizedLabelerKey) {
                modelContext.delete(labeler)
                deletedCount += 1
            }
        }

        try modelContext.save()
        refreshLabelerLookupCache()

        return LabelerSyncSummary(
            inserted: insertedCount,
            updated: updatedCount,
            unchanged: unchangedCount,
            deleted: deletedCount
        )
    }
}

private extension LabelerRecord {
    var normalized: LabelerRecord {
        LabelerRecord(
            name: name.normalizedLabelerText,
            fullName: fullName.normalizedLabelerText,
            codes: Array(Set(codes.map { $0.normalizedLabelerText }.filter { !$0.isEmpty })).sorted()
        )
    }
}

private extension String {
    var normalizedLabelerText: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var normalizedLabelerKey: String {
        normalizedLabelerText.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: .current
        )
    }
}
