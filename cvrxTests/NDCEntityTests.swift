//
//  NDCEntityTests.swift
//  cvrxTests
//
//  Created by Josh Steinbecker on 7/10/26.
//

import XCTest
import SwiftData
@testable import cvrx

final class NDCEntityTests: XCTestCase {

    // MARK: - digitsOnly

    func test_digitsOnly_stripsNonDigits() {
        XCTAssertEqual(NDCParser.digitsOnly("00069-2587-68"), "00069258768")
        XCTAssertEqual(NDCParser.digitsOnly("0069 2587 68"), "0069258768")
        XCTAssertEqual(NDCParser.digitsOnly("NDC: 0069-2587-68"), "0069258768")
        XCTAssertEqual(NDCParser.digitsOnly(""), "")
    }

    // MARK: - normalize: dash-separated input (unambiguous by construction)

    func test_normalize_dashed_fullWidth_5_4_2() throws {
        let result = try NDCParser.normalize("00069-2587-68")
        XCTAssertEqual(result.labelerCode, "00069")
        XCTAssertEqual(result.productCode, "2587")
        XCTAssertEqual(result.packageCode, "68")
        XCTAssertEqual(result.normalized11, "00069258768")
        XCTAssertFalse(result.isAmbiguous)
        XCTAssertTrue(result.candidates.isEmpty)
    }

    func test_normalize_dashed_droppedLabelerZero_matchesFullWidth() throws {
        // "69-2587-68" is the same drug as "00069-2587-68" with the
        // leading zero of the labeler segment dropped.
        let shortened = try NDCParser.normalize("69-2587-68")
        let full = try NDCParser.normalize("00069-2587-68")
        XCTAssertEqual(shortened.normalized11, full.normalized11)
        XCTAssertEqual(shortened.labelerCode, "00069")
    }

    func test_normalize_dashed_droppedProductZero() throws {
        let result = try NDCParser.normalize("12345-067-89")
        XCTAssertEqual(result.labelerCode, "12345")
        XCTAssertEqual(result.productCode, "0067")
        XCTAssertEqual(result.packageCode, "89")
        XCTAssertEqual(result.normalized11, "12345006789")
    }

    func test_normalize_dashed_droppedPackageZero() throws {
        let result = try NDCParser.normalize("12345-6789-1")
        XCTAssertEqual(result.labelerCode, "12345")
        XCTAssertEqual(result.productCode, "6789")
        XCTAssertEqual(result.packageCode, "01")
        XCTAssertEqual(result.normalized11, "12345678901")
    }

    func test_normalize_dashed_allSegmentsShortened() throws {
        // 4-4-2-configured label printed with every leading zero dropped
        // still normalizes to the same 11-digit code.
        let result = try NDCParser.normalize("1234-567-1")
        XCTAssertEqual(result.labelerCode, "01234")
        XCTAssertEqual(result.productCode, "0567")
        XCTAssertEqual(result.packageCode, "01")
    }

    func test_normalize_dashed_detectsExactConfiguration() throws {
        // Exactly 4-4-2 printed widths.
        let fourFourTwo = try NDCParser.normalize("1234-5678-90")
        XCTAssertEqual(fourFourTwo.configuration, .labeler4product4package2)

        // Exactly 5-3-2 printed widths.
        let fiveThreeTwo = try NDCParser.normalize("12345-678-90")
        XCTAssertEqual(fiveThreeTwo.configuration, .labeler5product3package2)

        // Exactly 5-4-1 printed widths.
        let fiveFourOne = try NDCParser.normalize("12345-6789-0")
        XCTAssertEqual(fiveFourOne.configuration, .labeler5product4package1)
    }

    func test_normalize_dashed_ambiguousWidths_configurationIsNil() throws {
        // Full 5-4-2 width doesn't correspond to any legacy 10-digit config,
        // so there's nothing to report with confidence.
        let result = try NDCParser.normalize("00069-2587-68")
        XCTAssertNil(result.configuration)
    }

    func test_normalize_alternateSeparators() throws {
        let space = try NDCParser.normalize("00069 2587 68")
        let enDash = try NDCParser.normalize("00069–2587–68")
        let emDash = try NDCParser.normalize("00069—2587—68")
        let dot = try NDCParser.normalize("00069.2587.68")
        let expected = "00069258768"
        XCTAssertEqual(space.normalized11, expected)
        XCTAssertEqual(enDash.normalized11, expected)
        XCTAssertEqual(emDash.normalized11, expected)
        XCTAssertEqual(dot.normalized11, expected)
    }

    func test_normalize_dashed_withWhitespacePadding() throws {
        let result = try NDCParser.normalize("  00069-2587-68  ")
        XCTAssertEqual(result.normalized11, "00069258768")
    }

    // MARK: - normalize: no separators, 11 digits (already normalized)

    func test_normalize_elevenDigits_noSeparators() throws {
        let result = try NDCParser.normalize("00069258768")
        XCTAssertEqual(result.labelerCode, "00069")
        XCTAssertEqual(result.productCode, "2587")
        XCTAssertEqual(result.packageCode, "68")
        XCTAssertFalse(result.isAmbiguous)
        XCTAssertNil(result.configuration)
    }

    // MARK: - normalize: no separators, 10 digits (ambiguous)

    func test_normalize_tenDigits_isAmbiguous() throws {
        let result = try NDCParser.normalize("1234567890")
        XCTAssertTrue(result.isAmbiguous)
        XCTAssertEqual(result.candidates.count, 3)
    }

    func test_normalize_tenDigits_candidatesMatchAllThreeConfigurations() throws {
        let result = try NDCParser.normalize("1234567890")

        // 4-4-2 → labeler "1234", product "5678", package "90"
        XCTAssertTrue(result.candidates.contains("01234567890"))
        // 5-3-2 → labeler "12345", product "678", package "90"
        XCTAssertTrue(result.candidates.contains("12345067890"))
        // 5-4-1 → labeler "12345", product "6789", package "0"
        XCTAssertTrue(result.candidates.contains("12345678900"))
    }

    func test_normalize_tenDigits_bestGuessDefaultsTo_5_4_1() throws {
        let result = try NDCParser.normalize("1234567890")
        XCTAssertEqual(result.configuration, .labeler5product4package1)
        XCTAssertEqual(result.normalized11, "12345678900")
    }

    func test_normalize_tenDigits_candidatesAreUnique_whenSegmentsAllZero() throws {
        // Degenerate all-zero input should still produce three (equal)
        // candidates without crashing or duplicating logic incorrectly.
        let result = try NDCParser.normalize("0000000000")
        XCTAssertEqual(result.candidates, ["00000000000", "00000000000", "00000000000"])
    }

    // MARK: - normalize: invalid input

    func test_normalize_emptyString_throws() {
        XCTAssertThrowsError(try NDCParser.normalize("")) { error in
            XCTAssertEqual(error as? NDCParseError, .empty)
        }
    }

    func test_normalize_whitespaceOnly_throws() {
        XCTAssertThrowsError(try NDCParser.normalize("   ")) { error in
            XCTAssertEqual(error as? NDCParseError, .empty)
        }
    }

    func test_normalize_letters_throws() {
        XCTAssertThrowsError(try NDCParser.normalize("ABCDE-1234-56")) { error in
            guard case .invalidCharacters = error as? NDCParseError else {
                return XCTFail("Expected .invalidCharacters, got \(error)")
            }
        }
    }

    func test_normalize_mixedAlphanumeric_throws() {
        XCTAssertThrowsError(try NDCParser.normalize("NDC00069258768")) { error in
            guard case .invalidCharacters = error as? NDCParseError else {
                return XCTFail("Expected .invalidCharacters, got \(error)")
            }
        }
    }

    func test_normalize_tooManyDashSegments_throws() {
        XCTAssertThrowsError(try NDCParser.normalize("1-2-3-4")) { error in
            guard case .tooManySegments(let count) = error as? NDCParseError else {
                return XCTFail("Expected .tooManySegments, got \(error)")
            }
            XCTAssertEqual(count, 4)
        }
    }

    func test_normalize_tooFewDashSegments_throws() {
        XCTAssertThrowsError(try NDCParser.normalize("12345-6789")) { error in
            guard case .tooManySegments(let count) = error as? NDCParseError else {
                return XCTFail("Expected .tooManySegments, got \(error)")
            }
            XCTAssertEqual(count, 2)
        }
    }

    func test_normalize_segmentTooLong_throws() {
        XCTAssertThrowsError(try NDCParser.normalize("123456-1234-56")) { error in
            guard case .segmentTooLong(let segment, let max) = error as? NDCParseError else {
                return XCTFail("Expected .segmentTooLong, got \(error)")
            }
            XCTAssertEqual(segment, "123456")
            XCTAssertEqual(max, 5)
        }
    }

    func test_normalize_packageSegmentTooLong_throws() {
        XCTAssertThrowsError(try NDCParser.normalize("12345-6789-012")) { error in
            guard case .segmentTooLong(let segment, let max) = error as? NDCParseError else {
                return XCTFail("Expected .segmentTooLong, got \(error)")
            }
            XCTAssertEqual(segment, "012")
            XCTAssertEqual(max, 2)
        }
    }

    func test_normalize_nineDigits_throwsTooShort() {
        XCTAssertThrowsError(try NDCParser.normalize("123456789")) { error in
            guard case .tooShort(let count) = error as? NDCParseError else {
                return XCTFail("Expected .tooShort, got \(error)")
            }
            XCTAssertEqual(count, 9)
        }
    }

    func test_normalize_eightDigits_throwsTooShort() {
        XCTAssertThrowsError(try NDCParser.normalize("12345678")) { error in
            guard case .tooShort(let count) = error as? NDCParseError else {
                return XCTFail("Expected .tooShort, got \(error)")
            }
            XCTAssertEqual(count, 8)
        }
    }

    func test_normalize_sevenDigits_throwsTooShort() {
        XCTAssertThrowsError(try NDCParser.normalize("1234567")) { error in
            guard case .tooShort = error as? NDCParseError else {
                return XCTFail("Expected .tooShort, got \(error)")
            }
        }
    }

    func test_normalize_twelveDigits_throwsTooLong() {
        XCTAssertThrowsError(try NDCParser.normalize("123456789012")) { error in
            guard case .tooLong(let count) = error as? NDCParseError else {
                return XCTFail("Expected .tooLong, got \(error)")
            }
            XCTAssertEqual(count, 12)
        }
    }

    // MARK: - billingFormatted / displayFormatted

    func test_billingFormatted_producesStandardDashForm() {
        XCTAssertEqual(NDCParser.billingFormatted("00069258768"), "00069-2587-68")
    }

    func test_billingFormatted_returnsInputUnchanged_ifNotElevenDigits() {
        XCTAssertEqual(NDCParser.billingFormatted("12345"), "12345")
    }

    func test_displayFormatted_5_4_1_dropsPackageLeadingZero() {
        // normalized "12345678901" → labeler 12345, product 6789, package 01
        let display = NDCParser.displayFormatted("12345678901", as: .labeler5product4package1)
        XCTAssertEqual(display, "12345-6789-1")
    }

    func test_displayFormatted_5_3_2_dropsProductLeadingZero() {
        // normalized "12345067890" → labeler 12345, product 0678, package 90
        let display = NDCParser.displayFormatted("12345067890", as: .labeler5product3package2)
        XCTAssertEqual(display, "12345-678-90")
    }

    func test_displayFormatted_4_4_2_dropsLabelerLeadingZero() {
        // normalized "01234567890" → labeler 01234, product 5678, package 90
        let display = NDCParser.displayFormatted("01234567890", as: .labeler4product4package2)
        XCTAssertEqual(display, "1234-5678-90")
    }

    func test_displayFormatted_returnsNil_whenNonZeroDigitWouldBeLost() {
        // Package "68" doesn't start with a zero, so it can't be shortened
        // to width 1 (5-4-1) without losing the "6" — no valid display
        // form in that configuration for this NDC.
        let display = NDCParser.displayFormatted("00069258768", as: .labeler5product4package1)
        XCTAssertNil(display)

        // Likewise product "2587" can't be shortened to width 3 (5-3-2)
        // without losing the "2".
        XCTAssertNil(NDCParser.displayFormatted("00069258768", as: .labeler5product3package2))

        // The 4-4-2 form IS valid here, since labeler "00069" does start
        // with a droppable zero — confirms this isn't a blanket failure.
        XCTAssertEqual(
            NDCParser.displayFormatted("00069258768", as: .labeler4product4package2),
            "0069-2587-68"
        )
    }

    func test_displayFormatted_returnsNil_forWrongLengthInput() {
        XCTAssertNil(NDCParser.displayFormatted("12345", as: .labeler5product4package1))
    }

    // MARK: - String.leftPadded

    func test_leftPadded_padsShortStrings() {
        XCTAssertEqual("69".leftPadded(to: 5), "00069")
        XCTAssertEqual("1".leftPadded(to: 2), "01")
    }

    func test_leftPadded_leavesExactWidthUnchanged() {
        XCTAssertEqual("12345".leftPadded(to: 5), "12345")
    }

    func test_leftPadded_leavesOverWidthUnchanged() {
        // Padding never truncates; over-length segments are caught earlier
        // by NDCParser's explicit width checks instead.
        XCTAssertEqual("123456".leftPadded(to: 5), "123456")
    }

    // MARK: - NDCEntity init

    func test_entityInit_padsSegmentsToStandardWidths() {
        let entity = NDCEntity(labelerCode: "69", productCode: "2587", packageCode: "8")
        XCTAssertEqual(entity.labelerCode, "00069")
        XCTAssertEqual(entity.productCode, "2587")
        XCTAssertEqual(entity.packageCode, "08")
    }

    func test_entityInit_assignsDefaultUUID_whenOmitted() {
        let a = NDCEntity(labelerCode: "00069", productCode: "2587", packageCode: "68")
        let b = NDCEntity(labelerCode: "00069", productCode: "2587", packageCode: "68")
        XCTAssertNotEqual(a.id, b.id)
    }

    func test_entityInit_storesScd() {
        let entity = NDCEntity(labelerCode: "00069", productCode: "2587", packageCode: "68", scd: "197361")
        XCTAssertEqual(entity.scd, "197361")
    }

    func test_entityInit_scdDefaultsToNil() {
        let entity = NDCEntity(labelerCode: "00069", productCode: "2587", packageCode: "68")
        XCTAssertNil(entity.scd)
    }

    // MARK: - NDCEntity(rawNDC:)

    func test_rawNDCInit_succeeds_forDashedInput() throws {
        let entity = try XCTUnwrap(NDCEntity(rawNDC: "69-2587-68"))
        XCTAssertEqual(entity.normalized11, "00069258768")
    }

    func test_rawNDCInit_succeeds_forElevenDigitInput() throws {
        let entity = try XCTUnwrap(NDCEntity(rawNDC: "00069258768"))
        XCTAssertEqual(entity.normalized11, "00069258768")
    }

    func test_rawNDCInit_succeeds_forAmbiguousTenDigitInput() throws {
        // Should succeed with the best-guess configuration rather than nil.
        let entity = try XCTUnwrap(NDCEntity(rawNDC: "1234567890"))
        XCTAssertEqual(entity.normalized11, "12345678900")
    }

    func test_rawNDCInit_returnsNil_forInvalidInput() {
        XCTAssertNil(NDCEntity(rawNDC: "not-an-ndc"))
        XCTAssertNil(NDCEntity(rawNDC: ""))
        XCTAssertNil(NDCEntity(rawNDC: "12345678")) // 8 digits, no separators
    }

    func test_rawNDCInit_passesThroughScd() throws {
        let entity = try XCTUnwrap(NDCEntity(rawNDC: "00069-2587-68", scd: "197361"))
        XCTAssertEqual(entity.scd, "197361")
    }

    // MARK: - isValid

    func test_isValid_trueForProperlyPaddedEntity() {
        let entity = NDCEntity(labelerCode: "00069", productCode: "2587", packageCode: "68")
        XCTAssertTrue(entity.isValid)
    }

    func test_isValid_trueEvenIfConstructedFromShortSegments() {
        // Init always pads, so this should still be valid afterward.
        let entity = NDCEntity(labelerCode: "1", productCode: "2", packageCode: "3")
        XCTAssertTrue(entity.isValid)
        XCTAssertEqual(entity.labelerCode, "00001")
    }

    // MARK: - hasShortenedForm / legacyDisplayFormats

    func test_legacyDisplayFormats_containsOnlyValidConfigurations() {
        // "00069258768": labeler starts with one zero (fits 4-4-2 only),
        // product "2587" has no leading zero (fails 5-3-2's width-3 drop),
        // package "68" has no leading zero (fails 5-4-1's width-1 drop).
        let entity = NDCEntity(labelerCode: "00069", productCode: "2587", packageCode: "68")
        let formats = entity.legacyDisplayFormats
        XCTAssertEqual(formats[.labeler4product4package2], "0069-2587-68")
        XCTAssertNil(formats[.labeler5product3package2])
        XCTAssertNil(formats[.labeler5product4package1])
    }

    func test_hasShortenedForm_trueWhenAtLeastOneConfigurationApplies() {
        let entity = NDCEntity(labelerCode: "00069", productCode: "2587", packageCode: "68")
        XCTAssertTrue(entity.hasShortenedForm)
    }

    func test_hasShortenedForm_falseWhenNoSegmentHasLeadingZero() {
        let entity = NDCEntity(labelerCode: "99999", productCode: "9999", packageCode: "99")
        XCTAssertFalse(entity.hasShortenedForm)
        XCTAssertTrue(entity.legacyDisplayFormats.isEmpty)
    }

    // MARK: - matches(rawNDC:)

    func test_matchesRawNDC_trueForDashedShortenedForm() {
        let entity = NDCEntity(labelerCode: "00069", productCode: "2587", packageCode: "68")
        XCTAssertTrue(entity.matches(rawNDC: "69-2587-68"))
        XCTAssertTrue(entity.matches(rawNDC: "00069-2587-68"))
        XCTAssertTrue(entity.matches(rawNDC: "00069258768"))
    }

    func test_matchesRawNDC_falseForDifferentCode() {
        let entity = NDCEntity(labelerCode: "00069", productCode: "2587", packageCode: "68")
        XCTAssertFalse(entity.matches(rawNDC: "00069-2587-69"))
    }

    func test_matchesRawNDC_trueForAmbiguousTenDigitInput_whenAnyCandidateMatches() {
        // Entity normalized to the 4-4-2 interpretation of "1234567890".
        let entity = NDCEntity(labelerCode: "01234", productCode: "5678", packageCode: "90")
        XCTAssertTrue(entity.matches(rawNDC: "1234567890"))
    }

    func test_matchesRawNDC_falseForAmbiguousTenDigitInput_whenNoCandidateMatches() {
        let entity = NDCEntity(labelerCode: "55555", productCode: "5555", packageCode: "55")
        XCTAssertFalse(entity.matches(rawNDC: "1234567890"))
    }

    func test_matchesRawNDC_falseForUnparsableInput() {
        let entity = NDCEntity(labelerCode: "00069", productCode: "2587", packageCode: "68")
        XCTAssertFalse(entity.matches(rawNDC: "garbage"))
    }

    // MARK: - matches(_ other: NDCEntity)

    func test_matchesEntity_trueForSameNormalizedCode_differentIds() {
        let a = NDCEntity(labelerCode: "00069", productCode: "2587", packageCode: "68")
        let b = NDCEntity(labelerCode: "00069", productCode: "2587", packageCode: "68")
        XCTAssertNotEqual(a.id, b.id)
        XCTAssertTrue(a.matches(b))
    }

    func test_matchesEntity_falseForDifferentCode() {
        let a = NDCEntity(labelerCode: "00069", productCode: "2587", packageCode: "68")
        let b = NDCEntity(labelerCode: "00069", productCode: "2587", packageCode: "69")
        XCTAssertFalse(a.matches(b))
    }

    // MARK: - Equatable

    func test_equatable_matchesNormalizedCodeRegardlessOfId() {
        let a = NDCEntity(labelerCode: "00069", productCode: "2587", packageCode: "68")
        let b = NDCEntity(labelerCode: "00069", productCode: "2587", packageCode: "68")
        XCTAssertEqual(a, b)
    }

    func test_equatable_notEqualForDifferentCode() {
        let a = NDCEntity(labelerCode: "00069", productCode: "2587", packageCode: "68")
        let b = NDCEntity(labelerCode: "00070", productCode: "2587", packageCode: "68")
        XCTAssertNotEqual(a, b)
    }

    // MARK: - NDCEntity.searchKeys(forRawNDC:)

    func test_searchKeys_singleKey_forUnambiguousInput() {
        let keys = NDCEntity.searchKeys(forRawNDC: "00069-2587-68")
        XCTAssertEqual(keys, ["00069258768"])
    }

    func test_searchKeys_threeKeys_forAmbiguousTenDigitInput() {
        let keys = NDCEntity.searchKeys(forRawNDC: "1234567890")
        XCTAssertEqual(keys.count, 3)
        XCTAssertTrue(keys.contains("01234567890"))
        XCTAssertTrue(keys.contains("12345067890"))
        XCTAssertTrue(keys.contains("12345678900"))
    }

    func test_searchKeys_empty_forUnparsableInput() {
        XCTAssertEqual(NDCEntity.searchKeys(forRawNDC: "not-an-ndc"), [])
        XCTAssertEqual(NDCEntity.searchKeys(forRawNDC: ""), [])
    }

    // MARK: - Round-trip / integration

    func test_roundTrip_billingFormattedThenReparsed_producesSameNormalizedCode() throws {
        let original = NDCEntity(labelerCode: "00069", productCode: "2587", packageCode: "68")
        let reparsed = try NDCParser.normalize(original.billingFormatted)
        XCTAssertEqual(reparsed.normalized11, original.normalized11)
    }

    func test_roundTrip_legacyDisplayFormattedThenReparsed_producesSameNormalizedCode() throws {
        let original = NDCEntity(labelerCode: "00069", productCode: "2587", packageCode: "68")
        guard let shortened = original.legacyDisplayFormats[.labeler4product4package2] else {
            return XCTFail("Expected a valid 4-4-2 display format for this NDC")
        }
        let reparsed = try NDCParser.normalize(shortened)
        XCTAssertEqual(reparsed.normalized11, original.normalized11)
    }

    func test_realWorldExample_epinephrine() throws {
        // NDC 0069-2587-68 (illustrative real-shaped example): full,
        // shortened, and no-separator forms should all agree.
        let full = try NDCParser.normalize("00069-2587-68")
        let shortened = try NDCParser.normalize("69-2587-68")
        let noDash = try NDCParser.normalize("00069258768")
        XCTAssertEqual(full.normalized11, shortened.normalized11)
        XCTAssertEqual(full.normalized11, noDash.normalized11)
    }
}
