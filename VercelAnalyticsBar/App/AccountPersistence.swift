import Foundation
import Security
import VercelAnalyticsCore

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
    private let keychain: any KeychainAccessing

    init(
        service: String = Self.defaultService,
        account: String = Self.defaultAccount,
        keychain: any KeychainAccessing = SystemKeychain()
    ) {
        self.service = service
        self.account = account
        self.keychain = keychain
    }

    func read() throws -> String? {
        if let token = try read(query: protectedItemQuery) {
            try deleteLegacyItem()
            return token
        }

        guard let legacyToken = try read(query: legacyItemQuery) else { return nil }
        try save(legacyToken)
        return legacyToken
    }

    func save(_ token: String) throws {
        let normalizedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedToken.isEmpty else {
            throw CredentialStoreError.invalidToken
        }

        guard let data = normalizedToken.data(using: .utf8) else {
            throw CredentialStoreError.invalidToken
        }

        let update: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]
        let updateStatus = keychain.update(protectedItemQuery, attributes: update)

        switch updateStatus {
        case errSecSuccess:
            try deleteLegacyItem()
        case errSecItemNotFound:
            var addQuery = protectedItemQuery
            addQuery[kSecValueData as String] = data
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            let addStatus = keychain.add(addQuery)
            guard addStatus == errSecSuccess else {
                throw CredentialStoreError.keychainStatus(addStatus)
            }
            try deleteLegacyItem()
        default:
            throw CredentialStoreError.keychainStatus(updateStatus)
        }
    }

    func delete() throws {
        let statuses = [protectedItemQuery, legacyItemQuery].map(keychain.delete)
        if let failure = statuses.first(where: { $0 != errSecSuccess && $0 != errSecItemNotFound }) {
            throw CredentialStoreError.keychainStatus(failure)
        }
    }

    var protectedItemQuery: [String: Any] {
        var query = legacyItemQuery
        query[kSecUseDataProtectionKeychain as String] = true
        return query
    }

    var legacyItemQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    private func read(query: [String: Any]) throws -> String? {
        var query = query
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        let (status, data) = keychain.copyMatching(query)

        switch status {
        case errSecItemNotFound:
            return nil
        case errSecSuccess:
            guard let data,
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

    private func deleteLegacyItem() throws {
        let status = keychain.delete(legacyItemQuery)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw CredentialStoreError.keychainStatus(status)
        }
    }
}

protocol KeychainAccessing {
    func copyMatching(_ query: [String: Any]) -> (OSStatus, Data?)
    func update(_ query: [String: Any], attributes: [String: Any]) -> OSStatus
    func add(_ attributes: [String: Any]) -> OSStatus
    func delete(_ query: [String: Any]) -> OSStatus
}

struct SystemKeychain: KeychainAccessing {
    func copyMatching(_ query: [String: Any]) -> (OSStatus, Data?) {
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        return (status, result as? Data)
    }

    func update(_ query: [String: Any], attributes: [String: Any]) -> OSStatus {
        SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
    }

    func add(_ attributes: [String: Any]) -> OSStatus {
        SecItemAdd(attributes as CFDictionary, nil)
    }

    func delete(_ query: [String: Any]) -> OSStatus {
        SecItemDelete(query as CFDictionary)
    }
}

protocol VercelAccountDataStore: ProjectSelectionPersisting {
    func readAnalyticsRange() throws -> VercelAnalyticsRange
    func saveAnalyticsRange(_ range: VercelAnalyticsRange) throws
    func clear() throws
}

enum AccountDataStoreError: Error, Equatable, LocalizedError {
    case invalidProjectSelection
    case invalidAnalyticsRange

    var errorDescription: String? {
        switch self {
        case .invalidProjectSelection:
            "The saved Vercel project selection could not be read."
        case .invalidAnalyticsRange:
            "The saved analytics range could not be read."
        }
    }
}

struct UserDefaultsVercelAccountDataStore: VercelAccountDataStore {
    static let projectSelectionKey = "VercelAnalyticsBar.projectSelection"
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

    func readProjectSelection() throws -> ProjectSelection {
        if let value = userDefaults.object(forKey: Self.projectSelectionKey) {
            guard let data = value as? Data,
                  let record = try? JSONDecoder().decode(ProjectSelectionRecord.self, from: data),
                  record.version == ProjectSelectionRecord.currentVersion,
                  record.selectedProjectIDs.allSatisfy(Self.isValidProjectID),
                  record.currentProjectID.map(Self.isValidProjectID) ?? true,
                  record.currentProjectID.map(record.selectedProjectIDs.contains) ?? true
            else {
                throw AccountDataStoreError.invalidProjectSelection
            }
            return record.selection
        }

        return try migrateLegacyProjectSelection()
    }

    func saveProjectSelection(_ selection: ProjectSelection) throws {
        guard selection.selectedProjectIDs.allSatisfy(Self.isValidProjectID),
              selection.currentProjectID.map(Self.isValidProjectID) ?? true,
              selection.currentProjectID.map(selection.selectedProjectIDs.contains) ?? true
        else {
            throw AccountDataStoreError.invalidProjectSelection
        }

        let record = ProjectSelectionRecord(selection: selection)
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        guard let data = try? encoder.encode(record) else {
            throw AccountDataStoreError.invalidProjectSelection
        }
        userDefaults.set(data, forKey: Self.projectSelectionKey)
        removeLegacyProjectSelection()
    }

    func readAnalyticsRange() throws -> VercelAnalyticsRange {
        guard let value = userDefaults.object(forKey: Self.analyticsRangeKey) else {
            return .last7Days
        }
        guard let rawValue = value as? String,
              let range = VercelAnalyticsRange(rawValue: rawValue)
        else {
            throw AccountDataStoreError.invalidAnalyticsRange
        }
        return range
    }

    func saveAnalyticsRange(_ range: VercelAnalyticsRange) throws {
        userDefaults.set(range.rawValue, forKey: Self.analyticsRangeKey)
    }

    func clear() throws {
        [
            Self.projectSelectionKey,
            Self.selectedProjectIDsKey,
            Self.currentProjectIDKey,
            Self.analyticsRangeKey,
        ].forEach(userDefaults.removeObject(forKey:))

        guard fileManager.fileExists(atPath: cacheDirectoryURL.path) else {
            return
        }
        try fileManager.removeItem(at: cacheDirectoryURL)
    }

    private func migrateLegacyProjectSelection() throws -> ProjectSelection {
        let selectedValue = userDefaults.object(forKey: Self.selectedProjectIDsKey)
        let currentValue = userDefaults.object(forKey: Self.currentProjectIDKey)
        guard selectedValue != nil || currentValue != nil else { return .empty }

        guard selectedValue == nil || selectedValue is [String],
              currentValue == nil || currentValue is String
        else {
            throw AccountDataStoreError.invalidProjectSelection
        }

        let legacySelectedProjectIDs = selectedValue as? [String] ?? []
        let legacyCurrentProjectID = currentValue as? String
        guard legacySelectedProjectIDs.allSatisfy(Self.isValidProjectID),
              legacyCurrentProjectID.map(Self.isValidProjectID) ?? true
        else {
            throw AccountDataStoreError.invalidProjectSelection
        }

        var selectedProjectIDs = Set(legacySelectedProjectIDs)
        if let legacyCurrentProjectID {
            selectedProjectIDs.insert(legacyCurrentProjectID)
        }
        let selection = ProjectSelection(
            selectedProjectIDs: selectedProjectIDs,
            currentProjectID: legacyCurrentProjectID
        )
        try saveProjectSelection(selection)
        return selection
    }

    private func removeLegacyProjectSelection() {
        userDefaults.removeObject(forKey: Self.selectedProjectIDsKey)
        userDefaults.removeObject(forKey: Self.currentProjectIDKey)
    }

    private static func isValidProjectID(_ projectID: String) -> Bool {
        !projectID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

private struct ProjectSelectionRecord: Codable {
    static let currentVersion = 1

    let version: Int
    let selectedProjectIDs: [String]
    let currentProjectID: String?

    init(selection: ProjectSelection) {
        version = Self.currentVersion
        selectedProjectIDs = selection.selectedProjectIDs.sorted()
        currentProjectID = selection.currentProjectID
    }

    var selection: ProjectSelection {
        ProjectSelection(
            selectedProjectIDs: Set(selectedProjectIDs),
            currentProjectID: currentProjectID
        )
    }
}
