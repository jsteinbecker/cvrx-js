import Foundation
import Testing
@testable import cvrx

@Suite("GS1 barcode parsing")
private struct GS1BarcodeParserTests {
    @Test("Parses raw DataMatrix payload with lot and expiration")
    func parsesRawDataMatrixPayload() throws {
        let parsed = GS1BarcodeParser.parse("01003123456789011727063010LOT-42")

        #expect(parsed.detectedNDC == "31234567890")
        #expect(parsed.detectedLot == "LOT-42")
        #expect(parsed.detectedExpiration == date(year: 2027, month: 6, day: 30))
    }

    @Test("Parses human-readable GS1 payload")
    func parsesHumanReadablePayload() throws {
        let parsed = GS1BarcodeParser.parse("](01)00312345678901(17)270600(10)BATCH9")

        #expect(parsed.detectedNDC == "31234567890")
        #expect(parsed.detectedLot == "BATCH9")
        #expect(parsed.detectedExpiration == date(year: 2027, month: 6, day: 30))
    }

    @Test("Looks up manufacturer from NDC labeler code")
    func looksUpManufacturerFromNDCLabelerCode() throws {
        let parsed = GS1BarcodeParser.parse("01030000212345681727063010LOT-42")

        #expect(parsed.detectedNDC == "00002123456")
        #expect(parsed.detectedManufacturer == "Eli Lilly")
    }

    @Test("Derives labeler candidates from normalized NDC")
    func derivesLabelerCandidatesFromNormalizedNDC() throws {
        #expect(LabelerCodeLookup.candidateCodes(forNDC: "00002123456") == ["00002", "0002"])
        #expect(LabelerCodeLookup.candidateCodes(forNDC: "0002-1234-56") == ["0002"])
    }

    private func date(year: Int, month: Int, day: Int) -> Date? {
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.year = year
        components.month = month
        components.day = day
        return components.date
    }
}
