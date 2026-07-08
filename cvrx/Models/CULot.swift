//
//  CULot.swift
//  cvrx
//
//  Created by Josh Steinbecker on 7/7/26.
//

import SwiftData
import Foundation


/// CSP Utilized Lot
/// A record of the Manufacturered Products Lot/Exp data utilized in a specific CSP compound.
@Model
final class CULot {
    var id: UUID = UUID()
    var ndcProduct: NDCProduct
    var lot: String
    var exp: Date
    
    init(id: UUID, ndcProduct: NDCProduct, lot: String, exp: Date) {
        self.id = id
        self.ndcProduct = ndcProduct
        self.lot = lot
        self.exp = exp
    }
}
