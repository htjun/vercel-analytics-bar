import Foundation
import Security

protocol VercelCredentialStore {
    func read() throws -> String?
    func save(_ token: String) throws
    func delete() throws
}

enum CredentialStoreError: Error, Equatable, LocalizedError {
    case invalidToken
    case invalidStoredValue
    case keychainStatus(Int32)

    var errorDescription: String? {
        switch self {
        case .invalidToken:
            "A non-empty Vercel access token is required."
        case .invalidStoredValue:
            "The stored Vercel credential could not be read."
        case .keychainStatus:
            "The Vercel credential could not be saved securely."
        }
    }
}

struct KeychainVercelCredentialStore: VercelCredentialStore {
    static let defaultService = "VercelAnalyticsBar"
    static let defaultAccount = "vercel-access-token"

    let service: String
    let account: String

    init(service: String = Self.defaultService, account: String = Self.defaultAccount) {
        self.service = service
        self.account = account
    }

    func read() throws -> String? {
        var query = itemQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        switch status {
        case errSecItemNotFound:
            return nil
        case errSecSuccess:
            guard let data = result as? Data,
                  let token = String(data: data, encoding: .utf8),
                  !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else {
                throw CredentialStoreError.invalidStoredValue
            }
            return token
        default:
            throw CredentialStoreError.keychainStatus(status)
        }
    }

    func save(_ token: String) throws {
        let normalizedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedToken.isEmpty else {
            throw CredentialStoreError.invalidToken
        }

        guard let data = normalizedToken.data(using: .utf8) else {
            throw CredentialStoreError.invalidToken
        }

        let update = [kSecValueData as String: data]
        let updateStatus = SecItemUpdate(itemQuery as CFDictionary, update as CFDictionary)

        switch updateStatus {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            var addQuery = itemQuery
            addQuery[kSecValueData as String] = data
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw CredentialStoreError.keychainStatus(addStatus)
            }
        default:
            throw CredentialStoreError.keychainStatus(updateStatus)
        }
    }

    func delete() throws {
        let status = SecItemDelete(itemQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw CredentialStoreError.keychainStatus(status)
        }
    }

    private var itemQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}

protocol VercelAccountDataStore {
    func clear() throws
}

struct UserDefaultsVercelAccountDataStore: VercelAccountDataStore {
    static let selectedProjectIDsKey = "VercelAnalyticsBar.selectedProjectIDs"
    static let currentProjectIDKey = "VercelAnalyticsBar.currentProjectID"
    static let analyticsRangeKey = "VercelAnalyticsBar.analyticsRange"

    private let userDefaults: UserDefaults
    private let fileManager: FileManager
    private let cacheDirectoryURL: URL

    init(
        userDefaults: UserDefaults = .standard,
        fileManager: FileManager = .default,
        applicationSupportURL: URL? = nil
    ) {
        self.userDefaults = userDefaults
        self.fileManager = fileManager

        let supportURL = applicationSupportURL
            ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        cacheDirectoryURL = supportURL
            .appendingPathComponent("VercelAnalyticsBar", isDirectory: true)
            .appendingPathComponent("Cache", isDirectory: true)
    }

    func clear() throws {
        [
            Self.selectedProjectIDsKey,
            Self.currentProjectIDKey,
            Self.analyticsRangeKey,
        ].forEach(userDefaults.removeObject(forKey:))

        guard fileManager.fileExists(atPath: cacheDirectoryURL.path) else {
            return
        }
        try fileManager.removeItem(at: cacheDirectoryURL)
    }
}
