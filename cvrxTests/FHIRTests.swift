//
//  FHIRCompoundExporterTests.swift
//  cvrxTests
//
//  Validates FHIRCompoundExporter by exporting a representative CSP, parsing the
//  emitted JSON as the raw wire format (JSONSerialization — deliberately NOT the
//  production structs, so the test exercises the actual serialized shape), and
//  asserting:
//      • bundle structure & required resources are present
//      • domain values survive the round trip (lots, BUD, strength ratios, qty)
//      • the one-ingredient-per-lot policy holds
//      • EVERY reference resolves — internal (Resource/id) and contained (#id)
//
//  Uses Swift Testing (Xcode 16+). To run under XCTest instead: rename `@Test`
//  funcs to `test…` methods in an `XCTestCase`, swap `#expect`→`XCTAssert*` and
//  `#require`→`XCTUnwrap`.
//

import Testing
import Foundation
@testable import cvrx   // exposes FHIRCompoundExporter + the …Representable protocols

// MARK: - Test doubles conforming to the domain interface

private struct MockLot: CompoundUtilizedLotRepresentable {
    var fhirID: String
    var lotNumber: String
    var expirationDate: Date?
    var drugCoding: FHIRCodingInput?
    var drugDisplay: String
}

private struct MockComponent: CompoundComponentRepresentable {
    var isActive: Bool
    var strengthNumerator: FHIRQuantityInput?
    var strengthDenominator: FHIRQuantityInput?
    var ingredientCoding: FHIRCodingInput?
    var ingredientDisplay: String
    var utilizedLots: [any CompoundUtilizedLotRepresentable]
}

private struct MockLabeler: LabelerRepresentable {
    var fhirID: String
    var labelerName: String
    var labelerCode: String?
}

private struct MockOrder: CompoundOrderRepresentable {
    var fhirID: String
    var displayText: String
    var localCode: FHIRCodingInput?
    var doseForm: FHIRCodingInput?
    var totalVolume: FHIRQuantityInput?
    var finishedLotNumber: String?
    var beyondUseDate: Date?
    var preparedAt: Date?
    var components: [any CompoundComponentRepresentable]
    var labeler: (any LabelerRepresentable)?
    var preparerName: String?
    var verifierName: String?
    var verifiedAt: Date?
}

// MARK: - Fixture: Vancomycin 50 mg/mL in NS, 100 mL — active drug split across TWO lots

private func makeVancomycinCSP() -> MockOrder {
    let ndc = "http://hl7.org/fhir/sid/ndc"
    let snomed = "http://snomed.info/sct"

    let lotA = MockLot(
        fhirID: "lot-vanc-A",
        lotNumber: "VL-8842A",
        expirationDate: ISO8601DateFormatter().date(from: "2027-04-30T00:00:00Z"),
        drugCoding: FHIRCodingInput(system: ndc, code: "0409-6533-01", display: "Vancomycin 1 g"),
        drugDisplay: "Vancomycin 1 g vial"
    )
    let lotB = MockLot(
        fhirID: "lot-vanc-B",
        lotNumber: "VL-8901C",
        expirationDate: ISO8601DateFormatter().date(from: "2027-06-15T00:00:00Z"),
        drugCoding: FHIRCodingInput(system: ndc, code: "0409-6533-01", display: "Vancomycin 1 g"),
        drugDisplay: "Vancomycin 1 g vial"
    )

    let vanc = MockComponent(
        isActive: true,
        strengthNumerator: FHIRQuantityInput(value: 5000, unit: "mg"),
        strengthDenominator: FHIRQuantityInput(value: 100, unit: "mL"),
        ingredientCoding: FHIRCodingInput(system: ndc, code: "0409-6533-01", display: "Vancomycin"),
        ingredientDisplay: "Vancomycin",
        utilizedLots: [lotA, lotB]               // two vials → two lots
    )

    let saline = MockComponent(                  // inactive base, no tracked lot
        isActive: false,
        strengthNumerator: nil,
        strengthDenominator: nil,
        ingredientCoding: FHIRCodingInput(system: snomed, code: "387390002", display: "Sodium chloride 0.9%"),
        ingredientDisplay: "Sodium chloride 0.9%",
        utilizedLots: []
    )

    return MockOrder(
        fhirID: "csp-vanc-001",
        displayText: "Vancomycin 50 mg/mL in NS, 100 mL (CSP)",
        localCode: nil,
        doseForm: FHIRCodingInput(system: snomed, code: "385219001", display: "Solution for injection"),
        totalVolume: FHIRQuantityInput(value: 100, unit: "mL"),
        finishedLotNumber: "CSP-20260622-014",
        beyondUseDate: ISO8601DateFormatter().date(from: "2026-06-23T18:00:00Z"),
        preparedAt: ISO8601DateFormatter().date(from: "2026-06-22T17:42:00Z"),
        components: [vanc, saline],
        labeler: MockLabeler(fhirID: "org-our-pharmacy", labelerName: "Our Hospital Pharmacy", labelerCode: "99999"),
        preparerName: "Jordan Tech",
        verifierName: "Pat Pharmacist",
        verifiedAt: ISO8601DateFormatter().date(from: "2026-06-22T17:50:00Z")
    )
}

// MARK: - Lightweight JSON navigation

private enum J {
    static func obj(_ any: Any?) -> [String: Any]? { any as? [String: Any] }
    static func arr(_ any: Any?) -> [Any]? { any as? [Any] }
    static func str(_ any: Any?) -> String? { any as? String }
    static func dbl(_ any: Any?) -> Double? {
        if let d = any as? Double { return d }
        if let n = any as? NSNumber { return n.doubleValue }
        return nil
    }
    /// All entry resources of a given resourceType.
    static func resources(_ bundle: [String: Any], type: String) -> [[String: Any]] {
        (arr(bundle["entry"]) ?? []).compactMap { obj(obj($0)?["resource"]) }
            .filter { str($0["resourceType"]) == type }
    }
    static func firstResource(_ bundle: [String: Any], type: String) -> [String: Any]? {
        resources(bundle, type: type).first
    }
}

// MARK: - Suite

@Suite("FHIR R5 compound export")
private struct FHIRCompoundExporterTests {

    /// Export the fixture and parse it once for the whole test.
    func exportedBundle() throws -> [String: Any] {
        let data = try FHIRCompoundExporter().exportJSON(makeVancomycinCSP())
        let parsed = try JSONSerialization.jsonObject(with: data)
        let bundle = try #require(J.obj(parsed), "top-level JSON must be an object")
        print("Exported bundle with \(J.arr(bundle["entry"])?.count ?? 0) entries")
        return bundle
    }

    // MARK: structure

    @Test("Bundle is a collection containing all four resource types")
    func bundleStructure() throws {
        let bundle = try exportedBundle()
        #expect(J.str(bundle["resourceType"]) == "Bundle")
        #expect(J.str(bundle["type"]) == "collection")
        #expect(!J.resources(bundle, type: "Organization").isEmpty)
        #expect(!J.resources(bundle, type: "Medication").isEmpty)
        #expect(!J.resources(bundle, type: "MedicationDispense").isEmpty)
        #expect(!J.resources(bundle, type: "Provenance").isEmpty)
    }

    // MARK: medication header values survive

    @Test("Medication header carries display, dose form, volume, and finished lot")
    func medicationHeader() throws {
        let bundle = try exportedBundle()
        let med = try #require(J.firstResource(bundle, type: "Medication"))

        #expect(J.str(med["id"]) == "csp-vanc-001")
        #expect(J.str(J.obj(med["code"])?["text"]) == "Vancomycin 50 mg/mL in NS, 100 mL (CSP)")

        let form = try #require(J.arr(J.obj(med["doseForm"])?["coding"])?.first.flatMap(J.obj))
        #expect(J.str(form["code"]) == "385219001")

        let vol = try #require(J.obj(med["totalVolume"]))
        #expect(J.dbl(vol["value"]) == 100)
        #expect(J.str(vol["code"]) == "mL")

        let instance = try #require(J.obj(med["instance"]))
        #expect(J.str(instance["lotNumber"]) == "CSP-20260622-014")
        #expect(J.str(instance["expirationDate"]) != nil)   // BUD present
        print("Finished CSP lot \(J.str(instance["lotNumber"]) ?? "?") BUD \(J.str(instance["expirationDate"]) ?? "?")")
    }

    // MARK: one-ingredient-per-lot policy + contained lot tracking

    @Test("Each utilized lot becomes a contained Medication with its lot number")
    func containedLotsPreserved() throws {
        let bundle = try exportedBundle()
        let med = try #require(J.firstResource(bundle, type: "Medication"))
        let contained = try #require(J.arr(med["contained"])?.compactMap(J.obj))

        #expect(contained.count == 2, "two vials → two contained Medications")

        let containedIDs = Set(contained.compactMap { J.str($0["id"]) })
        #expect(containedIDs == ["lot-vanc-A", "lot-vanc-B"], "contained ids unique & expected")

        let lotNumbers = Set(contained.compactMap { J.str(J.obj($0["instance"])?["lotNumber"]) })
        #expect(lotNumbers == ["VL-8842A", "VL-8901C"])

        for c in contained {
            #expect(J.str(J.obj(c["instance"])?["expirationDate"]) != nil, "each source lot has an expiry")
        }
    }

    @Test("Ingredients: two active lot refs + one coded inactive base, strengths intact")
    func ingredients() throws {
        let bundle = try exportedBundle()
        let med = try #require(J.firstResource(bundle, type: "Medication"))
        let ingredients = try #require(J.arr(med["ingredient"])?.compactMap(J.obj))

        #expect(ingredients.count == 3, "2 active (per lot) + 1 inactive base")

        let active = ingredients.filter { ($0["isActive"] as? Bool) == true }
        #expect(active.count == 2)
        for ing in active {
            let ref = try #require(J.str(J.obj(J.obj(ing["item"])?["reference"])?["reference"]))
            #expect(ref.hasPrefix("#"), "active ingredient points at a contained lot")
            let ratio = try #require(J.obj(ing["strengthRatio"]))
            #expect(J.dbl(J.obj(ratio["numerator"])?["value"]) == 5000)
            #expect(J.str(J.obj(ratio["numerator"])?["code"]) == "mg")
            #expect(J.dbl(J.obj(ratio["denominator"])?["value"]) == 100)
            #expect(J.str(J.obj(ratio["denominator"])?["code"]) == "mL")
        }

        let inactive = try #require(ingredients.first { ($0["isActive"] as? Bool) == false })
        #expect(J.obj(inactive["item"])?["reference"] == nil, "base uses a concept, not a reference")
        let coding = try #require(J.arr(J.obj(J.obj(inactive["item"])?["concept"])?["coding"])?.first.flatMap(J.obj))
        #expect(J.str(coding["code"]) == "387390002")
    }

    // MARK: dispense + provenance

    @Test("Dispense records preparation event with both performers")
    func dispense() throws {
        let bundle = try exportedBundle()
        let disp = try #require(J.firstResource(bundle, type: "MedicationDispense"))
        #expect(J.str(disp["status"]) == "completed")
        #expect(J.str(J.obj(J.obj(disp["medication"])?["reference"])?["reference"]) == "Medication/csp-vanc-001")
        #expect(J.dbl(J.obj(disp["quantity"])?["value"]) == 100)
        #expect(J.str(disp["whenPrepared"]) != nil)
        #expect((J.arr(disp["performer"])?.count ?? 0) == 2, "tech + RPh")
    }

    @Test("Provenance targets the dispense with a verifier agent")
    func provenance() throws {
        let bundle = try exportedBundle()
        let prov = try #require(J.firstResource(bundle, type: "Provenance"))
        let target = try #require(J.str(J.obj(J.arr(prov["target"])?.first)?["reference"]))
        #expect(target == "MedicationDispense/csp-vanc-001-dispense")
        let agentType = J.arr(J.obj(J.obj(J.arr(prov["agent"])?.first)?["type"])?["coding"])?
            .first.flatMap(J.obj)
        #expect(J.str(agentType?["code"]) == "verifier")
        #expect(J.str(prov["recorded"]) != nil)
    }

    // MARK: the important one — referential integrity

    @Test("Every reference resolves: internal Resource/id and contained #id")
    func referentialIntegrity() throws {
        let bundle = try exportedBundle()
        let entries = try #require(J.arr(bundle["entry"])?.compactMap { J.obj(J.obj($0)?["resource"]) })

        // Build the set of resolvable top-level targets: "ResourceType/id".
        var topLevelTargets = Set<String>()
        for r in entries {
            if let type = J.str(r["resourceType"]), let id = J.str(r["id"]) {
                topLevelTargets.insert("\(type)/\(id)")
            }
        }

        // Walk every reference string anywhere in the tree and check resolution.
        var checked = 0
        func walk(_ node: Any, containedIDs: Set<String>) {
            if let dict = J.obj(node) {
                // A FHIR Reference is { "reference": "<string>" }.
                if let refStr = J.str(dict["reference"]), dict.count <= 2 {
                    checked += 1
                    if refStr.hasPrefix("#") {
                        let id = String(refStr.dropFirst())
                        #expect(containedIDs.contains(id), "dangling contained reference \(refStr)")
                    } else if refStr.contains("/") && !refStr.hasPrefix("urn:") {
                        // Practitioner/* aren't emitted as entries here (external), so
                        // only enforce resolution for the types we DO emit.
                        let type = String(refStr.prefix(while: { $0 != "/" }))
                        if ["Medication", "Organization", "MedicationDispense"].contains(type) {
                            #expect(topLevelTargets.contains(refStr), "dangling reference \(refStr)")
                        }
                    }
                }
                for (_, v) in dict { walk(v, containedIDs: containedIDs) }
            } else if let array = J.arr(node) {
                for v in array { walk(v, containedIDs: containedIDs) }
            }
        }

        for r in entries {
            let containedIDs = Set((J.arr(r["contained"]) ?? []).compactMap { J.str(J.obj($0)?["id"]) })
            walk(r, containedIDs: containedIDs)
        }
        print("Validated \(checked) references — all resolved")
        #expect(checked >= 4, "expected several references in a non-trivial bundle")
    }
}//
//  FHIRTests.swift
//  cvrx
//
//  Created by Josh Steinbecker on 6/23/26.
//

