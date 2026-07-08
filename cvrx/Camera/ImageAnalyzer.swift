import Vision
import Foundation
import CoreGraphics


private typealias DetectedBarcode = CaptureAnalysis.DetectedBarcode
private typealias DetectedProduct = CaptureAnalysis.DetectedProduct

// MARK: - Analyzer

/// Runs Vision requests on a captured image and extracts pharmaceutical label data.
///
/// Multi-product strategy:
/// 1. Every barcode becomes a product *anchor* (GS1 payloads are parsed directly).
/// 2. OCR lines are assigned to the nearest anchor within `maxAssignDistance`
///    (normalized coords); leftovers go to `unassignedLines`.
/// 3. Regex extraction runs *per product* on only that product's assigned lines,
///    filling fields the barcode didn't provide.
/// 4. With no barcodes, NDC-bearing OCR lines act as anchors instead; if none or
///    one is found, the whole frame is treated as a single product (old behavior).
/// 5. Products that are clearly the same package (identical payload, or identical
///    NDC + lot) are merged.
actor ImageAnalyzer {
    static let shared = ImageAnalyzer()
    private init() {}

    /// Max normalized distance between an OCR line and an anchor for association.
    /// Tune against real captures; 0.35 works for 1–4 vials in a typical frame.
    private let maxAssignDistance: CGFloat = 0.35

    func analyze(url: URL) async -> CaptureAnalysis {
        let textRequest: RecognizeTextRequest = {
            var r = RecognizeTextRequest()
            r.recognitionLevel = .accurate
            r.usesLanguageCorrection = false
            return r
        }()

        async let barcodeObs = DetectBarcodesRequest().perform(on: url)
        async let textObs    = textRequest.perform(on: url)
        async let classObs   = ClassifyImageRequest().perform(on: url)

        let barcodes        = (try? await barcodeObs) ?? []
        let textLines       = (try? await textObs)    ?? []
        let classifications = (try? await classObs)   ?? []

        return build(barcodes: barcodes, text: textLines, classifications: classifications)
    }

    // MARK: - Build

    /// An OCR line paired with its location.
    private struct LocatedLine {
        let text: String
        let center: CGPoint
    }

    /// A product under construction, pinned to a location in the image.
    private struct ProductBuilder {
        var product: DetectedProduct
        let anchor: CGPoint
        var lines: [LocatedLine] = []
    }

    private func build(
        barcodes: [BarcodeObservation],
        text: [RecognizedTextObservation],
        classifications: [ClassificationObservation]
    ) -> CaptureAnalysis {

        var a = CaptureAnalysis()

        a.imageCategories = classifications
            .filter { $0.hasMinimumPrecision(0.1, forRecall: 0.8) }
            .prefix(3)
            .map(\.identifier)

        // 1. Barcodes → anchors
        var builders: [ProductBuilder] = []
        for obs in barcodes {
            guard let payload = obs.payloadString else { continue }
            let center = Self.center(of: obs.boundingBox)
            a.barcodes.append(.init(
                symbology: String(describing: obs.symbology),
                payload: payload,
                isGS1: obs.isGS1DataCarrier,
                center: center
            ))

            var product = DetectedProduct(sourceBarcodePayload: payload)
            if obs.isGS1DataCarrier {
                extractGS1(from: payload, into: &product)
            } else {
                product.detectedNDC = ndc(in: payload)
            }
            builders.append(.init(product: product, anchor: center))
        }

        // 2. OCR lines with locations
        let located: [LocatedLine] = text.compactMap { obs in
            guard let s = obs.topCandidates(1).first?.string else { return nil }
            return LocatedLine(text: s, center: Self.center(of: obs.boundingBox))
        }
        a.recognizedLines = located.map(\.text)

        // 3. No barcode anchors → fall back to NDC-line anchoring / single product
        if builders.isEmpty {
            return buildWithoutBarcodes(from: located, into: a)
        }

        // 4. Assign each line to the nearest anchor within range
        var unassigned: [LocatedLine] = []
        for line in located {
            if let idx = nearestBuilder(to: line.center, in: builders) {
                builders[idx].lines.append(line)
            } else {
                unassigned.append(line)
            }
        }
        a.unassignedLines = unassigned.map(\.text)

        // 5. Per-product OCR extraction fills whatever the barcode didn't provide
        for i in builders.indices {
            fillFromOCR(&builders[i])
        }

        a.products = merge(builders.map(\.product))
        return a
    }

    /// Index of the closest anchor within `maxAssignDistance`, or nil.
    private func nearestBuilder(to point: CGPoint, in builders: [ProductBuilder]) -> Int? {
        var best: (idx: Int, dist: CGFloat)? = nil
        for (i, b) in builders.enumerated() {
            let d = hypot(point.x - b.anchor.x, point.y - b.anchor.y)
            if d <= maxAssignDistance, d < (best?.dist ?? .infinity) {
                best = (i, d)
            }
        }
        return best?.idx
    }

    private func fillFromOCR(_ b: inout ProductBuilder) {
        b.product.assignedLines = b.lines.map(\.text)
        let joined = b.product.assignedLines.joined(separator: "\n")
        b.product.detectedLot        = b.product.detectedLot        ?? lot(in: joined)
        b.product.detectedExpiration = b.product.detectedExpiration ?? expiration(in: joined)
        b.product.detectedNDC        = b.product.detectedNDC        ?? ndc(in: joined)
    }

    /// No barcodes in frame: anchor on NDC-bearing OCR lines instead.
    /// 0 or 1 NDC lines → single product from the full transcript (legacy behavior).
    /// 2+ NDC lines → one product per NDC line, other lines assigned by proximity.
    private func buildWithoutBarcodes(from located: [LocatedLine], into analysis: CaptureAnalysis) -> CaptureAnalysis {
        var a = analysis

        let ndcLines = located.compactMap { line -> (line: LocatedLine, ndc: String)? in
            guard let value = ndc(in: line.text) else { return nil }
            return (line, value)
        }

        guard ndcLines.count >= 2 else {
            // Single (or zero) product: extract from the whole transcript.
            let full = located.map(\.text).joined(separator: "\n")
            var product = DetectedProduct()
            product.detectedNDC        = ndc(in: full)
            product.detectedLot        = lot(in: full)
            product.detectedExpiration = expiration(in: full)
            product.assignedLines      = located.map(\.text)
            // Only emit a product if we actually found something label-like.
            if product.detectedNDC != nil || product.detectedLot != nil || product.detectedExpiration != nil {
                a.products = [product]
            } else {
                a.unassignedLines = located.map(\.text)
            }
            return a
        }

        var builders: [ProductBuilder] = ndcLines.map {
            var p = DetectedProduct()
            p.detectedNDC = $0.ndc
            return ProductBuilder(product: p, anchor: $0.line.center)
        }

        let anchorTexts = Set(ndcLines.map(\.line.text))
        var unassigned: [LocatedLine] = []
        for line in located where !anchorTexts.contains(line.text) {
            if let idx = nearestBuilder(to: line.center, in: builders) {
                builders[idx].lines.append(line)
            } else {
                unassigned.append(line)
            }
        }
        a.unassignedLines = unassigned.map(\.text)

        for i in builders.indices {
            fillFromOCR(&builders[i])
        }

        a.products = merge(builders.map(\.product))
        return a
    }

    /// Merges entries that are clearly the same physical package:
    /// identical barcode payload, or identical non-nil NDC + lot.
    /// Two vials of the same NDC with different (or unknown) lots stay separate.
    private func merge(_ products: [DetectedProduct]) -> [DetectedProduct] {
        var result: [DetectedProduct] = []
        for p in products {
            if let idx = result.firstIndex(where: { existing in
                if let ep = existing.sourceBarcodePayload, let pp = p.sourceBarcodePayload, ep == pp {
                    return true
                }
                if let en = existing.detectedNDC, let pn = p.detectedNDC, en == pn,
                   let el = existing.detectedLot, let pl = p.detectedLot, el == pl {
                    return true
                }
                return false
            }) {
                // Keep the richer record; backfill missing fields from the duplicate.
                result[idx].detectedNDC        = result[idx].detectedNDC        ?? p.detectedNDC
                result[idx].detectedLot        = result[idx].detectedLot        ?? p.detectedLot
                result[idx].detectedExpiration = result[idx].detectedExpiration ?? p.detectedExpiration
                result[idx].assignedLines.append(contentsOf: p.assignedLines)
            } else {
                result.append(p)
            }
        }
        return result
    }

    private static func center(of rect: NormalizedRect) -> CGPoint {
        CGPoint(
            x: rect.origin.x + rect.width  / 2,
            y: rect.origin.y + rect.height / 2
        )
    }

    // MARK: - GS1 Parsing

    private func extractGS1(from payload: String, into p: inout DetectedProduct) {
        if payload.contains("(") {
            // Human-readable: "(01)00312345...(17)YYMMDD(10)LOT"
            let pattern = #/\((\d{2,4})\)([^(]*)/#
            for match in payload.matches(of: pattern) {
                applyGS1(
                    ai: String(match.output.1),
                    value: String(match.output.2).trimmingCharacters(in: .whitespaces),
                    to: &p
                )
            }
        } else {
            // Raw GS1 with optional FNC1 group separators (U+001D)
            for segment in payload.components(separatedBy: "\u{1D}") where !segment.isEmpty {
                parseRawSegment(segment, into: &p)
            }
        }
    }

    private func parseRawSegment(_ seg: String, into p: inout DetectedProduct) {
        // Fixed-length AIs: AI code → data field length
        let fixed: [String: Int] = [
            "01": 14, "02": 14,
            "11": 6, "12": 6, "13": 6, "15": 6, "16": 6, "17": 6, "18": 6, "19": 6,
            "20": 2
        ]
        // Variable-length AIs: consume the rest of the FNC1-delimited segment
        let variable: Set<String> = ["10", "21", "22", "30", "37"]

        var s = seg[...]
        while s.count >= 2 {
            let ai = String(s.prefix(2))
            if let len = fixed[ai] {
                guard s.count >= 2 + len else { break }
                applyGS1(ai: ai, value: String(s.dropFirst(2).prefix(len)), to: &p)
                s = s.dropFirst(2 + len)
            } else if variable.contains(ai) {
                applyGS1(ai: ai, value: String(s.dropFirst(2)), to: &p)
                break
            } else {
                s = s.dropFirst(1)
            }
        }
    }

    private func applyGS1(ai: String, value: String, to p: inout DetectedProduct) {
        switch ai {
        case "01": p.detectedNDC        = p.detectedNDC        ?? ndcFromGTIN(value)
        case "10": if !value.isEmpty { p.detectedLot = p.detectedLot ?? value }
        case "17": p.detectedExpiration = p.detectedExpiration ?? gs1Date(value)
        default:   break
        }
    }

    /// Extracts the 11-digit NDC from a 14-digit GTIN.
    /// Pharma GTIN-14 = indicator(1) + NDC-11(11) + check(1) → drop first 2, drop last 1.
    private func ndcFromGTIN(_ gtin: String) -> String? {
        guard gtin.count == 14, gtin.allSatisfy(\.isNumber) else { return nil }
        return String(gtin.dropFirst(2).dropLast(1))
    }

    /// Parses a GS1 YYMMDD date. Day "00" means last day of month per GS1 spec.
    private func gs1Date(_ yymmdd: String) -> Date? {
        guard yymmdd.count == 6,
              let yy = Int(yymmdd.prefix(2)),
              let mm = Int(yymmdd.dropFirst(2).prefix(2)),
              let dd = Int(yymmdd.dropFirst(4))
        else { return nil }
        let year = yy < 50 ? 2000 + yy : 1900 + yy
        let cal = Calendar(identifier: .gregorian)
        var comps = DateComponents()
        comps.year = year
        comps.month = mm
        if dd == 0 {
            comps.day = 1
            guard let first = cal.date(from: comps),
                  let days = cal.range(of: .day, in: .month, for: first)?.count
            else { return nil }
            comps.day = days
        } else {
            comps.day = dd
        }
        return cal.date(from: comps)
    }

    // MARK: - OCR Pattern Extraction

    private func lot(in text: String) -> String? {
        capture(#"(?i)(?:lot\s*[#:/]?\s*|l/n\s*[:/]?\s*|batch\s*[:/]?\s*)([A-Z0-9][A-Z0-9\-]{2,19})"#, in: text)
    }

    private func expiration(in text: String) -> Date? {
        let patterns = [
            #"(?i)exp(?:iration|iry|\.)?[\s:.]*(\d{1,2})[/\-](\d{4})"#,
            #"(?i)exp(?:iration|iry|\.)?[\s:.]*(\d{1,2})[/\-](\d{2})\b"#,
            #"(?i)use\s*by[\s:.]*(\d{1,2})[/\-](\d{4})"#,
        ]
        let cal = Calendar(identifier: .gregorian)
        for pat in patterns {
            guard let re = try? Regex(pat),
                  let m = text.firstMatch(of: re)
            else { continue }
            let captures = Array(m.output)
            guard captures.count >= 3,
                  let monthStr = captures[1].substring,
                  let yearStr  = captures[2].substring,
                  let month = Int(monthStr),
                  var year  = Int(yearStr)
            else { continue }
            if year < 100 { year += year < 50 ? 2000 : 1900 }
            var comps = DateComponents()
            comps.year = year
            comps.month = month
            comps.day = 1
            if let date = cal.date(from: comps) { return date }
        }
        return nil
    }

    private func ndc(in text: String) -> String? {
        let patterns = [
            #"(?i)ndc[\s:#]*(\d{5}-\d{4}-\d{2})"#,
            #"(?i)ndc[\s:#]*(\d{5}-\d{3}-\d{2})"#,
            #"\b(\d{5}-\d{4}-\d{2})\b"#,
            #"\b(\d{5}-\d{3}-\d{2})\b"#,
        ]
        for pat in patterns {
            if let r = capture(pat, in: text) { return r }
        }
        return nil
    }

    /// Returns the first capture group of a regex match, or the full match if there are no groups.
    private func capture(_ pattern: String, in text: String) -> String? {
        guard let re = try? Regex(pattern),
              let match = text.firstMatch(of: re)
        else { return nil }
        let output = match.output
        let captured = output.dropFirst().first?.substring ?? output.first?.substring
        return captured.map(String.init)
    }
}
