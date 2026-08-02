import Testing
@testable import VercelAnalyticsBar

@Test func accountConnectionErrorsProvideSafeRecoveryCopy() {
    let secret = "vercel-secret-token"

    for error in [AccountConnectionError.invalidToken, .insufficientPermissions] {
        #expect(error.localizedDescription.isEmpty == false)
        #expect(error.recoverySuggestion?.isEmpty == false)
        #expect(error.localizedDescription.contains(secret) == false)
        #expect(error.recoverySuggestion?.contains(secret) == false)
    }
}
