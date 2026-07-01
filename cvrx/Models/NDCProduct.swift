//
//  NDCProduct.swift
//  cvrx
//
//  Created by Josh Steinbecker on 6/20/26.
//

import SwiftData

enum Dimension: Codable, Hashable, Equatable {
    case mass
    case volume
    case activity
    case charge
    case time
}

struct RxUnit: Codable, Hashable, Equatable {
    var name: String
    var id: String { name }
    var inlineDisplay: String
    var dimension: Dimension
}

struct RxMeasurement: Equatable {
    var magnitude: Double
    var unit: RxUnit
}

extension RxMeasurement: Codable {
    private enum CodingKeys: String, CodingKey {
        case magnitude
        case unit
    }
    
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            magnitude: try container.decode(Double.self, forKey: .magnitude),
            unit: try container.decode(RxUnit.self, forKey: .unit)
        )
    }
}

enum AdminRoute: String, Hashable, Codable {
    case inj
    case oral
    case im
    case sq
    case top
}

@Model
class NDCProduct {
    var ndc9: String
    var name: String
    var brandedName: String?
    var routes: [AdminRoute]
    var unitSize: RxMeasurement
    var isMultiDose: Bool = false

    init(
        ndc9: String,
        name: String,
        brandedName: String? = nil,
        routes: [AdminRoute],
        unitSize: RxMeasurement,
        isMultiDose: Bool
    ) {
        self.ndc9 = ndc9
        self.name = name
        self.brandedName = brandedName
        self.routes = routes
        self.unitSize = unitSize
        self.isMultiDose = isMultiDose
    }
}


