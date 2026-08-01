import Testing
import VercelAnalyticsCore
@testable import VercelAnalyticsBar

@Test func appUsesCoreProductIdentity() {
    #expect(ProductInfo.name == "Vercel Analytics Bar")
}
