//
//  Patient.swift
//  cvrx
//
//  Created by Josh Steinbecker on 6/22/26.
//

import SwiftData
import Foundation


@Model
final class Patient {
    @Attribute(.unique) var id: UUID
    var name: String
    var floor: String
    var room: String
    var bed: String?
    var dob: Date?

    init(id: UUID = UUID(), name: String, floor: String, room: String, bed: String? = nil, dob: Date? = nil) {
        self.id = id
        self.name = name
        self.floor = floor
        self.room = room
        self.bed = bed
        self.dob = dob
    }
    
    func ageInYears(on date: Date = Date()) -> Double? {
            guard let dob else { return nil }
        return date.timeIntervalSince(dob) / (365.2425 * 24 * 60 * 60)
    }
    
    var initials: String {
        let nameParts = self.name.split(separator: " ")
        guard let first = nameParts.first?.first else { return "" }
        if nameParts.count > 1, let last = nameParts.last?.first {
            return "\(first)\(last)".uppercased()
        }
        return String(first).uppercased()
    }
}
