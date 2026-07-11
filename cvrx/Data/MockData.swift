import Foundation
import SwiftData
import SwiftUI

enum MockData {

    // MARK: - Users
    //
    // Use factories so each caller gets a fresh SwiftData User instance.

    static func makeUserJts() -> User {
        User(username: "jts", deptId: "NCMC", facilityID: "GH", name: "Josh Steinbecker", role: .hdcpht)
    }

    static func makeUserMsm() -> User {
        User(username: "msm", deptId: "NCMC", facilityID: "GH", name: "Molly Sweeney-McKeil", role: .rph)
    }

    static let patientNames = [
        "Test Patient", "John Q. Patient", "Jane R. Doe", "Maria Gonzalez",
        "Robert Chen", "Aisha Patel", "Liam O'Connor", "Sofia Rossi"
    ]
    
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
    static func makeSampleOrders(into: ModelContext ,count: Int = 6, seed: UInt64? = nil) -> [CSPOrder] {
        var rng = SeededGenerator(seed: seed ?? UInt64.random(in: .min ... .max))

        let builders = templateBuilders
        var pool: [@MainActor (inout SeededGenerator) -> CompoundSpec] = []
        var orders: [CSPOrder] = []
        orders.reserveCapacity(count)

        for _ in 0..<count {
            if pool.isEmpty { pool = builders.shuffled(using: &rng) }
            let spec = pool.removeLast()(&rng)

            let newOrder = CSPOrder(
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
    
    static func daptomycinIVPush(_ rng: inout SeededGenerator) -> CompoundSpec {
        let dose = [400, 450, 500, 550, 600, 700, 800, 900].randomElement(using: &rng)!

        return CompoundSpec(
            medicationName: "Daptomycin \(dose) mg IV Push",
            finalContainer: "Syringe",
            route: "IV Push",
            recipeText: """
            1. Confirm daptomycin vial strength(s) needed to prepare a \(dose) mg dose.
            2. Reconstitute each vial with 0.9% Sodium Chloride Injection per institutional procedure — do NOT use dextrose-containing diluents (daptomycin is incompatible with dextrose).
            3. Gently rotate the vial(s); allow to sit until fully dissolved. Avoid vigorous shaking/foaming.
            4. Draw final \(dose) mg dose into syringe.
            5. Cap, label, and photograph final syringe.
            """,
            components: [
                CompoundComponent(
                    product: daptomycinVial500mg(),
                    totalQuantity: Double(dose),
                    quantityUnit: .mg
                ),
                CompoundComponent(product: sodiumChlorideVial(), totalQuantity: 10, quantityUnit: .mL)
            ]
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
                CompoundComponent(product: cefepimeVial2g(), totalQuantity: 2, quantityUnit: .g),
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
                CompoundComponent(product: avycazVial2_5g(), totalQuantity: dose, quantityUnit: .g),
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
                CompoundComponent(product: zosynVial4_5g(), totalQuantity: 4.5, quantityUnit: .g),
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
                CompoundComponent(product: meropenemVial1g(), totalQuantity: 1, quantityUnit: .g),
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
                CompoundComponent(product: ondansetronVial4mg(), totalQuantity: 4, quantityUnit: .mg)
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
    
    static func sodiumChlorideVial() -> Product {
        Product(name: "0.9% Sodium Chloride 20 mL vial", linkedNDCs: ["63323-0186-20"],
                strength: 9, strengthUnit: .mg)
    }
    
    static func daptomycinVial500mg() -> Product {
        Product(name: "Daptomycin 500 mg vial", linkedNDCs: ["00054-0479-25"],
                strength: 500, strengthUnit: .mg)
    }
    
    static func vancoVial1g() -> Product {
        Product(name: "Vancomycin 1 g vial", linkedNDCs: ["67457-0367-10"],
                strength: 1, strengthUnit: .g)
    }
    
    static func vancoVial500mg() -> Product {
        Product(name: "Vancomycin 500 mg vial", linkedNDCs: ["67457-0366-10"],
                strength: 500, strengthUnit: .mg)
    }
    
    static func cefepimeVial2g() -> Product {
        Product(name: "Cefepime 2 g vial", linkedNDCs: ["0143-9859-10"],
                strength: 2, strengthUnit: .g)
    }
    
    static func avycazVial2_5g() -> Product {
        Product(name: "Avycaz 2.5 g vial", linkedNDCs: ["00456-2700-10"],
                strength: 2.5, strengthUnit: .g)
    }
    
    static func zosynVial4_5g() -> Product {
        Product(name: "Piperacillin-Tazobactam 4.5 g vial", linkedNDCs: ["0206-8862-02"],
                strength: 4.5, strengthUnit: .g)
    }
    
    static func meropenemVial1g() -> Product {
        Product(name: "Meropenem 1 g vial", linkedNDCs: ["63323-0508-20"],
                strength: 1, strengthUnit: .g)
    }
    
    static func ondansetronVial4mg() -> Product {
        Product(name: "Ondansetron 4 mg/2 mL vial", linkedNDCs: ["0641-6078-01"],
                strength: 4, strengthUnit: .mg, mlConcentration: 2)
    }
    
    static func swfiVial() -> Product {
        Product(name: "Sterile Water for Injection 10 mL", linkedNDCs: ["0409-4887-10"],
                strength: 10, strengthUnit: .mL, mlConcentration: 10)
    }
    
    static func nsBag(volume: Int) -> Product {
        let ndc: String
        switch volume {
        case 50: ndc = "0338-0049-41"
        case 100: ndc = "0338-0049-38"
        case 250: ndc = "0338-0049-02"
        default: ndc = String(format: "0338-0%04d-10", volume)
        }

        return Product(name: "0.9% Sodium Chloride \(volume) mL bag",
                linkedNDCs: [ndc],
                strength: 0.9, strengthUnit: .g, mlConcentration: 100)
    }
    
    static func daptoVial500mg() -> Product {
        Product(name: "Daptomycin 500 mg vial", linkedNDCs: ["00054-0479-25"],
                strength: 500, strengthUnit: .mg, mlConcentration: 50)
    }
    
    static func daptoVial350mg() -> Product {
        Product(name: "Daptomycin 350 mg vial", linkedNDCs: ["00054-0478-25"],
                strength: 350, strengthUnit: .mg, mlConcentration: 50)
    }
}

// MARK: - Scan Simulation

extension MockData {
    static let simulatedIncorrectBarcode = "01099999999999101799123110WRONGLOT"

    static func simulatedCorrectBarcode(for product: Product, lot: String = "SIMLOT1") -> String {
        let ndc = product.linkedNDCs.first ?? "99999-9999-99"
        let digits = ndc.filter(\.isNumber)
        return "0103\(digits)1729123110\(lot)"
    }
}

// MARK: - Randomization helpers

private extension MockData {


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


extension MockData {
    @MainActor
    static func makeFacility(into context: ModelContext, floors: Int = 5, avgBeds: Int = 10) {
        let facility = Facility(
            id: UUID(),
            name: "General Hospital",
            abv: "GH"
        )
        context.insert(facility)

        let floorTypes: [FloorType] = [.ms, .pc, .ic, .ob, .op]
        let floorNames: [FloorType: String] = [
            .ms: "3W1",
            .pc: "4SW4",
            .ic: "CCU1",
            .ob: "4SW1",
            .op: "OPINF"
        ]

        for i in 0..<floors {
            let floorType = floorTypes[i % floorTypes.count]
            let bedsPerRoom = 2

            let floor = FloorUnit(
                id: UUID(),
                name: "\(floorNames[floorType] ?? "Floor") \(i + 1)",
                facility: facility,
                floorType: floorType,
                bedsPerRoom: bedsPerRoom
            )
            context.insert(floor)

            let roomCount = Int.random(in: 4...8)
            for r in 0..<roomCount {
                let room = Room(
                    id: UUID(),
                    floor: floor,
                    name: "\(100 + i * 10 + r)"
                )
                context.insert(room)

                for b in 0..<bedsPerRoom {
                    let bed = Bed(
                        id: UUID(),
                        name: facility.bedNamingRule.label(for: b),
                        room: room
                    )
                    context.insert(bed)
                }
            }
        }
    }
}
