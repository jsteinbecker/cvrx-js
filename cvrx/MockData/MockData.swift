import Foundation
import SwiftUI

enum MockData {

    // MARK: - Users
    //
    // `User` is a reference type (ObservableObject). Exposing mock users as
    // `static let` produces a process-wide singleton, which means every call
    // site silently shares the *same* mutable instance — a footgun for
    // previews and tests. Use factories so each caller gets a fresh User,
    // and let the app root take ownership via @StateObject.

    static func makeUserJts() -> User {
        User(username: "jts", deptId: "NCMC", name: "Josh Steinbecker", role: .hdcpht)
    }

    static func makeUserMsm() -> User {
        User(username: "msm", deptId: "NCMC", name: "Molly Sweeney-McKeil", role: .rph)
    }

    // Catalog products. In real life these come from the formulary; here we
    // hand-roll a small fixture set that mirrors the structure of the new
    // Product model.
    private static let vanco1g = Product(
        name: "Vancomycin 1 g vial",
        linkedNDCs: ["00000-0001-01"],
        strength: 1,
        strengthUnit: .g
    )

    private static let vanco500mg = Product(
        name: "Vancomycin 500 mg vial",
        linkedNDCs: ["00000-0005-01"],
        strength: 500,
        strengthUnit: .mg
    )

    private static let ns250 = Product(
        name: "0.9% Sodium Chloride 250 mL bag",
        linkedNDCs: ["00000-0250-10"],
        strength: 0.9,
        strengthUnit: .g,
        mlConcentration: 100   // 0.9 g per 100 mL — informational only here
    )

    private static let cefepime2g = Product(
        name: "Cefepime 2 g vial",
        linkedNDCs: ["00000-0200-01"],
        strength: 2,
        strengthUnit: .g
    )

    private static let avycaz2500mg = Product(
        name: "Ceftazidime-Tazobactam 2.5g vial",
        linkedNDCs: ["00000-0201-01"],
        strength: 2.5,
        strengthUnit: .g
    )

    private static let swfi = Product(
        name: "Sterile Water for Injection 10 mL",
        linkedNDCs: ["00000-0010-10"],
        strength: 10,
        strengthUnit: .mL,
        mlConcentration: 10
    )

    static let orders: [CompoundOrder] = [
        CompoundOrder(
            id: UUID(),
            orderNumber: "RXC-100428",
            patient: Patient(id: UUID(), name: "Test Patient", floor: "3W", room: "356"),
            medicationName: "Vancomycin 1,250 mg in NS 250 mL IVPB",
            finalContainer: "250 mL IV",
            route: "IV",
            dueTime: .now.addingTimeInterval(60 * 45),
            recipeText: "1. Reconstitute all Vancomycin vials to a concentration of 100mg/mL with Sterile Water. \n2. Withdraw 1250mg / 12.5mL into a sterile syringe. \n3.Introduce to the 250mL bag of 0.9% Sodium Chloride.",
            components: [
                CompoundComponent(
                    product: vanco1g,
                    totalQuantity: 1,
                    quantityUnit: .g
                ),
                CompoundComponent(
                    product: vanco500mg,
                    totalQuantity: 250,
                    quantityUnit: .mg
                ),
                CompoundComponent(
                    product: swfi,
                    totalQuantity: 15,
                    quantityUnit: .mL
                ),
                CompoundComponent(
                    product: ns250,
                    totalQuantity: 250,
                    quantityUnit: .mL
                )
            ],
            captures: [],
            status: .pending
        ),
        CompoundOrder(
            id: UUID(),
            orderNumber: "RXC-100429",
            patient: Patient(id: UUID(), name: "John  Q Patient", floor: "4SW4", room: "429", bed: "A"),
            medicationName: "Cefepime 2 g in SWFI",
            finalContainer: "Syringe",
            route: "IV Push",
            dueTime: .now.addingTimeInterval(60 * 90),
            recipeText: "1. Confirm cefepime vial strength.\n2. Reconstitute per institutional procedure.\n3. Draw final dose into syringe.\n4. Cap, label, and photograph final syringe.",
            components: [
                CompoundComponent(
                    product: cefepime2g,
                    totalQuantity: 2,
                    quantityUnit: .g,
                    utilizedLots: [
                        CompoundUtilizedLot(
                            barcodeValue: "300000200015",
                            lot: "CEF24A",
                            expiration: .now.addingTimeInterval(60 * 60 * 24 * 180),
                            strengthQuantity: 2
                        )
                    ]
                ),
                CompoundComponent(
                    product: swfi,
                    totalQuantity: 10,
                    quantityUnit: .mL
                )
            ],
            captures: [],
            status: .pending
        ),
        CompoundOrder(
            id: UUID(),
            orderNumber: "RXC-100430",
            patient: Patient(id: UUID(), name: "John  Q Patient", floor: "4SW4", room: "429", bed: "A"),
            medicationName: "Avycaz 7.5g in 250mL NS Continuous Infusion",
            finalContainer: "Bag with gaseous contents evacuated",
            route: "Continuous Infusion",
            dueTime: .now.addingTimeInterval(60 * 90),
            recipeText: "",
            components: [
                CompoundComponent(
                    id: UUID(),
                    product: avycaz2500mg,
                    totalQuantity: 7.5,
                    quantityUnit: .g,
                    utilizedLots: [
                        CompoundUtilizedLot(
                            id: UUID(),
                            barcodeValue: "678964556848",
                            lot: "99A450A",
                            expiration: .now.addingTimeInterval(60 * 60 * 24 * 180),
                            strengthQuantity: 7.5
                        )
                    ]
                ),
                CompoundComponent(
                    product: ns250,
                    totalQuantity: 250,
                    quantityUnit: .mL
                )
            ],
            captures: [],
            status: .pending
        )
    ]
}
