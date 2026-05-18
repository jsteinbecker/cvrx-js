//
//  User.swift
//  cvrx
//
//  Created by Josh Steinbecker on 5/25/26.
//
import Foundation
import Combine

class User: ObservableObject, Codable, Hashable {
    @Published var id: UUID
    @Published var username: String
    @Published var deptId: String
    @Published var name: String
    @Published var role: UserRole

    enum CodingKeys: String, CodingKey {
        case id
        case username
        case deptId
        case name
        case role
    }
    
    init(id: UUID = UUID(), username: String, deptId: String, name: String, role: UserRole) {
        self.id = id
        self.username = username
        self.deptId = deptId
        self.name = name
        self.role = role
    }

    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        username = try container.decode(String.self, forKey: .username)
        deptId = try container.decode(String.self, forKey: .deptId)
        name = try container.decode(String.self, forKey: .name)
        role = try container.decode(UserRole.self, forKey: .role)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(username, forKey: .username)
        try container.encode(deptId, forKey: .deptId)
        try container.encode(name, forKey: .name)
        try container.encode(role, forKey: .role)
    }

    static func == (lhs: User, rhs: User) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

enum UserRole: String, Codable, Equatable, Hashable {
    case cpht = "Technician"
    case hdcpht = "Hazardous Drug Technician"
    case rph = "RPh"
    
    var canScan: Bool {
        switch self {
        case .cpht, .hdcpht:
            return true
        case .rph:
            return true
        }
    }
    
    var canVerify: Bool {
        switch self {
        case .rph:
            return true
        default:
            return false
        }
    }
    
    var canRemediate: Bool {
        switch self {
        case .cpht, .hdcpht:
            return true
        case .rph:
            return true
        }
    }
    
    var canOverrideScan: Bool {
        switch self {
        case .rph, .hdcpht:
            return true
        case .cpht:
            return false
        }
    }
}
