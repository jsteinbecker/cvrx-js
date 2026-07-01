import Vision
import Foundation

/// Runs Vision requests on a captured image and extracts pharmaceutical label data.
actor ImageAnalyzer {
    static let shared = ImageAnalyzer()
    private init() {}

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

    private func build(
        barcodes: [BarcodeObservation],
        text: [RecognizedTextObservation],
        classifications: [ClassificationObservation]
    ) -> CaptureAnalysis {
        
        var a: CaptureAnalysis = CaptureAnalysis()

        a.imageCategories = classifications
            .filter { $0.hasMinimumPrecision(0.1, forRecall: 0.8) }
            .prefix(3)
            .map(\.identifier)

        for obs in barcodes {
            guard let payload = obs.payloadString else { continue }
            a.barcodes.append(.init(
                symbology: String(describing: obs.symbology),
                payload: payload,
                isGS1: obs.isGS1DataCarrier
            ))
            if obs.isGS1DataCarrier {
                extractGS1(from: payload, into: &a)
            } else {
                a.detectedNDC = a.detectedNDC ?? ndc(in: payload)
            }
        }

        a.recognizedLines = text.compactMap { $0.topCandidates(1).first?.string }
        let full = a.recognizedLines.joined(separator: "\n")
        a.detectedLot        = a.detectedLot        ?? lot(in: full)
        a.detectedExpiration = a.detectedExpiration ?? expiration(in: full)
        a.detectedNDC        = a.detectedNDC        ?? ndc(in: full)

        return a
    }

    // MARK: - GS1 Parsing

    private func extractGS1(from payload: String, into a: inout CaptureAnalysis) {
        if payload.contains("(") {
            // Human-readable: "(01)00312345...(17)YYMMDD(10)LOT"
            let pattern = #/\((\d{2,4})\)([^(]*)/#
            for match in payload.matches(of: pattern) {
                applyGS1(
                    ai: String(match.output.1),
                    value: String(match.output.2).trimmingCharacters(in: .whitespaces),
                    to: &a
                )
            }
        } else {
            // Raw GS1 with optional FNC1 group separators (U+001D)
            for segment in payload.components(separatedBy: "\u{1D}") where !segment.isEmpty {
                parseRawSegment(segment, into: &a)
            }
        }
    }

    private func parseRawSegment(_ seg: String, into a: inout CaptureAnalysis) {
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
                applyGS1(ai: ai, value: String(s.dropFirst(2).prefix(len)), to: &a)
                s = s.dropFirst(2 + len)
            } else if variable.contains(ai) {
                applyGS1(ai: ai, value: String(s.dropFirst(2)), to: &a)
                break
            } else {
                s = s.dropFirst(1)
            }
        }
    }

    private func applyGS1(ai: String, value: String, to a: inout CaptureAnalysis) {
        switch ai {
        case "01": a.detectedNDC        = a.detectedNDC        ?? ndcFromGTIN(value)
        case "10": if !value.isEmpty { a.detectedLot = a.detectedLot ?? value }
        case "17": a.detectedExpiration = a.detectedExpiration ?? gs1Date(value)
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
