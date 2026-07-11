//
//  NDCEntity.swift
//  cvrx
//
//  Created by Josh Steinbecker on 7/10/26.
//

import SwiftData
import Foundation

// MARK: - NDC Configuration

/// The three legacy 10-digit NDC segment configurations published by the FDA.
/// The 11-digit "normalized" form (5-4-2) is what's used for billing/HIPAA
/// transactions; the 10-digit forms are how labelers actually print NDCs,
/// and each configuration drops the leading zero from a different segment.
enum NDCConfiguration: String, CaseIterable, Codable, Sendable {
    case labeler4product4package2 = "4-4-2"
    case labeler5product3package2 = "5-3-2"
    case labeler5product4package1 = "5-4-1"

    /// Digit width per segment as actually printed for this configuration.
    var printedWidths: (labeler: Int, product: Int, package: Int) {
        switch self {
        case .labeler4product4package2: return (4, 4, 2)
        case .labeler5product3package2: return (5, 3, 2)
        case .labeler5product4package1: return (5, 4, 1)
        }
    }
}

// MARK: - Parse Result / Errors

struct NDCParseResult: Equatable, Sendable {
    let labelerCode: String   // zero-padded to 5
    let productCode: String   // zero-padded to 4
    let packageCode: String   // zero-padded to 2

    /// Known only when segments were explicit (dashes) and matched a
    /// legacy width exactly, or for the ambiguous-10-digit "best guess".
    let configuration: NDCConfiguration?

    /// True when the input was a bare 10-digit string with no separators,
    /// meaning the segment boundaries could not be determined with
    /// certainty (all three legacy configurations sum to 10 digits).
    let isAmbiguous: Bool

    /// Every legal normalized-11 candidate when `isAmbiguous` is true.
    /// Empty otherwise.
    let candidates: [String]

    var normalized11: String { labelerCode + productCode + packageCode }
}

enum NDCParseError: LocalizedError, Equatable {
    case empty
    case invalidCharacters(String)
    case tooShort(digitCount: Int)
    case tooLong(digitCount: Int)
    case segmentTooLong(segment: String, maxAllowed: Int)
    case tooManySegments(count: Int)

    var errorDescription: String? {
        switch self {
        case .empty:
            return "NDC string is empty."
        case .invalidCharacters(let raw):
            return "NDC contains characters other than digits and separators: \"\(raw)\"."
        case .tooShort(let count):
            return "NDC has too few/ambiguous digits (\(count)) to normalize reliably; expected 10 or 11 (or 3 dash-separated segments)."
        case .tooLong(let count):
            return "NDC has too many digits (\(count)) to be valid; expected 10 or 11."
        case .segmentTooLong(let segment, let max):
            return "NDC segment \"\(segment)\" exceeds the maximum width of \(max) digits."
        case .tooManySegments(let count):
            return "NDC has \(count) dash-separated segments; expected exactly 3."
        }
    }
}

// MARK: - Parser

/// Namespace for parsing/normalizing NDC strings from arbitrary user,
/// barcode, or scanner input: with or without dashes, with or without
/// dropped leading zeros, 8–11 digits.
enum NDCParser {

    static func digitsOnly(_ raw: String) -> String {
        raw.filter(\.isNumber)
    }

    /// Normalizes any reasonable NDC representation into its 11-digit form.
    ///
    /// - Dashes present → segment boundaries are explicit; each segment is
    ///   left-padded with zeros up to its max width (5, 4, 2). This handles
    ///   dropped leading zeros regardless of which of the three legacy
    ///   configurations produced the printed form (e.g. "69-2587-68" and
    ///   "0069-2587-68" both normalize to the same 11-digit code).
    /// - No dashes, 11 digits → already normalized, no ambiguity.
    /// - No dashes, 10 digits → boundaries are ambiguous (all three legacy
    ///   configs sum to 10 digits); every legal split is returned as a
    ///   candidate, with a best-guess primary parse.
    /// - No dashes, 8–9 digits → multiple leading zeros were dropped across
    ///   more than one segment with nothing to anchor them; throws rather
    ///   than guess.
    static func normalize(_ raw: String) throws -> NDCParseResult {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw NDCParseError.empty }

        // Allow digits and common separator variants; anything else
        // (letters, NDC-unit suffixes, stray punctuation) is invalid.
        let separatorChars: Set<Character> = ["-", "–", "—", " ", "."]
        let invalidChars = trimmed.filter { !$0.isNumber && !separatorChars.contains($0) }
        guard invalidChars.isEmpty else {
            throw NDCParseError.invalidCharacters(raw)
        }

        let hasSeparators = trimmed.contains(where: separatorChars.contains)

        if hasSeparators {
            let parts = trimmed
                .split(whereSeparator: { separatorChars.contains($0) })
                .map { digitsOnly(String($0)) }
                .filter { !$0.isEmpty }

            guard parts.count == 3 else {
                throw NDCParseError.tooManySegments(count: parts.count)
            }

            let maxWidths = [5, 4, 2]
            for (part, maxWidth) in zip(parts, maxWidths) where part.count > maxWidth {
                throw NDCParseError.segmentTooLong(segment: part, maxAllowed: maxWidth)
            }

            let labeler = parts[0].leftPadded(to: 5)
            let product = parts[1].leftPadded(to: 4)
            let package = parts[2].leftPadded(to: 2)

            // If every segment's printed width matches one known
            // configuration exactly, report it with confidence.
            let printedWidths = (parts[0].count, parts[1].count, parts[2].count)
            let configuration = NDCConfiguration.allCases.first {
                $0.printedWidths == printedWidths
            }

            return NDCParseResult(
                labelerCode: labeler,
                productCode: product,
                packageCode: package,
                configuration: configuration,
                isAmbiguous: false,
                candidates: []
            )
        }

        // No separators: work from digit count alone.
        let digits = digitsOnly(trimmed)
        switch digits.count {
        case 11:
            let labeler = String(digits.prefix(5))
            let product = String(digits.dropFirst(5).prefix(4))
            let package = String(digits.suffix(2))
            return NDCParseResult(
                labelerCode: labeler,
                productCode: product,
                packageCode: package,
                configuration: nil, // already normalized; no legacy config implied
                isAmbiguous: false,
                candidates: []
            )

        case 10:
            var candidateSplits: [(config: NDCConfiguration, labeler: String, product: String, package: String)] = []
            for config in NDCConfiguration.allCases {
                let (lw, pw, kw) = config.printedWidths
                let labeler = String(digits.prefix(lw)).leftPadded(to: 5)
                let product = String(digits.dropFirst(lw).prefix(pw)).leftPadded(to: 4)
                let package = String(digits.suffix(kw)).leftPadded(to: 2)
                candidateSplits.append((config, labeler, product, package))
            }

            let candidates = candidateSplits.map { $0.labeler + $0.product + $0.package }
            // Best guess for a primary parse: 5-4-1 is the single most
            // common legacy configuration across NDC directory data, so
            // surface it as "the" parse while still exposing every
            // candidate for callers who want to check them all (e.g. when
            // matching against a known set of stored NDCs).
            let best = candidateSplits.first { $0.config == .labeler5product4package1 } ?? candidateSplits[0]

            return NDCParseResult(
                labelerCode: best.labeler,
                productCode: best.product,
                packageCode: best.package,
                configuration: best.config,
                isAmbiguous: true,
                candidates: candidates
            )

        case 8, 9:
            // Multiple dropped leading zeros with no separators to anchor
            // segments — too ambiguous to guess reliably without an
            // external labeler-code lookup.
            throw NDCParseError.tooShort(digitCount: digits.count)

        default:
            if digits.count > 11 {
                throw NDCParseError.tooLong(digitCount: digits.count)
            } else {
                throw NDCParseError.tooShort(digitCount: digits.count)
            }
        }
    }

    /// Reformats a normalized 11-digit NDC into the standard billing/HIPAA
    /// 5-4-2 dash format, e.g. "00069-2587-68".
    static func billingFormatted(_ normalized11: String) -> String {
        guard normalized11.count == 11 else { return normalized11 }
        let labeler = normalized11.prefix(5)
        let product = normalized11.dropFirst(5).prefix(4)
        let package = normalized11.suffix(2)
        return "\(labeler)-\(product)-\(package)"
    }

    /// Reformats a normalized 11-digit NDC into one of the three legacy
    /// 10-digit printed configurations (dropping that configuration's
    /// leading zero), for matching how a manufacturer prints it on a label.
    /// Returns nil if the segment being shortened doesn't actually start
    /// with the zero(s) that configuration requires dropping.
    static func displayFormatted(_ normalized11: String, as config: NDCConfiguration) -> String? {
        guard normalized11.count == 11 else { return nil }
        let labeler = String(normalized11.prefix(5))
        let product = String(normalized11.dropFirst(5).prefix(4))
        let package = String(normalized11.suffix(2))

        let (lw, pw, kw) = config.printedWidths

        func dropLeadingZeros(_ segment: String, to width: Int) -> String? {
            guard segment.count >= width else { return nil }
            let droppedCount = segment.count - width
            guard segment.prefix(droppedCount).allSatisfy({ $0 == "0" }) else {
                return nil // a non-zero digit would be lost — invalid for this config
            }
            return String(segment.suffix(width))
        }

        guard let l = dropLeadingZeros(labeler, to: lw),
              let p = dropLeadingZeros(product, to: pw),
              let k = dropLeadingZeros(package, to: kw) else {
            return nil
        }
        return "\(l)-\(p)-\(k)"
    }
}

// MARK: - String padding helper

extension String {
    func leftPadded(to width: Int, with character: Character = "0") -> String {
        guard count < width else { return self }
        return String(repeating: String(character), count: width - count) + self
    }
}

// MARK: - Model

@Model
final class NDCEntity {
    var id: UUID = UUID()
    var labelerCode: String   // always stored zero-padded to 5 digits
    var productCode: String   // always stored zero-padded to 4 digits
    var packageCode: String   // always stored zero-padded to 2 digits
    var scd: String?

    init(
        id: UUID = UUID(),
        labelerCode: String,
        productCode: String,
        packageCode: String,
        scd: String? = nil
    ) {
        self.id = id
        self.labelerCode = labelerCode.leftPadded(to: 5)
        self.productCode = productCode.leftPadded(to: 4)
        self.packageCode = packageCode.leftPadded(to: 2)
        self.scd = scd
    }

    /// Fails only if `raw` can't be parsed into a valid NDC shape at all
    /// (wrong digit count, invalid characters, wrong number of segments).
    /// Ambiguous 10-digit inputs still succeed using a best-guess legacy
    /// configuration — use `NDCParser.normalize(_:)` directly if you need
    /// every candidate split instead of just the best guess.
    convenience init?(rawNDC: String, scd: String? = nil) {
        guard let result = try? NDCParser.normalize(rawNDC) else { return nil }
        self.init(
            labelerCode: result.labelerCode,
            productCode: result.productCode,
            packageCode: result.packageCode,
            scd: scd
        )
    }
}

// MARK: - Computed properties

extension NDCEntity {

    /// The canonical 11-digit form with no separators, e.g. "00069258768".
    var normalized11: String {
        labelerCode + productCode + packageCode
    }

    /// Standard 5-4-2 billing/HIPAA format, e.g. "00069-2587-68".
    var billingFormatted: String {
        "\(labelerCode)-\(productCode)-\(packageCode)"
    }

    /// True if this code has at least one valid "shortened" legacy 10-digit
    /// printed form (i.e. some segment starts with a zero that a
    /// manufacturer's label would typically drop).
    var hasShortenedForm: Bool {
        !legacyDisplayFormats.isEmpty
    }

    /// All valid legacy 10-digit printed representations for this NDC,
    /// keyed by configuration. A code is only representable in the
    /// configuration(s) whose dropped segment actually starts with zero(s);
    /// most real NDCs match exactly one.
    var legacyDisplayFormats: [NDCConfiguration: String] {
        var result: [NDCConfiguration: String] = [:]
        for config in NDCConfiguration.allCases {
            if let formatted = NDCParser.displayFormatted(normalized11, as: config) {
                result[config] = formatted
            }
        }
        return result
    }

    var isValid: Bool {
        labelerCode.count == 5 && labelerCode.allSatisfy(\.isNumber) &&
        productCode.count == 4 && productCode.allSatisfy(\.isNumber) &&
        packageCode.count == 2 && packageCode.allSatisfy(\.isNumber)
    }
}

// MARK: - Matching / querying

extension NDCEntity {

    /// Compares against a raw, possibly-messy NDC string (dashes optional,
    /// leading zeros optional/dropped). Handles ambiguous 10-digit input by
    /// checking every legal candidate split, not just one guess — so a
    /// scanned 10-digit barcode will still match a stored entity even when
    /// the segment boundaries weren't printable from the barcode alone.
    func matches(rawNDC: String) -> Bool {
        guard let result = try? NDCParser.normalize(rawNDC) else { return false }
        if result.isAmbiguous {
            return result.candidates.contains(normalized11)
        }
        return result.normalized11 == normalized11
    }

    /// Exact match against another already-parsed NDCEntity.
    func matches(_ other: NDCEntity) -> Bool {
        normalized11 == other.normalized11
    }

    /// Builds the set of normalized-11 keys to search by, from a raw
    /// scanned/typed string. Use this to drive a SwiftData `#Predicate`
    /// (e.g. `keys.contains(entity.normalized11)`-style matching, or a set
    /// of `OR` clauses) when you only have unparsed user/scanner input.
    /// Returns an empty array if `raw` can't be parsed at all.
    static func searchKeys(forRawNDC raw: String) -> [String] {
        guard let result = try? NDCParser.normalize(raw) else { return [] }
        return result.isAmbiguous ? result.candidates : [result.normalized11]
    }
}

extension NDCEntity: Equatable {
    static func == (lhs: NDCEntity, rhs: NDCEntity) -> Bool {
        lhs.normalized11 == rhs.normalized11
    }
}
