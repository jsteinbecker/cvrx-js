//
//  CSPEvent.swift
//  cvrx
//
//  Created by Josh Steinbecker on 6/25/26.
//
import SwiftData
import Foundation


enum CSPStatusType: String, Codable, Hashable, CaseIterable {
    case pending
    case staging
    case preparing
    case waitingForRPh
    case waitingForCPhT
    case remediating
    case approved
    case rejected
    case cancelled
}


@Model
final class CSPEvent {
    @Attribute(.unique) var id: UUID
    var cspOrder: CSPOrder
    var timestamp: Date
    var status: CSPStatusType
    var statusChanged: Bool
    var user: User

    init(
        id: UUID = UUID(),
        cspOrder: CSPOrder,
        timestamp: Date,
        status: CSPStatusType,
        statusChanged: Bool = false,
        user: User
    ) {
        self.id = id
        self.cspOrder = cspOrder
        self.timestamp = timestamp
        self.status = status
        self.statusChanged = statusChanged
        self.user = user
    }
    
    func isAuthorized() -> Bool {
        if (self.statusChanged && [.waitingForCPhT, .approved, .rejected].contains(self.status)) {
            if (self.user.role != .rph) { return false }
        } else {
            return true
        }
        return true
    }
}
