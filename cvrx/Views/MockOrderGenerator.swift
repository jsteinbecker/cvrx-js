//
//  MockOrderGenerator.swift
//  cvrx
//
//  Created by Josh Steinbecker on 6/13/26.
//

import SwiftUI
import SwiftData
import Foundation


@MainActor
struct OrderGeneratorButton: View {
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        Button("Generate New Order") {
            MockData.makeSampleOrders(into: modelContext, count: 1)
        }
    }
}
