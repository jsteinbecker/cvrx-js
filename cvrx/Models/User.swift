import Foundation
import SwiftUI


struct User: Identifiable, Codable, Hashable {
    var id: UUID
    var username: String
    var deptId: String
    var name: String
    var role: UserRole
    var active: Bool

    init(id: UUID = UUID(), username: String, deptId: String, name: String, role: UserRole) {
        self.id = id
        self.username = username
        self.deptId = deptId
        self.name = name
        self.role = role
        self.active = true
    }
}

// MARK: - Environment Key

struct CurrentUserKey: EnvironmentKey {
    static let defaultValue: User = User(username: "unknown", deptId: "", name: "Unknown", role: .cpht)
}

extension EnvironmentValues {
    var currentUser: User {
        get { self[CurrentUserKey.self] }
        set { self[CurrentUserKey.self] = newValue }
    }
}

// MARK: - Role

enum UserRole: String, Codable, Equatable, Hashable {
    case cpht = "Technician"
    case hdcpht = "Hazardous Drug Technician"
    case rph = "RPh"

    var canScan: Bool { true }

    var canVerify: Bool {
        switch self {
        case .rph: return true
        default: return false
        }
    }

    var canRemediate: Bool { true }

    var canOverrideScan: Bool {
        switch self {
        case .rph, .hdcpht: return true
        case .cpht: return false
        }
    }
}
