import Foundation

struct SupabaseConfig: Sendable {
    let projectURL: URL
    let anonKey: String

    static var bundled: SupabaseConfig? {
        guard
            let rawURL = Bundle.main.object(forInfoDictionaryKey: "CVRXSupabaseURL") as? String,
            let rawAnonKey = Bundle.main.object(forInfoDictionaryKey: "CVRXSupabaseAnonKey") as? String
        else { return nil }

        let trimmedURL = rawURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedAnonKey = rawAnonKey.trimmingCharacters(in: .whitespacesAndNewlines)

        guard
            !trimmedURL.isEmpty,
            !trimmedAnonKey.isEmpty,
            !trimmedURL.contains("YOUR-SUPABASE"),
            !trimmedAnonKey.contains("YOUR-SUPABASE"),
            let projectURL = URL(string: trimmedURL)
        else { return nil }

        return SupabaseConfig(projectURL: projectURL, anonKey: trimmedAnonKey)
    }
}
