import CryptoKit
import Foundation
import SwiftData
import SwiftUI

@Model
final class User {
    @Attribute(.unique)
    var id: UUID

    var username: String
    var deptId: String
    var facilityID: String
    var passwordHash: String
    var name: String
    var role: UserRole
    var active: Bool

    init(
        id: UUID = UUID(),
        username: String,
        deptId: String,
        facilityID: String? = nil,
        password: String = "password",
        passwordHash: String? = nil,
        name: String,
        role: UserRole,
        active: Bool = true
    ) {
        self.id = id
        self.username = username
        self.deptId = deptId
        self.facilityID = facilityID ?? deptId
        self.passwordHash = passwordHash ?? User.passwordHash(for: password)
        self.name = name
        self.role = role
        self.active = active
    }

    static func passwordHash(for password: String) -> String {
        let data = Data(password.utf8)
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    func passwordMatches(_ password: String) -> Bool {
        passwordHash == User.passwordHash(for: password)
    }

    func matchesFacilityID(_ candidate: String) -> Bool {
        facilityID.normalizedLoginValue == candidate.normalizedLoginValue
    }
}

// MARK: - Codable

extension User: Codable {
    private enum CodingKeys: String, CodingKey {
        case id
        case username
        case deptId
        case facilityID
        case passwordHash
        case name
        case role
        case active
    }

    convenience init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let deptId = try container.decode(String.self, forKey: .deptId)
        self.init(
            id: try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID(),
            username: try container.decode(String.self, forKey: .username),
            deptId: deptId,
            facilityID: try container.decodeIfPresent(String.self, forKey: .facilityID) ?? deptId,
            passwordHash: try container.decodeIfPresent(String.self, forKey: .passwordHash),
            name: try container.decode(String.self, forKey: .name),
            role: try container.decode(UserRole.self, forKey: .role),
            active: try container.decodeIfPresent(Bool.self, forKey: .active) ?? true
        )
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(id, forKey: .id)
        try container.encode(username, forKey: .username)
        try container.encode(deptId, forKey: .deptId)
        try container.encode(facilityID, forKey: .facilityID)
        try container.encode(passwordHash, forKey: .passwordHash)
        try container.encode(name, forKey: .name)
        try container.encode(role, forKey: .role)
        try container.encode(active, forKey: .active)
    }
}

// MARK: - Login Helpers

extension String {
    var normalizedLoginValue: String {
        trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

// MARK: - Environment

private struct CurrentUserKey: EnvironmentKey {
    nonisolated(unsafe) static let defaultValue: User? = nil
}

extension EnvironmentValues {
    var currentUser: User? {
        get { self[CurrentUserKey.self] }
        set { self[CurrentUserKey.self] = newValue }
    }
}


enum UserRole: String, Codable, Hashable {
    case cpht = "cpht"
    case hdcpht = "hdcpht"
    case srcpht = "srcpht"
    case rph = "rph"

    var displayName: String {
        switch self {
        case .cpht: "Technician"
        case .hdcpht: "Hazardous Drug Technician"
        case .srcpht: "Senior Technician"
        case .rph: "RPh"
        }
    }

    var canScan: Bool { true }

    var canVerify: Bool { self == .rph }

    var canRemediate: Bool { true }

    var canOverrideScan: Bool {
        switch self {
        case .rph, .hdcpht, .srcpht: true
        case .cpht: false
        }
    }
}
