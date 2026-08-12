import Foundation
import Security
import Testing
@testable import VercelAnalyticsBar

@Test func keychainStoreReadsOnlyFromProtectedStorage() throws {
    let keychain = RecordingKeychain()
    keychain.copyResults = [
        (errSecSuccess, Data("protected-token".utf8)),
    ]
    let store = KeychainVercelCredentialStore(
        service: "fixture-service",
        account: "fixture-account",
        keychain: keychain
    )

    #expect(try store.read() == "protected-token")
    #expect(keychain.copiedQueries.count == 1)
    #expect(keychain.copiedQueries[0][kSecUseDataProtectionKeychain as String] as? Bool == true)
    #expect(keychain.addedAttributes.isEmpty)
    #expect(keychain.deletedQueries.isEmpty)
}

@Test func keychainStoreUpdatesAndDeletesOnlyProtectedStorage() throws {
    let keychain = RecordingKeychain()
    keychain.updateStatus = errSecSuccess
    let store = KeychainVercelCredentialStore(keychain: keychain)

    try store.save(" fixture-token ")

    #expect(keychain.updatedQueries.count == 1)
    #expect(keychain.updatedQueries[0].0[kSecUseDataProtectionKeychain as String] as? Bool == true)
    #expect(
        keychain.updatedQueries[0].1[kSecAttrAccessible as String] as? String
            == kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String
    )
    #expect(keychain.deletedQueries.isEmpty)

    try store.delete()
    #expect(keychain.deletedQueries.count == 1)
    #expect(keychain.deletedQueries[0][kSecUseDataProtectionKeychain as String] as? Bool == true)
}

@Test func keychainStoreAddsOnlyProtectedAccessibleStorage() throws {
    let keychain = RecordingKeychain()
    let store = KeychainVercelCredentialStore(keychain: keychain)

    try store.save("fixture-token")

    #expect(keychain.addedAttributes.count == 1)
    #expect(keychain.addedAttributes[0][kSecUseDataProtectionKeychain as String] as? Bool == true)
    #expect(
        keychain.addedAttributes[0][kSecAttrAccessible as String] as? String
            == kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String
    )
}

@Test func keychainStorePreservesUpdateFailureStatus() {
    let keychain = RecordingKeychain()
    keychain.updateStatus = errSecMissingEntitlement
    let store = KeychainVercelCredentialStore(keychain: keychain)

    #expect(throws: CredentialStoreError.keychainStatus(errSecMissingEntitlement)) {
        try store.save("fixture-token")
    }
}

@Test func keychainStorePreservesAddFailureStatus() {
    let keychain = RecordingKeychain()
    keychain.addStatus = errSecMissingEntitlement
    let store = KeychainVercelCredentialStore(keychain: keychain)

    #expect(throws: CredentialStoreError.keychainStatus(errSecMissingEntitlement)) {
        try store.save("fixture-token")
    }
}

@Test func keychainStorePreservesDeleteFailureStatus() {
    let keychain = RecordingKeychain()
    keychain.deleteStatus = errSecMissingEntitlement
    let store = KeychainVercelCredentialStore(keychain: keychain)

    #expect(throws: CredentialStoreError.keychainStatus(errSecMissingEntitlement)) {
        try store.delete()
    }
}

@Test func keychainFailureDiagnosticsContainStatusWithoutTokenData() {
    let secret = "vercel-secret-token"
    let error = CredentialStoreError.keychainStatus(errSecMissingEntitlement)

    #expect(error.diagnosticDescription.contains(String(errSecMissingEntitlement)))
    #expect(!error.diagnosticDescription.contains(secret))
    #expect(!error.localizedDescription.contains(secret))
}

@Test func snapshotCacheUsesAndRestoresUserOnlyPermissions() throws {
    let supportURL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let store = FileAnalyticsSnapshotCacheStore(applicationSupportURL: supportURL)
    let directoryURL = store.fileURL.deletingLastPathComponent()
    defer { try? FileManager.default.removeItem(at: supportURL) }

    try store.write([])
    try expectPermissions(0o700, at: directoryURL)
    try expectPermissions(0o600, at: store.fileURL)

    try FileManager.default.setAttributes([.posixPermissions: 0o777], ofItemAtPath: directoryURL.path)
    try FileManager.default.setAttributes([.posixPermissions: 0o666], ofItemAtPath: store.fileURL.path)
    #expect(try store.read() == [])
    try expectPermissions(0o700, at: directoryURL)
    try expectPermissions(0o600, at: store.fileURL)
}

private func expectPermissions(_ expected: Int, at url: URL) throws {
    let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
    #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == expected)
}

private final class RecordingKeychain: KeychainAccessing {
    var copyResults: [(OSStatus, Data?)] = []
    var updateStatus: OSStatus = errSecItemNotFound
    var addStatus: OSStatus = errSecSuccess
    var deleteStatus: OSStatus = errSecSuccess
    private(set) var copiedQueries: [[String: Any]] = []
    private(set) var updatedQueries: [([String: Any], [String: Any])] = []
    private(set) var addedAttributes: [[String: Any]] = []
    private(set) var deletedQueries: [[String: Any]] = []

    func copyMatching(_ query: [String: Any]) -> (OSStatus, Data?) {
        copiedQueries.append(query)
        return copyResults.removeFirst()
    }

    func update(_ query: [String: Any], attributes: [String: Any]) -> OSStatus {
        updatedQueries.append((query, attributes))
        return updateStatus
    }

    func add(_ attributes: [String: Any]) -> OSStatus {
        addedAttributes.append(attributes)
        return addStatus
    }

    func delete(_ query: [String: Any]) -> OSStatus {
        deletedQueries.append(query)
        return deleteStatus
    }
}
