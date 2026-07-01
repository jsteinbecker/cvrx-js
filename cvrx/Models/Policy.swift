//
//  Policy.swift
//  cvrx
//
//  Created by Josh Steinbecker on 6/29/26.
//

import Foundation
import SwiftData


enum StorageCondition: String, Codable, Equatable {
    case refrigerated
    case frozen
    case controlledRoomTemperature
    case unknown
    case excessiveHeat
}


@Model
final class BUDMultidosePolicy {
    var id: UUID = UUID()
    var priorToEntryStorage: [StorageCondition]
    var postEntryStorage: [StorageCondition]
    var bud: TimeInterval
    var createdBy: User
    var createdAt: Date = Date()
    var updatedBy: User?
    var approvedBy: User?
    
    init(
        id: UUID,
        priorToEntryStorage: [StorageCondition],
        postEntryStorage: [StorageCondition],
        bud: TimeInterval,
        createdBy: User,
        createdAt: Date
    ) {
        self.id = id
        self.priorToEntryStorage = priorToEntryStorage
        self.postEntryStorage = postEntryStorage
        self.bud = bud
        self.createdBy = createdBy
        self.createdAt = createdAt
        self.updatedBy = nil
        self.approvedBy = nil
    }
}
