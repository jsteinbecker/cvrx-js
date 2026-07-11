import Foundation

struct GS1BarcodeParseResult: Equatable, Sendable {
    var detectedNDC: String?
    var detectedLot: String?
    var detectedExpiration: Date?
    var detectedManufacturer: String?

    var hasParsedData: Bool {
        detectedNDC != nil || detectedLot != nil || detectedExpiration != nil || detectedManufacturer != nil
    }
}

enum GS1BarcodeParser {
    static func parse(_ rawPayload: String) -> GS1BarcodeParseResult {
        var result = GS1BarcodeParseResult()
        let payload = normalizedPayload(rawPayload)

        if payload.contains("(") {
            let pattern = #/\((\d{2,4})\)([^(]*)/#
            for match in payload.matches(of: pattern) {
                apply(
                    ai: String(match.output.1),
                    value: String(match.output.2).trimmingCharacters(in: .whitespacesAndNewlines),
                    to: &result
                )
            }
        } else {
            for segment in payload.components(separatedBy: "\u{1D}") where !segment.isEmpty {
                parseRawSegment(segment, into: &result)
            }
        }

        if let ndc = result.detectedNDC {
            result.detectedManufacturer = LabelerCodeLookup.name(forNDC: ndc)
        }

        return result
    }

    private static func normalizedPayload(_ payload: String) -> String {
        var value = payload.trimmingCharacters(in: .whitespacesAndNewlines)
        for prefix in ["]d2", "]C1", "]e0"] where value.hasPrefix(prefix) {
            value.removeFirst(prefix.count)
            break
        }
        return value
    }

    private static func parseRawSegment(_ segment: String, into result: inout GS1BarcodeParseResult) {
        let fixed: [String: Int] = [
            "01": 14, "02": 14,
            "11": 6, "12": 6, "13": 6, "15": 6, "16": 6, "17": 6, "18": 6, "19": 6,
            "20": 2
        ]
        let variable: Set<String> = ["10", "21", "22", "30", "37"]

        var remaining = segment[...]
        while remaining.count >= 2 {
            let ai = String(remaining.prefix(2))
            if let length = fixed[ai] {
                guard remaining.count >= 2 + length else { break }
                apply(ai: ai, value: String(remaining.dropFirst(2).prefix(length)), to: &result)
                remaining = remaining.dropFirst(2 + length)
            } else if variable.contains(ai) {
                apply(ai: ai, value: String(remaining.dropFirst(2)), to: &result)
                break
            } else {
                remaining = remaining.dropFirst(1)
            }
        }
    }

    private static func apply(ai: String, value: String, to result: inout GS1BarcodeParseResult) {
        switch ai {
        case "01":
            result.detectedNDC = result.detectedNDC ?? ndcFromGTIN(value)
        case "10":
            if !value.isEmpty { result.detectedLot = result.detectedLot ?? value }
        case "17":
            result.detectedExpiration = result.detectedExpiration ?? gs1Date(value)
        default:
            break
        }
    }

    static func ndcFromGTIN(_ gtin: String) -> String? {
        guard gtin.count == 14, gtin.allSatisfy(\.isNumber) else { return nil }
        return String(gtin.dropFirst(2).dropLast(1))
    }

    static func gs1Date(_ yymmdd: String) -> Date? {
        guard yymmdd.count == 6,
              let yy = Int(yymmdd.prefix(2)),
              let mm = Int(yymmdd.dropFirst(2).prefix(2)),
              let dd = Int(yymmdd.dropFirst(4))
        else { return nil }

        let year = yy < 50 ? 2000 + yy : 1900 + yy
        let calendar = Calendar(identifier: .gregorian)
        var components = DateComponents()
        components.year = year
        components.month = mm

        if dd == 0 {
            components.day = 1
            guard let firstDay = calendar.date(from: components),
                  let days = calendar.range(of: .day, in: .month, for: firstDay)?.count
            else { return nil }
            components.day = days
        } else {
            components.day = dd
        }

        return calendar.date(from: components)
    }
}
