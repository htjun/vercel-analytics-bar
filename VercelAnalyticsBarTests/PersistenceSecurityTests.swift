import Foundation
import Security
import Testing
@testable import VercelAnalyticsBar

@Test func keychainStoreMigratesLegacyCredentialsToProtectedStorage() throws {
    let keychain = RecordingKeychain()
    keychain.copyResults = [
        (errSecItemNotFound, nil),
        (errSecSuccess, Data("legacy-token".utf8)),
    ]
    let store = KeychainVercelCredentialStore(
        service: "fixture-service",
        account: "fixture-account",
        keychain: keychain
    )

    #expect(try store.read() == "legacy-token")
    #expect(keychain.copiedQueries.count == 2)
    #expect(keychain.copiedQueries[0][kSecUseDataProtectionKeychain as String] as? Bool == true)
    #expect(keychain.copiedQueries[1][kSecUseDataProtectionKeychain as String] == nil)
    #expect(keychain.addedAttributes.count == 1)
    #expect(keychain.addedAttributes[0][kSecUseDataProtectionKeychain as String] as? Bool == true)
    #expect(
        keychain.addedAttributes[0][kSecAttrAccessible as String] as? String
            == kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String
    )
    #expect(keychain.deletedQueries.count == 1)
    #expect(keychain.deletedQueries[0][kSecUseDataProtectionKeychain as String] == nil)
}

@Test func keychainStoreUpdatesProtectedAccessibilityAndDeletesEveryCredentialClass() throws {
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
    #expect(keychain.deletedQueries.count == 1)

    try store.delete()
    #expect(keychain.deletedQueries.count == 3)
    #expect(keychain.deletedQueries[1][kSecUseDataProtectionKeychain as String] as? Bool == true)
    #expect(keychain.deletedQueries[2][kSecUseDataProtectionKeychain as String] == nil)
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
        return errSecSuccess
    }

    func delete(_ query: [String: Any]) -> OSStatus {
        deletedQueries.append(query)
        return errSecSuccess
    }
}
