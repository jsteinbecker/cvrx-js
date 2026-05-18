//
//  VerificationTab.swift
//  cvrx
//
//  Created by Josh Steinbecker on 5/27/26.
//

import SwiftUI

/// Dedicated verification queue. Independent of the compounding/capture flow:
/// the user enters verification only by tapping an item here.
struct VerificationTab: View {
    let store: CompoundingStore
    @EnvironmentObject var user: User

    var body: some View {
        NavigationStack {
            Group {
                if store.ordersReadyForVerification.isEmpty {
                    ContentUnavailableView(
                        "Nothing to Verify",
                        systemImage: "tray",
                        description: Text("Compounds marked ready for verification will appear here.")
                    )
                } else {
                    List(store.ordersReadyForVerification) { order in
                        NavigationLink(value: order.id) {
                            VerifyQueueRow(order: order)
                        }
                    }
                }
            }
            .navigationTitle("Verification Queue")
            .navigationDestination(for: CompoundOrder.ID.self) { orderID in
                if let order = store.orderBinding(for: orderID) {
                    VerifyScene(order: order, store: store)
                } else {
                    ContentUnavailableView("Order Not Found", systemImage: "exclamationmark.triangle")
                }
            }
        }
    }
}

struct VerifyQueueRow: View {
    let order: CompoundOrder

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: order.remediation != nil ? "arrow.uturn.left.circle.fill" : "photo.stack")
                .font(.title2)
                .foregroundStyle(order.remediation != nil ? .purple : .orange)
                .frame(width: 40)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(order.orderNumber)
                        .font(.headline)
                    if order.remediation != nil {
                        Text("RE-VERIFY")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.purple))
                    }
                }
                Text(order.medicationName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text("\(order.captures.count) image\(order.captures.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }
}

