import Foundation
import SwiftData

// MARK: - Units

enum QuantityUnit: String, Codable, CaseIterable, Hashable {
    case mg
    case g
    case mcg
    case ug = "µg"
    case ng
    case uL = "µL"
    case mL
    case L
    case units
    case millionUnits = "million units"
    case mEq
    case mmol
    case unitless

    /// Dimension family — quantities can only be converted within the same family.
    enum Dimension {
        case mass, volume, activity, electrolyte, count
    }

    var dimension: Dimension {
        switch self {
        case .ng, .mcg, .ug, .mg, .g:   return .mass
        case .uL, .mL, .L:              return .volume
        case .units, .millionUnits:     return .activity
        case .mEq, .mmol:               return .electrolyte
        case .unitless:                 return .count
        }
    }

    var toBaseFactor: Double {
        switch self {
        case .ng:           return 1e-6
        case .mcg:          return 1e-3
        case .ug:           return 1e-3
        case .mg:           return 1
        case .g:            return 1e3
        case .uL:           return 1e-3
        case .mL:           return 1
        case .L:            return 1e3
        case .units:        return 1
        case .millionUnits: return 1e6
        case .mEq:          return 1
        case .mmol:         return 1
        case .unitless:     return 1
        }
    }
}

extension Double {
    /// Convert a value from one unit to another within the same dimension.
    /// Returns nil if dimensions don't match.
    func converted(from: QuantityUnit, to: QuantityUnit) -> Double? {
        guard from.dimension == to.dimension else { return nil }
        return self * from.toBaseFactor / to.toBaseFactor
    }
}

// MARK: - Product (the catalog entry, not a physical lot)

@Model
final class Product {
    @Attribute(.unique) var id: UUID
    var name: String
    var linkedNDCs: [String]
    /// Labeled strength of the product (e.g. 50 for "50 mg/mL" or "500 mg vial").
    var strength: Double
    var strengthUnit: QuantityUnit
    /// If the product is a solution, the volume associated with `strength`.
    /// e.g. heparin 5000 units/mL → strength=5000, strengthUnit=.units, mlConcentration=1
    /// A dry vial would leave this nil.
    var mlConcentration: Double?
    /// Convenience: is this product a liquid concentration vs. a solid dose form?
    var isSolution: Bool { mlConcentration != nil }

    init(
        id: UUID = UUID(),
        name: String,
        linkedNDCs: [String] = [],
        strength: Double,
        strengthUnit: QuantityUnit,
        mlConcentration: Double? = nil
    ) {
        self.id = id
        self.name = name
        self.linkedNDCs = linkedNDCs
        self.strength = strength
        self.strengthUnit = strengthUnit
        self.mlConcentration = mlConcentration
    }
}

// MARK: - Scan Override Record

/// When a scanned lot's data is corrected (barcode wrong, lot corrected, expiration adjusted),
/// this record documents the change and stores the cosigner.
@Model
final class ScanOverride {
    @Attribute(.unique) var id: UUID
    /// Which lot this override applies to.
    var lotID: UUID
    /// The field that was changed ("barcode", "lot", "expiration").
    var field: String
    /// Original value from the scan.
    var previousValue: String
    /// New value after override.
    var newValue: String
    /// User who performed the override.
    var overriddenBy: User
    /// When the override was applied.
    var overriddenAt: Date
    /// If non-nil, the verifier who co-signed this override.
    var cosignedBy: User?
    /// When the cosign occurred (nil if not yet cosigned).
    var cosignedAt: Date?
    
    init(
        id: UUID = UUID(),
        lotID: UUID,
        field: String,
        previousValue: String,
        newValue: String,
        overriddenBy: User,
        overriddenAt: Date = Date(),
        cosignedBy: User? = nil,
        cosignedAt: Date? = nil
    ) {
        self.id = id
        self.lotID = lotID
        self.field = field
        self.previousValue = previousValue
        self.newValue = newValue
        self.overriddenBy = overriddenBy
        self.overriddenAt = overriddenAt
        self.cosignedBy = cosignedBy
        self.cosignedAt = cosignedAt
    }
    
    /// True if this override requires (and has) a verifier co-signature.
    var isCosigned: Bool { cosignedBy != nil }
    
    /// Summary for audit/display.
    var summary: String {
        if let signer = cosignedBy {
            return "\(field): '\(previousValue)' → '\(newValue)' [cosigned by \(signer.username)]"
        } else {
            return "\(field): '\(previousValue)' → '\(newValue)' [pending cosign]"
        }
    }
}

@Model class ScanEvent {
    @Attribute(.unique) var id: UUID = UUID()
    var scannedValue: String
    var timestamp: Date
    var removed: Bool = false
    var user: User
    var cul: CompoundUtilizedLot? = nil
    
    init(
        id: UUID,
        scannedValue: String,
        timestamp: Date,
        removed: Bool,
        user: User,
        cul: CompoundUtilizedLot? = nil
    ) {
        self.id = id
        self.scannedValue = scannedValue
        self.timestamp = timestamp
        self.removed = removed
        self.user = user
        self.cul = cul
    }
}

@Model
final class CompoundUtilizedLot {
    @Attribute(.unique) var id: UUID
    var barcodeValue: String?
    var lot: String
    var expiration: Date?
    var mfg: String?
    /// Quantity actually drawn from this lot, expressed in the parent component's `quantityUnit`.
    var strengthQuantity: Double
    /// Optional: photo capture reference (matches your bucket-based photo workflow).
    var photoBucketID: UUID?
    /// Who scanned or manually entered this lot.
    var scannedBy: User?
    /// Timestamp this lot was scanned/recorded.
    var scannedAt: Date
    /// Record of any overrides applied to this lot (field corrections, barcode corrections, etc.).
    var overrides: [ScanOverride] = []
    
    init(
        id: UUID = UUID(),
        barcodeValue: String? = nil,
        lot: String,
        expiration: Date? = nil,
        mfg: String? = nil,
        strengthQuantity: Double,
        photoBucketID: UUID? = nil,
        scannedBy: User? = nil,
        scannedAt: Date = Date(),
        overrides: [ScanOverride] = []
    ) {
        self.id = id
        self.barcodeValue = barcodeValue
        self.lot = lot
        self.expiration = expiration
        self.mfg = mfg
        self.strengthQuantity = strengthQuantity
        self.photoBucketID = photoBucketID
        self.scannedBy = scannedBy
        self.scannedAt = scannedAt
        self.overrides = overrides
    }

    var isExpired: Bool {
        guard let expiration else { return false }
        return expiration < Date()
    }
    
    /// True if there are any overrides that lack a verifier co-signature.
    var hasPendingOverrides: Bool {
        overrides.contains { !$0.isCosigned }
    }
    
    var wasScanned: Bool {
        return scannedBy != nil
    }
}

// MARK: - Compound Component (one line item in a compound recipe)

@Model
final class CompoundComponent {
    @Attribute(.unique) var id: UUID
    var compound: Compound?
    var cspOrder: CSPOrder?
    var product: Product
    /// The total target quantity for this component.
    var totalQuantity: Double
    var quantityUnit: QuantityUnit
    /// Lots scanned in to fulfill this component.
    var utilizedLots: [CompoundUtilizedLot]
    /// Indicates the component has at least one verified scan.
    var isScanned: Bool { !utilizedLots.isEmpty }
    var scanOverride: ScanOverride? = nil
    
    init(
        id: UUID = UUID(),
        compound: Compound? = nil,
        product: Product,
        totalQuantity: Double,
        quantityUnit: QuantityUnit,
        utilizedLots: [CompoundUtilizedLot] = []
    ) {
        self.id = id
        self.compound = compound
        self.product = product
        self.totalQuantity = totalQuantity
        self.quantityUnit = quantityUnit
        self.utilizedLots = utilizedLots
    }

    /// Sum of what's been drawn across all scanned lots.
    var quantityAccountedFor: Double {
        utilizedLots.reduce(0) { $0 + $1.strengthQuantity }
    }

    /// Remaining quantity still needed to fulfill `totalQuantity`.
    var quantityRemaining: Double {
        max(0, totalQuantity - quantityAccountedFor)
    }

    /// True when scanned lots fully cover the target (within a small tolerance).
    func isFulfilled(tolerance: Double = 0.001) -> Bool {
        abs(totalQuantity - quantityAccountedFor) <= tolerance
            || quantityAccountedFor >= totalQuantity
    }

    /// Volume to draw from the product, if it's a solution and units are compatible.
    /// e.g. need 200 mg from a 50 mg/mL vial → 4 mL.
    func requiredVolumeFromProduct() -> Double? {
        guard
            let mlConc = product.mlConcentration,
            mlConc > 0,
            let needInProductUnits = totalQuantity.converted(
                from: quantityUnit,
                to: product.strengthUnit
            )
        else { return nil }
        return needInProductUnits / product.strength * mlConc
    }
    
    /// True if any utilized lot has a pending (un-cosigned) override.
    var hasPendingOverrides: Bool {
        utilizedLots.contains { $0.hasPendingOverrides }
    }
}

// MARK: - Compound (the parent record)

@Model
final class Compound {
    @Attribute(.unique) var id: UUID
    var name: String
    var rxNumber: String?
    var preparedBy: String?
    var verifiedBy: String?
    var preparedAt: Date
    var beyondUseDate: Date?
    var components: [CompoundComponent]
    var notes: String?

    init(
        id: UUID = UUID(),
        name: String,
        rxNumber: String? = nil,
        preparedBy: String? = nil,
        verifiedBy: String? = nil,
        preparedAt: Date = Date(),
        beyondUseDate: Date? = nil,
        components: [CompoundComponent] = [],
        notes: String? = nil
    ) {
        self.id = id
        self.name = name
        self.rxNumber = rxNumber
        self.preparedBy = preparedBy
        self.verifiedBy = verifiedBy
        self.preparedAt = preparedAt
        self.beyondUseDate = beyondUseDate
        self.components = components
        self.notes = notes
    }

    var isFullyScanned: Bool {
        !components.isEmpty && components.allSatisfy { $0.isFulfilled() }
    }

    var hasExpiredLot: Bool {
        components.contains { $0.utilizedLots.contains(where: \.isExpired) }
    }
}
