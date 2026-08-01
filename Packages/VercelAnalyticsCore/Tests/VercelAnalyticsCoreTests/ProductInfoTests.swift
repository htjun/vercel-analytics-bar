import Testing
@testable import VercelAnalyticsCore

@Test func productNameIsStable() {
    #expect(ProductInfo.name == "Vercel Analytics Bar")
}
