import Foundation
import SwiftData
import SwiftUI

@Model
final class User {
    @Attribute(.unique)
    var id: UUID

    var username: String
    var deptId: String
    var name: String
    var role: UserRole
    var active: Bool

    init(
        id: UUID = UUID(),
        username: String,
        deptId: String,
        name: String,
        role: UserRole,
        active: Bool = true
    ) {
        self.id = id
        self.username = username
        self.deptId = deptId
        self.name = name
        self.role = role
        self.active = active
    }
}

// MARK: - Codable

extension User: Codable {
    private enum CodingKeys: String, CodingKey {
        case id
        case username
        case deptId
        case name
        case role
        case active
    }

    convenience init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.init(
            id: try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID(),
            username: try container.decode(String.self, forKey: .username),
            deptId: try container.decode(String.self, forKey: .deptId),
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
        try container.encode(name, forKey: .name)
        try container.encode(role, forKey: .role)
        try container.encode(active, forKey: .active)
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

// MARK: - Role

enum UserRole: String, Codable, Hashable {
    case cpht = "cpht"
        case hdcpht = "hdcpht"
        case rph = "rph"

    var displayName: String {
        switch self {
        case .cpht: "Technician"
        case .hdcpht: "Hazardous Drug Technician"
        case .rph: "RPh"
        }
    }

    var canScan: Bool { true }

    var canVerify: Bool { self == .rph }

    var canRemediate: Bool { true }

    var canOverrideScan: Bool {
        switch self {
        case .rph, .hdcpht: true
        case .cpht: false
        }
    }
}
