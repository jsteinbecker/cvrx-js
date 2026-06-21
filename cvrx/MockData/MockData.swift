import Foundation
import SwiftData
import SwiftUI

enum MockData {

    // MARK: - Users
    //
    // User is @Observable (reference type). Use factories so each caller gets
    // a fresh User, letting the app root take ownership via @State.

    static func makeUserJts() -> User {
        User(username: "jts", deptId: "NCMC", name: "Josh Steinbecker", role: .hdcpht)
    }

    static func makeUserMsm() -> User {
        User(username: "msm", deptId: "NCMC", name: "Molly Sweeney-McKeil", role: .rph)
    }

    // MARK: - Sample order generation
    //
    // Picks from a catalog of clinically-coherent templates and randomizes the
    // order "envelope" (order number, patient, due time) plus per-lot data
    // (lot string, barcode, expiration). Recipe text and component makeup come
    // from the template so the data stays plausible — the randomness is
    // intentionally *semi*, not pure noise.
    //
    // Pass a `seed` for deterministic output (SwiftUI previews, unit tests).
    // Leave it nil for fresh data on every launch.

    @MainActor
    @discardableResult
    static func makeSampleOrders(into: ModelContext ,count: Int = 6, seed: UInt64? = nil) -> [CompoundOrder] {
        var rng = SeededGenerator(seed: seed ?? UInt64.random(in: .min ... .max))

        let builders = templateBuilders
        var pool: [@MainActor (inout SeededGenerator) -> CompoundSpec] = []
        var orders: [CompoundOrder] = []
        orders.reserveCapacity(count)

        for _ in 0..<count {
            // Reshuffle when the pool empties so templates spread out before repeating.
            if pool.isEmpty { pool = builders.shuffled(using: &rng) }
            let spec = pool.removeLast()(&rng)

            let newOrder = CompoundOrder(
                    orderNumber: randomOrderNumber(&rng),
                    patient: randomPatient(&rng),
                    medicationName: spec.medicationName,
                    finalContainer: spec.finalContainer,
                    route: spec.route,
                    dueTime: randomDueTime(&rng),
                    recipeText: spec.recipeText,
                    components: spec.components
                )
            into.insert(newOrder)
            orders.append(newOrder)
            
        }
        return orders
    }
}

// MARK: - Order templates

private extension MockData {

    /// Everything a template needs to define; the envelope is filled by the generator.
    struct CompoundSpec {
        var medicationName: String
        var finalContainer: String
        var route: String
        var recipeText: String
        var components: [CompoundComponent]
    }

    @MainActor
    static var templateBuilders: [@MainActor (inout SeededGenerator) -> CompoundSpec] {
        [   vancomycinIVPB,
            cefepimeIVPush,
            avycazInfusion,
            zosynIVPB,
            meropenemIVPB,
            ondansetronSyringe   ]
    }

    static func vancomycinIVPB(_ rng: inout SeededGenerator) -> CompoundSpec {
        let dose = [1000, 1250, 1500].randomElement(using: &rng)!        // mg
        let bagVolume = [100, 250].randomElement(using: &rng)!           // mL
        let withdrawVolume = Double(dose) / 100.0                        // 100 mg/mL reconstitution
        let above1g = max(0, dose - 1000)

        var components: [CompoundComponent] = [
            CompoundComponent(product: vancoVial1g(), totalQuantity: 1, quantityUnit: .g)
        ]
        if above1g > 0 {
            components.append(
                CompoundComponent(product: vancoVial500mg(),
                                  totalQuantity: Double(above1g),
                                  quantityUnit: .mg)
            )
        }
        components.append(
            CompoundComponent(product: swfiVial(), totalQuantity: withdrawVolume, quantityUnit: .mL)
        )
        components.append(
            CompoundComponent(product: nsBag(volume: bagVolume),
                              totalQuantity: Double(bagVolume),
                              quantityUnit: .mL)
        )

        let recipe = """
        1. Reconstitute all Vancomycin vials to 100 mg/mL with Sterile Water for Injection.
        2. Withdraw \(dose) mg / \(trimmed(withdrawVolume)) mL into a sterile syringe.
        3. Introduce to the \(bagVolume) mL bag of 0.9% Sodium Chloride.
        """

        return CompoundSpec(
            medicationName: "Vancomycin \(grouped(dose)) mg in NS \(bagVolume) mL IVPB",
            finalContainer: "\(bagVolume) mL IV",
            route: "IV",
            recipeText: recipe,
            components: components
        )
    }

    static func cefepimeIVPush(_ rng: inout SeededGenerator) -> CompoundSpec {
        CompoundSpec(
            medicationName: "Cefepime 2 g in SWFI",
            finalContainer: "Syringe",
            route: "IV Push",
            recipeText: """
            1. Confirm cefepime vial strength.
            2. Reconstitute per institutional procedure.
            3. Draw final dose into syringe.
            4. Cap, label, and photograph final syringe.
            """,
            components: [
                CompoundComponent(
                    product: cefepimeVial2g(),
                    totalQuantity: 2,
                    quantityUnit: .g,
                    utilizedLots: [utilizedLot(prefix: "CEF", strength: 2, &rng)]
                ),
                CompoundComponent(product: swfiVial(), totalQuantity: 10, quantityUnit: .mL)
            ]
        )
    }

    static func avycazInfusion(_ rng: inout SeededGenerator) -> CompoundSpec {
        let dose = [5.0, 7.5].randomElement(using: &rng)!   // g
        return CompoundSpec(
            medicationName: "Avycaz \(trimmed(dose))g in 250 mL NS Continuous Infusion",
            finalContainer: "Bag with gaseous contents evacuated",
            route: "Continuous Infusion",
            recipeText: "",
            components: [
                CompoundComponent(
                    product: avycazVial2_5g(),
                    totalQuantity: dose,
                    quantityUnit: .g,
                    utilizedLots: [utilizedLot(prefix: "99A", strength: dose, &rng)]
                ),
                CompoundComponent(product: nsBag(volume: 250), totalQuantity: 250, quantityUnit: .mL)
            ]
        )
    }

    static func zosynIVPB(_ rng: inout SeededGenerator) -> CompoundSpec {
        let bagVolume = [50, 100].randomElement(using: &rng)!
        return CompoundSpec(
            medicationName: "Piperacillin-Tazobactam 4.5 g in NS \(bagVolume) mL IVPB",
            finalContainer: "\(bagVolume) mL IV",
            route: "IV",
            recipeText: """
            1. Reconstitute the 4.5 g vial per institutional procedure.
            2. Withdraw the full reconstituted volume into a sterile syringe.
            3. Introduce to the \(bagVolume) mL bag of 0.9% Sodium Chloride.
            """,
            components: [
                CompoundComponent(
                    product: zosynVial4_5g(),
                    totalQuantity: 4.5,
                    quantityUnit: .g,
                    utilizedLots: [utilizedLot(prefix: "ZOS", strength: 4.5, &rng)]
                ),
                CompoundComponent(product: nsBag(volume: bagVolume),
                                  totalQuantity: Double(bagVolume),
                                  quantityUnit: .mL)
            ]
        )
    }

    static func meropenemIVPB(_ rng: inout SeededGenerator) -> CompoundSpec {
        let bagVolume = [100, 250].randomElement(using: &rng)!
        return CompoundSpec(
            medicationName: "Meropenem 1 g in NS \(bagVolume) mL IVPB",
            finalContainer: "\(bagVolume) mL IV",
            route: "IV",
            recipeText: """
            1. Reconstitute the 1 g vial with Sterile Water for Injection.
            2. Withdraw the full dose into a sterile syringe.
            3. Introduce to the \(bagVolume) mL bag of 0.9% Sodium Chloride.
            """,
            components: [
                CompoundComponent(
                    product: meropenemVial1g(),
                    totalQuantity: 1,
                    quantityUnit: .g,
                    utilizedLots: [utilizedLot(prefix: "MER", strength: 1, &rng)]
                ),
                CompoundComponent(product: swfiVial(), totalQuantity: 20, quantityUnit: .mL),
                CompoundComponent(product: nsBag(volume: bagVolume),
                                  totalQuantity: Double(bagVolume),
                                  quantityUnit: .mL)
            ]
        )
    }

    static func ondansetronSyringe(_ rng: inout SeededGenerator) -> CompoundSpec {
        CompoundSpec(
            medicationName: "Ondansetron 4 mg Syringe",
            finalContainer: "Syringe",
            route: "IV Push",
            recipeText: """
            1. Draw 4 mg / 2 mL from the ondansetron vial into a sterile syringe.
            2. Cap, label, and photograph the final syringe.
            """,
            components: [
                CompoundComponent(
                    product: ondansetronVial4mg(),
                    totalQuantity: 4,
                    quantityUnit: .mg,
                    utilizedLots: [utilizedLot(prefix: "OND", strength: 4, &rng)]
                )
            ]
        )
    }
}

// MARK: - Product factories
//
// Fresh Product per call so each order owns its own component graph rather than
// sharing reference-type instances across orders. mlConcentration values for the
// diluents are preserved from the original mock data — adjust if that field means
// something else in your model.

private extension MockData {

    static func vancoVial1g() -> Product {
        Product(name: "Vancomycin 1 g vial", linkedNDCs: ["00000-0001-01"],
                strength: 1, strengthUnit: .g)
    }

    static func vancoVial500mg() -> Product {
        Product(name: "Vancomycin 500 mg vial", linkedNDCs: ["00000-0005-01"],
                strength: 500, strengthUnit: .mg)
    }

    static func cefepimeVial2g() -> Product {
        Product(name: "Cefepime 2 g vial", linkedNDCs: ["00000-0200-01"],
                strength: 2, strengthUnit: .g)
    }

    static func avycazVial2_5g() -> Product {
        Product(name: "Ceftazidime-Tazobactam 2.5g vial", linkedNDCs: ["00000-0201-01"],
                strength: 2.5, strengthUnit: .g)
    }

    static func zosynVial4_5g() -> Product {
        Product(name: "Piperacillin-Tazobactam 4.5 g vial", linkedNDCs: ["00000-0450-01"],
                strength: 4.5, strengthUnit: .g)
    }

    static func meropenemVial1g() -> Product {
        Product(name: "Meropenem 1 g vial", linkedNDCs: ["00000-0100-01"],
                strength: 1, strengthUnit: .g)
    }

    static func ondansetronVial4mg() -> Product {
        Product(name: "Ondansetron 4 mg/2 mL vial", linkedNDCs: ["00000-0040-02"],
                strength: 4, strengthUnit: .mg, mlConcentration: 2)
    }

    static func swfiVial() -> Product {
        Product(name: "Sterile Water for Injection 10 mL", linkedNDCs: ["00000-0010-10"],
                strength: 10, strengthUnit: .mL, mlConcentration: 10)
    }

    static func nsBag(volume: Int) -> Product {
        Product(name: "0.9% Sodium Chloride \(volume) mL bag",
                linkedNDCs: [String(format: "00000-0%03d-10", volume)],
                strength: 0.9, strengthUnit: .g, mlConcentration: 100)
    }
}

// MARK: - Randomization helpers

private extension MockData {

    static let patientNames = [
        "Test Patient", "John Q. Patient", "Jane R. Doe", "Maria Gonzalez",
        "Robert Chen", "Aisha Patel", "Liam O'Connor", "Sofia Rossi"
    ]

    static let floors = ["3W", "4SW4", "5E", "2N", "ICU", "CVU", "6S"]

    static func randomOrderNumber(_ rng: inout SeededGenerator) -> String {
        String(format: "RXC-1%05d", Int.random(in: 0...99_999, using: &rng))
    }

    static func randomPatient(_ rng: inout SeededGenerator) -> Patient {
        let name = patientNames.randomElement(using: &rng)!
        let floor = floors.randomElement(using: &rng)!
        let room = String(Int.random(in: 100...599, using: &rng))

        if Bool.random(using: &rng) {
            let bed = ["A", "B"].randomElement(using: &rng)!
            return Patient(name: name, floor: floor, room: room, bed: bed)
        }
        return Patient(name: name, floor: floor, room: room)
    }

    static func randomDueTime(_ rng: inout SeededGenerator) -> Date {
        let minutes = Double(Int.random(in: 20...240, using: &rng))
        return .now.addingTimeInterval(minutes * 60)
    }

    static func utilizedLot(prefix: String,
                            strength: Double,
                            _ rng: inout SeededGenerator) -> CompoundUtilizedLot {
        CompoundUtilizedLot(
            barcodeValue: randomBarcode(&rng),
            lot: randomLot(prefix: prefix, &rng),
            expiration: randomExpiration(&rng),
            strengthQuantity: strength
        )
    }

    static func randomLot(prefix: String, _ rng: inout SeededGenerator) -> String {
        let year = Int.random(in: 24...27, using: &rng)
        let number = Int.random(in: 100...999, using: &rng)
        let suffix = ["A", "B", "C", "D"].randomElement(using: &rng)!
        return "\(prefix)\(year)\(number)\(suffix)"   // e.g. CEF24517A
    }

    static func randomBarcode(_ rng: inout SeededGenerator) -> String {
        (0..<12).map { _ in String(Int.random(in: 0...9, using: &rng)) }.joined()
    }

    static func randomExpiration(_ rng: inout SeededGenerator) -> Date {
        let days = Int.random(in: 120...540, using: &rng)
        return .now.addingTimeInterval(Double(days) * 86_400)
    }

    // Formatting helpers

    static func trimmed(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(value)
    }

    static func grouped(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }
}

// MARK: - Seedable RNG
//
// SplitMix64 — deterministic when given a fixed seed, so previews/tests get
// stable mock data while production launches stay fresh.

struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
