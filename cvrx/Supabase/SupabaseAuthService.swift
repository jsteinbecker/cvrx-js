import Foundation

actor SupabaseAuthService {
    enum AuthError: LocalizedError {
        case notConfigured
        case missingSession
        case profileNotFound
        case facilityNotFound

        var errorDescription: String? {
            switch self {
            case .notConfigured:
                return "Supabase is not configured."
            case .missingSession:
                return "Supabase did not return a valid session."
            case .profileNotFound:
                return "No active profile exists for this Supabase user."
            case .facilityNotFound:
                return "This user does not belong to the requested facility."
            }
        }
    }

    private let config: SupabaseConfig
    private var session: SupabaseSession?
    private var selectedFacilityID: UUID?

    init(config: SupabaseConfig) {
        self.config = config
    }

    func authenticate(username: String, password: String, facilityID: String) async throws -> User {
        let normalizedFacilityID = Self.normalizedLoginValue(facilityID)
        let login = username.trimmingCharacters(in: .whitespacesAndNewlines)

        let authResponse: SupabasePasswordAuthResponse = try await unauthenticatedClient.authRequest(
            path: "token?grant_type=password",
            method: .post,
            body: PasswordGrantRequest(email: login, password: password)
        )

        guard let accessToken = authResponse.accessToken else {
            throw AuthError.missingSession
        }

        session = SupabaseSession(accessToken: accessToken, refreshToken: authResponse.refreshToken)
        let authenticatedClient = SupabaseRESTClient(config: config, accessToken: accessToken)

        let profiles: [ProfileRow] = try await authenticatedClient.restRequest(
            path: "profiles?select=id,username,dept_id,display_name,role,active&id=eq.\(authResponse.user.id.uuidString)&active=eq.true",
            responseType: [ProfileRow].self
        )

        guard let profile = profiles.first else {
            throw AuthError.profileNotFound
        }

        let memberships: [FacilityMembershipRow] = try await authenticatedClient.restRequest(
            path: "facility_memberships?select=facility_id,facilities(id,abv)&user_id=eq.\(profile.id.uuidString)",
            responseType: [FacilityMembershipRow].self
        )

        guard let membership = memberships.first(where: { row in
            Self.normalizedLoginValue(row.facilities?.abv ?? "") == normalizedFacilityID
        }) else {
            throw AuthError.facilityNotFound
        }

        selectedFacilityID = membership.facilityID

        return User(
            id: profile.id,
            username: profile.username,
            deptId: profile.deptID,
            facilityID: membership.facilities?.abv ?? normalizedFacilityID,
            passwordHash: "supabase-auth",
            name: profile.displayName,
            role: profile.role,
            active: profile.active
        )
    }

    func makeAuthenticatedClient() throws -> (client: SupabaseRESTClient, facilityID: UUID) {
        guard let session, let selectedFacilityID else {
            throw AuthError.missingSession
        }

        return (
            SupabaseRESTClient(config: config, accessToken: session.accessToken),
            selectedFacilityID
        )
    }

    func makeRealtimeConnectionInfo() throws -> SupabaseRealtimeConnectionInfo {
        guard let session, let selectedFacilityID else {
            throw AuthError.missingSession
        }

        return SupabaseRealtimeConnectionInfo(
            config: config,
            accessToken: session.accessToken,
            facilityID: selectedFacilityID
        )
    }

    func signOut() {
        session = nil
        selectedFacilityID = nil
    }

    private var unauthenticatedClient: SupabaseRESTClient {
        SupabaseRESTClient(config: config)
    }

    private static func normalizedLoginValue(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

private struct PasswordGrantRequest: Encodable {
    let email: String
    let password: String
}

private struct SupabasePasswordAuthResponse: Decodable {
    let accessToken: String?
    let refreshToken: String?
    let user: AuthUser

    private enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case user
    }
}

private struct SupabaseSession: Sendable {
    let accessToken: String
    let refreshToken: String?
}

private struct AuthUser: Decodable {
    let id: UUID
}

private struct ProfileRow: Decodable {
    let id: UUID
    let username: String
    let deptID: String
    let displayName: String
    let role: UserRole
    let active: Bool

    private enum CodingKeys: String, CodingKey {
        case id
        case username
        case deptID = "dept_id"
        case displayName = "display_name"
        case role
        case active
    }
}

private struct FacilityMembershipRow: Decodable {
    let facilityID: UUID
    let facilities: FacilityReferenceRow?

    private enum CodingKeys: String, CodingKey {
        case facilityID = "facility_id"
        case facilities
    }
}

private struct FacilityReferenceRow: Decodable {
    let id: UUID
    let abv: String
}
