import Foundation
import CoreGraphics

struct CaptureAnalysis: Codable, Equatable, Sendable {
    var barcodes: [DetectedBarcode] = []
    var recognizedLines: [String] = []
    var imageCategories: [String] = []
    var products: [DetectedProduct] = []
    /// OCR lines that couldn't be confidently associated with any product.
    var unassignedLines: [String] = []

    nonisolated init() {
        barcodes = []
        recognizedLines = []
        imageCategories = []
        products = []
        unassignedLines = []
    }

    var hasAnyData: Bool {
        !barcodes.isEmpty || !recognizedLines.isEmpty
    }

    var hasParsedData: Bool {
        products.contains { $0.hasParsedData }
    }

    var multipleProductsDetected: Bool { products.count > 1 }

    var detectedNDC: String?        { products.count == 1 ? products[0].detectedNDC : nil }
    var detectedLot: String?        { products.count == 1 ? products[0].detectedLot : nil }
    var detectedExpiration: Date?   { products.count == 1 ? products[0].detectedExpiration : nil }

    struct DetectedBarcode: Codable, Equatable, Sendable {
        var symbology: String
        var payload: String
        var isGS1: Bool
        /// Center of the barcode's bounding box in normalized image coordinates (0–1).
        var center: CGPoint
    }

    /// One physical product detected in the frame, with the label data associated to it.
    struct DetectedProduct: Codable, Identifiable, Equatable, Sendable {
        let id: UUID
        var detectedNDC: String?
        var detectedLot: String?
        var detectedExpiration: Date?
        /// Payload of the barcode that anchored this product, if any (nil = OCR-only product).
        var sourceBarcodePayload: String?
        /// OCR lines spatially assigned to this product.
        var assignedLines: [String]

        nonisolated init(
            id: UUID = UUID(),
            detectedNDC: String? = nil,
            detectedLot: String? = nil,
            detectedExpiration: Date? = nil,
            sourceBarcodePayload: String? = nil,
            assignedLines: [String] = []
        ) {
            self.id = id
            self.detectedNDC = detectedNDC
            self.detectedLot = detectedLot
            self.detectedExpiration = detectedExpiration
            self.sourceBarcodePayload = sourceBarcodePayload
            self.assignedLines = assignedLines
        }

        var hasParsedData: Bool {
            detectedNDC != nil || detectedLot != nil || detectedExpiration != nil
        }
    }
}
