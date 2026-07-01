//
//  DoseSizeSelection.swift
//  cvrx
//
//  Created by Josh Steinbecker on 6/30/26.
//

import Foundation

// MARK: - Result types

struct DoseSizeSelection {
    struct SelectedUnit {
        let product: Product
        let count: Int
    }

    /// Which products to use and how many units of each.
    let combination: [SelectedUnit]
    /// Total amount actually delivered, in the ordered dose's unit.
    let totalDelivered: Decimal
    /// totalDelivered - orderedDose (always >= 0).
    let waste: Decimal
    /// Total number of individual units (vials/tablets/etc.) used.
    let unitCount: Int
}

enum DoseSizeSelectionError: Error {
    case noSizesProvided
    case invalidDose
    /// A candidate size's unit dimension doesn't match the ordered dose's
    /// dimension (e.g. trying to fill a mL order with a mg-only product).
    case incompatibleUnits(Product)
    /// No combination of the given sizes can reach or exceed the ordered dose
    /// within the search bound.
    case noAchievableCombination
}

// MARK: - Selector

enum DoseSizeSelector {

    /// Selects which manufactured product sizes to use to fulfill
    /// `orderedDose`, minimizing waste first, then minimizing the total
    /// number of units used.
    ///
    /// Works with decimal doses/strengths (e.g. 1.5 g, 0.5 mL) by scaling
    /// values to integer "ticks" internally, then scaling back for the
    /// result. All candidate sizes must share the ordered unit's dimension
    /// (mass, volume, activity, etc.) — cross-dimension conversion (e.g.
    /// mg -> mL via concentration) is a separate concern and isn't handled
    /// here.
    ///
    /// - Parameters:
    ///   - orderedDose: The dose amount to fulfill, in `orderedUnit`.
    ///   - orderedUnit: The unit the dose is expressed in.
    ///   - sizes: Candidate manufactured sizes (unlimited supply assumed —
    ///     see note at bottom of file for the limited-stock variant).
    ///   - maxDecimalPlaces: Caps how many fractional digits are honored when
    ///     scaling to integer ticks. Higher values allow finer precision but
    ///     grow the DP search space. 6 comfortably covers mcg-level dosing
    ///     off of gram-scale orders.
    static func select(
        orderedDose: Decimal,
        orderedUnit: QuantityUnit,
        sizes: [Product],
        maxDecimalPlaces: Int = 6
    ) throws -> DoseSizeSelection {

        guard !sizes.isEmpty else { throw DoseSizeSelectionError.noSizesProvided }
        guard orderedDose > 0 else { throw DoseSizeSelectionError.invalidDose }

        // Convert every candidate's strength into the ordered dose's unit so
        // we're comparing like-for-like (e.g. a 500 mg product against a
        // 1.5 g order).
        var strengthsInOrderedUnit: [(product: Product, strength: Decimal)] = []
        for product in sizes {
            guard product.strengthUnit.dimension == orderedUnit.dimension else {
                throw DoseSizeSelectionError.incompatibleUnits(product)
            }
            let baseStrength = product.strength * product.strengthUnit.toBaseFactor
            let converted = baseStrength / orderedUnit.toBaseFactor
            strengthsInOrderedUnit
                .append( (product, converted) as! ( product: Product, strength: Decimal ) )
        }

        // --- Scale decimals to integers ("ticks") ---
        let allValues = [orderedDose] + strengthsInOrderedUnit.map(\.strength)
        let scale = decimalScale(for: allValues, maxDecimalPlaces: maxDecimalPlaces)

        let orderedTicks = ticks(orderedDose, scale: scale)
        let ticksByProductId: [UUID: Int] = Dictionary(
            uniqueKeysWithValues: strengthsInOrderedUnit.map {
                ($0.product.id, ticks($0.strength, scale: scale))
            }
        )
        let productsById: [UUID: Product] = Dictionary(
            uniqueKeysWithValues: sizes.map { ($0.id, $0) }
        )

        let sizeTicks = ticksByProductId.filter { $0.value > 0 }
        guard let minTicks = sizeTicks.values.min(), orderedTicks > 0 else {
            throw DoseSizeSelectionError.noAchievableCombination
        }

        // Waste can never exceed (minTicks - 1): worst case, use only the
        // smallest size repeatedly. This bounds the DP search.
        let maxSum = orderedTicks + minTicks - 1
        guard maxSum > 0 else { throw DoseSizeSelectionError.noAchievableCombination }

        // dp[S] = min units needed for an exact sum of S ticks.
        // choice[S] = product id last used to reach S optimally.
        var dp = [Int](repeating: Int.max, count: maxSum + 1)
        var choice = [UUID?](repeating: nil, count: maxSum + 1)
        dp[0] = 0

        for sum in 1...maxSum {
            for (productId, size) in sizeTicks {
                guard size <= sum else { continue }
                let prev = dp[sum - size]
                guard prev != Int.max, prev + 1 < dp[sum] else { continue }
                dp[sum] = prev + 1
                choice[sum] = productId
            }
        }

        // Step 1: minimize waste — first achievable sum >= orderedTicks.
        // dp already holds the min unit count for that sum, so step 2
        // (minimize units) falls out of the same pass.
        guard let bestSum = (orderedTicks...maxSum).first(where: { dp[$0] != Int.max }) else {
            throw DoseSizeSelectionError.noAchievableCombination
        }

        // Reconstruct which sizes were used.
        var countsById: [UUID: Int] = [:]
        var remaining = bestSum
        while remaining > 0 {
            guard let productId = choice[remaining], let size = ticksByProductId[productId] else {
                throw DoseSizeSelectionError.noAchievableCombination
            }
            countsById[productId, default: 0] += 1
            remaining -= size
        }

        let combination = countsById.compactMap { productId, count -> DoseSizeSelection.SelectedUnit? in
            guard let product = productsById[productId] else { return nil }
            return .init(product: product, count: count)
        }

        let totalDelivered = Decimal(bestSum) / Decimal(scale)

        return DoseSizeSelection(
            combination: combination,
            totalDelivered: totalDelivered,
            waste: totalDelivered - orderedDose,
            unitCount: dp[bestSum]
        )
    }

    // MARK: - Decimal <-> tick helpers

    /// Smallest power-of-10 scale that makes every given Decimal an integer,
    /// capped at `maxDecimalPlaces` to keep the DP array bounded even if a
    /// value has a long or imprecise decimal expansion.
    private static func decimalScale(for values: [Decimal], maxDecimalPlaces: Int) -> Int {
        var neededPlaces = 0
        for value in values {
            // Decimal.exponent is the power of 10 the mantissa is scaled by;
            // negative exponent means fractional digits (e.g. 1.5 -> -1).
            let places = max(0, -value.exponent)
            neededPlaces = max(neededPlaces, places)
        }
        neededPlaces = min(neededPlaces, maxDecimalPlaces)
        return Int(pow(10.0, Double(neededPlaces)))
    }

    private static func ticks(_ value: Decimal, scale: Int) -> Int {
        var scaled = value * Decimal(scale)
        var rounded = Decimal()
        NSDecimalRound(&rounded, &scaled, 0, .plain)
        return NSDecimalNumber(decimal: rounded).intValue
    }
}

// MARK: - Usage with MockData

// let result = try DoseSizeSelector.select(
//     orderedDose: 1.5,
//     orderedUnit: .g,
//     sizes: [MockData.vanco1g, MockData.vanco500mg]
// )
// for unit in result.combination {
//     print("\(unit.count) x \(unit.product.name) (\(unit.product.strength) \(unit.product.strengthUnit))")
// }
// print("Delivered: \(result.totalDelivered) \(orderedUnit), waste: \(result.waste), units used: \(result.unitCount)")

// MARK: - Note: limited lot stock

// This assumes unlimited supply of each size, which is right for a
// *catalog-level* size decision (i.e. "would we ever use these three
// vials"). If you instead want to select against actual on-hand
// CompoundUtilizedLot quantities, cap each product's usable count by
// available stock and switch the inner DP loop to iterate `sum` in
// decreasing order per product-size (bounded/0-1 knapsack style) so no
// product is used more than its stock allows. Happy to write that variant
// if/when you're wiring this to live lot data instead of the formulary.
