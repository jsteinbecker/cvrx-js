//
//  OrdersTab.swift
//  cvrx
//
//  Created by Josh Steinbecker on 5/27/26.
//
import Foundation
import SwiftUI

struct OrdersTab: View {
    let store: CompoundingStore

    // Read from environment rather than re-declaring ownership. Using
    // @StateObject with an injected parameter is wrong: @StateObject only
    // initializes once on the first render and would detach this view's
    // copy from the app-level source of truth.
    @EnvironmentObject var user: User

    var body: some View {
        NavigationStack {
            List(store.orders) { order in
                NavigationLink(value: order.id) {
                    OrderRow(order: order)
                }
            }
            .navigationTitle("Compounding Orders")
            .navigationDestination(for: CompoundOrder.ID.self) { orderID in
                if let order = store.orderBinding(for: orderID) {
                    OrderDetailScene(order: order, store: store)
                } else {
                    ContentUnavailableView("Order Not Found", systemImage: "exclamationmark.triangle")
                }
            }
        }
    }
}
