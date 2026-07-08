//
//  Facility.swift
//  cvrx
//
//  Created by Josh Steinbecker on 6/22/26.
//

import SwiftData
import Foundation


enum BedNamingRule: String, Codable {
    case alpha      // A, B, C...
    case numeric    // 1, 2, 3...
    case dotNumeric // .1, .2, .3...

    func label(for index: Int) -> String {
        switch self {
        case .alpha:
            let letters = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
            if index < 26 {
                return String(letters[letters.index(letters.startIndex, offsetBy: index)])
            } else {
                let first = index / 26 - 1
                let second = index % 26
                return label(for: first) + label(for: second)
            }
        case .numeric:
            return "\(index + 1)"
        case .dotNumeric:
            return ".\(index + 1)"
        }
    }
}


@Model
final class Facility {
    @Attribute(.unique)
    var id: UUID
    var name: String
    var abv: String
    var bedNamingRule: BedNamingRule = BedNamingRule.alpha

    init(id: UUID = UUID(), name: String, abv: String, bedNamingRule: BedNamingRule = .alpha) {
        self.id = id
        self.name = name
        self.abv = abv
        self.bedNamingRule = bedNamingRule
    }
}


enum FloorType: String, Codable {
    /// Med/Surg
    case ms
    /// Progressive Care
    case pc
    /// Intensive Care
    case ic
    /// Observation
    case ob
    /// Outpatient
    case op
}


@Model
final class FloorUnit {
    @Attribute(.unique)
    var id: UUID
    var name: String
    var facility: Facility
    var floorType: FloorType
    var bedsPerRoom: Int = 1

    @Relationship(deleteRule: .cascade, inverse: \Room.floor)
    var rooms: [Room] = []

    func updateBedsPerRoom(n: Int, context: ModelContext) {
        guard n > 0 else { return }
        bedsPerRoom = n
        let rule = facility.bedNamingRule

        for room in rooms {
            let beds = room.beds
            let currentCount = beds.count
            if currentCount < n {
                for i in currentCount..<n {
                    let bed = Bed(id: UUID(), name: rule.label(for: i), room: room)
                    context.insert(bed)
                }
            } else if currentCount > n {
                beds.dropFirst(n)
                    .filter { $0.patient == nil }
                    .forEach { context.delete($0) }
            }
        }
    }

    init(
        id: UUID = UUID(),
        name: String,
        facility: Facility,
        floorType: FloorType,
        bedsPerRoom: Int = 1,
        rooms: [Room] = []
    ) {
        self.id = id
        self.name = name
        self.facility = facility
        self.floorType = floorType
        self.bedsPerRoom = bedsPerRoom
        self.rooms = rooms
    }
}


@Model
final class Room {
    @Attribute(.unique) var id: UUID
    var floor: FloorUnit
    var name: String

    @Relationship(deleteRule: .cascade, inverse: \Bed.room)
    var beds: [Bed] = []

    init(id: UUID, floor: FloorUnit, name: String) {
        self.id = id
        self.floor = floor
        self.name = name
    }
}

enum OccupancyStatus: String, Codable {
    case occupied
    case vacant
    case reserved
    case unavailable

    var displayName: String {
        switch self {
        case .occupied:    "Occupied"
        case .vacant:      "Vacant"
        case .reserved:    "Reserved"
        case .unavailable: "Unavailable"
        }
    }
}


@Model
final class Bed {
    @Attribute(.unique) var id: UUID
    var name: String
    var room: Room
    var status: OccupancyStatus = OccupancyStatus.vacant
    var patient: Patient?

    init(id: UUID, name: String, room: Room, occupancyStatus: OccupancyStatus = .vacant) {
        self.id = id
        self.name = name
        self.room = room
        self.status = occupancyStatus
    }
}
