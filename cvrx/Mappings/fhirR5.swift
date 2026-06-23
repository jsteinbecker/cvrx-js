//
//  FHIRCompoundExporter.swift
//  cvrx
//
//  Maps a CompoundOrder (+ components, utilized lots, labeler, verification)
//  into a FHIR R5 `Bundle` (collection) containing:
//
//      • Medication          — the compounded sterile product (the recipe)
//          └─ contained:     — one Medication per utilized lot (per-component lot tracking)
//      • Organization        — the compounding pharmacy / labeler
//      • MedicationDispense  — the preparation event (who / when / how much)
//      • Provenance          — the RPh verification audit trail (optional)
//
//  The FHIR layer is fully decoupled from your @Model classes via the
//  `…Representable` protocols below. Conform your SwiftData models to them
//  (see the commented example at the bottom) — you should not need to touch
//  any of the FHIR structs.
//
//  ─────────────────────────────────────────────────────────────────────────
//  DESIGN DECISION — per-component lot traceability
//  R5 `Medication.instance` holds ONE lot for the *finished* CSP only. To keep
//  the lot of every *source* component, each utilized lot becomes a `contained`
//  Medication, and the ingredient that consumed it references it by `#id`.
//  Policy here: ONE `ingredient` entry per utilized lot. If a component is drawn
//  from two vials (two lots), you get two ingredient entries, each pointing at
//  its own contained Medication — full traceability, which is the whole point of
//  CSP documentation. Inactive bases with no tracked lot (e.g. NS diluent) get a
//  single ingredient with `item.concept` and no contained resource.
//  ─────────────────────────────────────────────────────────────────────────
//

import Foundation

// MARK: - Domain interface your @Model classes conform to

/// A quantity with a UCUM unit (e.g. 5000 mg, 100 mL).
public struct FHIRQuantityInput: Sendable {
    public var value: Double
    public var unit: String          // human unit, e.g. "mg"
    public var ucumCode: String      // UCUM code, e.g. "mg" — usually == unit
    public init(value: Double, unit: String, ucumCode: String? = nil) {
        self.value = value
        self.unit = unit
        self.ucumCode = ucumCode ?? unit
    }
}

/// A coded concept (SNOMED, NDC, RxNorm, …).
public struct FHIRCodingInput: Sendable {
    public var system: String        // e.g. "http://hl7.org/fhir/sid/ndc"
    public var code: String
    public var display: String?
    public init(system: String, code: String, display: String? = nil) {
        self.system = system; self.code = code; self.display = display
    }
}

public protocol LabelerRepresentable {
    var fhirID: String { get }       // stable id for Organization/<id>
    var labelerName: String { get }
    var labelerCode: String? { get } // e.g. NDC labeler segment
}

public protocol CompoundUtilizedLotRepresentable {
    var fhirID: String { get }       // stable id; becomes the contained #<id>
    var lotNumber: String { get }
    var expirationDate: Date? { get }
    var drugCoding: FHIRCodingInput? { get }   // NDC / RxNorm of the source product
    var drugDisplay: String { get }            // fallback text if no code
}

public protocol CompoundComponentRepresentable {
    var isActive: Bool { get }
    /// Concentration this component contributes, as numerator / denominator.
    /// Return nil for inactive components carried only as a coded base.
    var strengthNumerator: FHIRQuantityInput? { get }
    var strengthDenominator: FHIRQuantityInput? { get }
    /// Coded identity of the ingredient (used when there is no tracked lot).
    var ingredientCoding: FHIRCodingInput? { get }
    var ingredientDisplay: String { get }
    /// Lots actually consumed for this component.
    var utilizedLots: [any CompoundUtilizedLotRepresentable] { get }
}

public protocol CompoundOrderRepresentable {
    var fhirID: String { get }       // becomes Medication/<id>
    var displayText: String { get }  // e.g. "Vancomycin 50 mg/mL in NS, 100 mL (CSP)"
    var localCode: FHIRCodingInput? { get }   // optional local formulary code
    var doseForm: FHIRCodingInput? { get }    // SNOMED dose form
    var totalVolume: FHIRQuantityInput? { get }
    var finishedLotNumber: String? { get }
    var beyondUseDate: Date? { get }          // BUD → Medication.instance.expirationDate
    var preparedAt: Date? { get }
    var components: [any CompoundComponentRepresentable] { get }
    var labeler: (any LabelerRepresentable)? { get }
    var preparerName: String? { get }         // tech
    var verifierName: String? { get }         // RPh; drives the Provenance
    var verifiedAt: Date? { get }
}

// MARK: - Minimal FHIR R5 model (only the elements we emit)

private struct Coding: Encodable { var system: String; var code: String; var display: String? }
private struct CodeableConcept: Encodable { var coding: [Coding]?; var text: String? }

private struct Quantity: Encodable {
    var value: Double
    var unit: String
    var system: String? = "http://unitsofmeasure.org"
    var code: String?
    init(_ q: FHIRQuantityInput) { value = q.value; unit = q.unit; code = q.ucumCode }
}

private struct Ratio: Encodable { var numerator: Quantity; var denominator: Quantity }
private struct Reference: Encodable { var reference: String }

/// R5 CodeableReference — `concept` and/or `reference`.
private struct CodeableReference: Encodable {
    var concept: CodeableConcept?
    var reference: Reference?
}

private struct Identifier: Encodable { var system: String?; var value: String }

private struct Ingredient: Encodable {
    var item: CodeableReference
    var isActive: Bool?
    var strengthRatio: Ratio?        // R5 choice type serializes as strengthRatio
}

private struct MedicationInstance: Encodable {
    var lotNumber: String?
    var expirationDate: String?      // FHIR dateTime
}

private struct Medication: Encodable {
    let resourceType = "Medication"
    var id: String
    var contained: [Medication]?
    var identifier: [Identifier]?
    var code: CodeableConcept?
    var status: String? = "active"
    var marketingAuthorizationHolder: Reference?
    var doseForm: CodeableConcept?
    var totalVolume: Quantity?
    var ingredient: [Ingredient]?
    var instance: MedicationInstance?
}

private struct Organization: Encodable {
    let resourceType = "Organization"
    var id: String
    var identifier: [Identifier]?
    var name: String
}

private struct DispensePerformer: Encodable { var actor: Reference }

private struct MedicationDispense: Encodable {
    let resourceType = "MedicationDispense"
    var id: String
    var status: String = "completed"
    var medication: CodeableReference
    var quantity: Quantity?
    var whenPrepared: String?
    var performer: [DispensePerformer]?
}

private struct ProvenanceAgent: Encodable {
    var type: CodeableConcept?
    var who: Reference
}

private struct Provenance: Encodable {
    let resourceType = "Provenance"
    var id: String
    var target: [Reference]
    var recorded: String
    var agent: [ProvenanceAgent]
}

// A bundle entry is heterogeneous, so erase each resource to JSON up front.
private struct BundleEntry: Encodable {
    var resource: AnyEncodable
}

private struct Bundle: Encodable {
    let resourceType = "Bundle"
    var type = "collection"
    var entry: [BundleEntry]
}

/// Type-eraser so a [BundleEntry] can hold mixed resource types.
private struct AnyEncodable: Encodable {
    private let encodeFn: (Encoder) throws -> Void
    init<T: Encodable>(_ wrapped: T) { encodeFn = wrapped.encode }
    func encode(to encoder: Encoder) throws { try encodeFn(encoder) }
}

// MARK: - Exporter

public struct FHIRCompoundExporter {

    public init() {}

    /// Produce pretty-printed FHIR R5 Bundle JSON for one compound order.
    public func exportJSON(_ order: any CompoundOrderRepresentable) throws -> Data {
        let bundle = buildBundle(order)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(bundle)
    }

    // MARK: build

    private func buildBundle(_ order: any CompoundOrderRepresentable) -> Bundle {
        var entries: [BundleEntry] = []

        // Organization (labeler / pharmacy)
        var holderRef: Reference?
        if let lab = order.labeler {
            let org = Organization(
                id: lab.fhirID,
                identifier: lab.labelerCode.map {
                    [Identifier(system: "http://hl7.org/fhir/sid/ndc", value: $0)]
                },
                name: lab.labelerName
            )
            entries.append(BundleEntry(resource: AnyEncodable(org)))
            holderRef = Reference(reference: "Organization/\(lab.fhirID)")
        }

        // Medication (+ contained per-lot Medications + ingredients)
        var contained: [Medication] = []
        var ingredients: [Ingredient] = []

        for component in order.components {
            let strength = ratio(for: component)

            if component.utilizedLots.isEmpty {
                // No tracked lot (e.g. diluent) → coded ingredient, no contained resource.
                ingredients.append(
                    Ingredient(
                        item: CodeableReference(concept: concept(for: component), reference: nil),
                        isActive: component.isActive,
                        strengthRatio: strength
                    )
                )
            } else {
                // One ingredient per lot — full lot traceability.
                for lot in component.utilizedLots {
                    let lotMed = Medication(
                        id: lot.fhirID,
                        code: CodeableConcept(
                            coding: lot.drugCoding.map { [Coding(system: $0.system, code: $0.code, display: $0.display)] },
                            text: lot.drugCoding == nil ? lot.drugDisplay : nil
                        ),
                        instance: MedicationInstance(
                            lotNumber: lot.lotNumber,
                            expirationDate: lot.expirationDate.map(fhirDateTime)
                        )
                    )
                    contained.append(lotMed)
                    ingredients.append(
                        Ingredient(
                            item: CodeableReference(concept: nil, reference: Reference(reference: "#\(lot.fhirID)")),
                            isActive: component.isActive,
                            strengthRatio: strength
                        )
                    )
                }
            }
        }

        let medication = Medication(
            id: order.fhirID,
            contained: contained.isEmpty ? nil : contained,
            code: CodeableConcept(
                coding: order.localCode.map { [Coding(system: $0.system, code: $0.code, display: $0.display)] },
                text: order.displayText
            ),
            marketingAuthorizationHolder: holderRef,
            doseForm: order.doseForm.map {
                CodeableConcept(coding: [Coding(system: $0.system, code: $0.code, display: $0.display)], text: nil)
            },
            totalVolume: order.totalVolume.map { Quantity($0) },
            ingredient: ingredients.isEmpty ? nil : ingredients,
            instance: (order.finishedLotNumber != nil || order.beyondUseDate != nil)
                ? MedicationInstance(
                    lotNumber: order.finishedLotNumber,
                    expirationDate: order.beyondUseDate.map(fhirDateTime)
                  )
                : nil
        )
        entries.append(BundleEntry(resource: AnyEncodable(medication)))

        // MedicationDispense (the preparation event)
        var performers: [DispensePerformer] = []
        if let tech = order.preparerName {
            performers.append(DispensePerformer(actor: Reference(reference: "Practitioner/\(slug(tech))")))
        }
        if let rph = order.verifierName {
            performers.append(DispensePerformer(actor: Reference(reference: "Practitioner/\(slug(rph))")))
        }
        let dispense = MedicationDispense(
            id: "\(order.fhirID)-dispense",
            medication: CodeableReference(concept: nil, reference: Reference(reference: "Medication/\(order.fhirID)")),
            quantity: order.totalVolume.map { Quantity($0) },
            whenPrepared: order.preparedAt.map(fhirDateTime),
            performer: performers.isEmpty ? nil : performers
        )
        entries.append(BundleEntry(resource: AnyEncodable(dispense)))

        // Provenance (RPh verification)
        if let rph = order.verifierName, let when = order.verifiedAt {
            let prov = Provenance(
                id: "\(order.fhirID)-verify",
                target: [Reference(reference: "MedicationDispense/\(order.fhirID)-dispense")],
                recorded: fhirDateTime(when),
                agent: [
                    ProvenanceAgent(
                        type: CodeableConcept(
                            coding: [Coding(
                                system: "http://terminology.hl7.org/CodeSystem/provenance-participant-type",
                                code: "verifier", display: "Verifier")],
                            text: nil),
                        who: Reference(reference: "Practitioner/\(slug(rph))")
                    )
                ]
            )
            entries.append(BundleEntry(resource: AnyEncodable(prov)))
        }

        return Bundle(entry: entries)
    }

    // MARK: helpers

    private func ratio(for component: any CompoundComponentRepresentable) -> Ratio? {
        guard let n = component.strengthNumerator, let d = component.strengthDenominator else { return nil }
        return Ratio(numerator: Quantity(n), denominator: Quantity(d))
    }

    private func concept(for component: any CompoundComponentRepresentable) -> CodeableConcept {
        CodeableConcept(
            coding: component.ingredientCoding.map { [Coding(system: $0.system, code: $0.code, display: $0.display)] },
            text: component.ingredientCoding == nil ? component.ingredientDisplay : nil
        )
    }

    private func slug(_ name: String) -> String {
        name.lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .components(separatedBy: CharacterSet.alphanumerics.union(["-"]).inverted)
            .joined()
    }

    private static let dateTimeFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private func fhirDateTime(_ date: Date) -> String {
        Self.dateTimeFormatter.string(from: date)
    }
}

// MARK: - Example conformance (uncomment & adapt to your real @Model names)
/*
extension CompoundOrder: CompoundOrderRepresentable {
    var fhirID: String { id.uuidString }
    var displayText: String { label }                 // your computed label
    var localCode: FHIRCodingInput? { nil }
    var doseForm: FHIRCodingInput? {
        FHIRCodingInput(system: "http://snomed.info/sct", code: "385219001", display: "Solution for injection")
    }
    var totalVolume: FHIRQuantityInput? {
        finalVolumeML.map { FHIRQuantityInput(value: $0, unit: "mL") }
    }
    var finishedLotNumber: String? { cspLotNumber }
    var beyondUseDate: Date? { bud }
    var preparedAt: Date? { preparedTimestamp }
    var components: [any CompoundComponentRepresentable] { compoundComponents }
    var labeler: (any LabelerRepresentable)? { primaryLabeler }
    var preparerName: String? { technician?.name }
    var verifierName: String? { verifyingPharmacist?.name }
    var verifiedAt: Date? { verificationTimestamp }
}

extension CompoundComponent: CompoundComponentRepresentable {
    var strengthNumerator: FHIRQuantityInput? {
        FHIRQuantityInput(value: totalDrugMg, unit: "mg")
    }
    var strengthDenominator: FHIRQuantityInput? {
        FHIRQuantityInput(value: order?.finalVolumeML ?? 1, unit: "mL")
    }
    var ingredientCoding: FHIRCodingInput? {
        ndc.map { FHIRCodingInput(system: "http://hl7.org/fhir/sid/ndc", code: $0, display: drugName) }
    }
    var ingredientDisplay: String { drugName }
    var utilizedLots: [any CompoundUtilizedLotRepresentable] { lots }
}

extension CompoundUtilizedLot: CompoundUtilizedLotRepresentable {
    var fhirID: String { "lot-\(id.uuidString)" }
    var drugCoding: FHIRCodingInput? {
        ndc.map { FHIRCodingInput(system: "http://hl7.org/fhir/sid/ndc", code: $0) }
    }
    var drugDisplay: String { component?.drugName ?? "unknown" }
    // lotNumber, expirationDate already exist on your model
}

extension Labeler: LabelerRepresentable {
    var fhirID: String { "org-\(labelerCode ?? id.uuidString)" }
    var labelerName: String { name }
}
*/
