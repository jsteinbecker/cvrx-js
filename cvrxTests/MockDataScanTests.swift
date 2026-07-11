import SwiftData
import Testing
@testable import cvrx

@Suite("Mock order scan data")
@MainActor
private struct MockDataScanTests {
    @Test("Every generated ingredient has a matching simulated NDC scan")
    func generatedIngredientsMatchSimulatedCorrectScans() throws {
        let container = try ModelContainer(
            for: CSPOrder.self,
            CSPEvent.self,
            VerificationRecord.self,
            AuditEvent.self,
            RemediationRequest.self,
            RemediationCapture.self,
            RemediationLotChange.self,
            BUDMultidosePolicy.self,
            CaptureFlag.self,
            CompoundComponent.self,
            CompoundUtilizedLot.self,
            ScanOverride.self,
            ScanEvent.self,
            CompoundCapture.self,
            Compound.self,
            Product.self,
            Patient.self,
            User.self,
            Labeler.self,
            NDCProduct.self,
            Facility.self,
            FloorUnit.self,
            Room.self,
            Bed.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )

        let orders = MockData.makeSampleOrders(into: container.mainContext, count: 6, seed: 1)
        let components = orders.flatMap(\.components)

        #expect(!components.isEmpty)

        for component in components {
            let product = component.product
            #expect(!product.linkedNDCs.isEmpty, "\(product.name) should expose at least one NDC")
            #expect(!product.normalizedNDCMatchKeys.isEmpty, "\(product.name) should produce scan match keys")

            let simulatedScan = MockData.simulatedCorrectBarcode(for: product)
              print(simulatedScan)
              print(product.name, product.strength, product.strengthUnit)
            #expect(product.allowsBarcode(simulatedScan), "\(product.name) should match its simulated scan \(simulatedScan)")
        }
    }

    @Test("Generated ingredients reject the simulated wrong NDC scan")
    func generatedIngredientsRejectWrongScan() throws {
        let container = try ModelContainer(
            for: CSPOrder.self,
            CSPEvent.self,
            VerificationRecord.self,
            AuditEvent.self,
            RemediationRequest.self,
            RemediationCapture.self,
            RemediationLotChange.self,
            BUDMultidosePolicy.self,
            CaptureFlag.self,
            CompoundComponent.self,
            CompoundUtilizedLot.self,
            ScanOverride.self,
            ScanEvent.self,
            CompoundCapture.self,
            Compound.self,
            Product.self,
            Patient.self,
            User.self,
            Labeler.self,
            NDCProduct.self,
            Facility.self,
            FloorUnit.self,
            Room.self,
            Bed.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )

        let orders = MockData.makeSampleOrders(into: container.mainContext, count: 6, seed: 1)
        let components = orders.flatMap(\.components)
        let incorrectMatches = components.filter { component in
            component.product.allowsBarcode(MockData.simulatedIncorrectBarcode)
        }

        #expect(incorrectMatches.isEmpty, "The intentionally wrong scan should become an unexpected component")
    }
}
