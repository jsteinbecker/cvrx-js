import Foundation

struct CaptureAnalysis: Equatable, Sendable {
    var barcodes: [DetectedBarcode] = []
    var recognizedLines: [String] = []
    var imageCategories: [String] = []
    var detectedNDC: String?
    var detectedLot: String?
    var detectedExpiration: Date?

    nonisolated init() {
        barcodes = []
        recognizedLines = []
        imageCategories = []
        detectedNDC = nil
        detectedLot = nil
        detectedExpiration = nil
    }

    var hasAnyData: Bool {
        !barcodes.isEmpty || !recognizedLines.isEmpty
    }

    var hasParsedData: Bool {
        detectedNDC != nil || detectedLot != nil || detectedExpiration != nil
    }

    struct DetectedBarcode: Equatable {
        var symbology: String
        var payload: String
        var isGS1: Bool
    }
}
