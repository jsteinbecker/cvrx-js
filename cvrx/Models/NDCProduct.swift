//
//  NDCProduct.swift
//  cvrx
//
//  Created by Josh Steinbecker on 6/20/26.
//

import SwiftData


struct Measurement: Codable {
    var magnitude: Double
    var unit: String
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
    var unitSize: Measurement
    var isMultiDose: Bool = false
    
    init(
        ndc9: String,
        name: String,
        brandedName: String? = nil,
        routes: [AdminRoute],
        unitSize: Measurement,
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


