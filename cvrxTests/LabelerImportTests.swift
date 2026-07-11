import Foundation
import Testing
@testable import cvrx

@Suite("Labeler import")
private struct LabelerImportTests {
    @Test("Parses bundled labeler JSON shape")
    func parsesBundledShape() throws {
        let json = """
        [
          {
            "Eli Lilly": {
              "full_name": "Eli Lilly and Company",
              "codes": ["0002"],
              "active_rx_product_count": 150,
              "in_rxnorm": true,
              "active_ndc_product_count": 150,
              "has_active_ndc_products": true
            }
          },
          {
            "Merck Sharp Dohme": {
              "full_name": "Merck Sharp & Dohme LLC",
              "codes": ["0052", "0006", "0052"],
              "active_rx_product_count": 65,
              "in_rxnorm": true,
              "active_ndc_product_count": 65,
              "has_active_ndc_products": true
            }
          }
        ]
        """

        let records = try parseLabelerData(Data(json.utf8))

        #expect(records.map(\.name) == ["Eli Lilly", "Merck Sharp Dohme"])
        #expect(records.first?.fullName == "Eli Lilly and Company")
        #expect(records.last?.codes == ["0006", "0052"])
    }

    @Test("Accepts legacy RxNorm key spelling")
    func acceptsLegacyRxNormKey() throws {
        let json = """
        [
          {
            "Legacy Labeler": {
              "full_name": "Legacy Labeler LLC",
              "codes": ["1234"],
              "in_rx_norm": true
            }
          }
        ]
        """

        let records = try parseLabelerData(Data(json.utf8))

        #expect(records.count == 1)
        #expect(records[0].name == "Legacy Labeler")
        #expect(records[0].codes == ["1234"])
    }

    @Test("Rejects duplicate normalized names")
    func rejectsDuplicateNames() throws {
        let json = """
        [
          {
            "Example": {
              "full_name": "Example Inc.",
              "codes": ["0001"],
              "in_rxnorm": true
            }
          },
          {
            " example ": {
              "full_name": "Example Incorporated",
              "codes": ["0002"],
              "in_rxnorm": true
            }
          }
        ]
        """

        #expect(throws: LabelerImportError.self) {
            _ = try parseLabelerData(Data(json.utf8))
        }
    }
}
