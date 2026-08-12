import Foundation
import VercelAnalyticsCore

protocol AnalyticsSnapshotCacheStore {
    func read() throws -> [SnapshotCacheEntry]
    func write(_ entries: [SnapshotCacheEntry]) throws
    func clear() throws
}

struct SnapshotCacheEntry: Codable, Equatable, Sendable {
    let projectID: String
    let snapshot: AnalyticsSnapshot

    var key: SnapshotCacheKey {
        SnapshotCacheKey(projectID: projectID, range: snapshot.range)
    }
}

struct FileAnalyticsSnapshotCacheStore: AnalyticsSnapshotCacheStore {
    static let currentSchemaVersion = 2

    let fileURL: URL
    private let fileManager: FileManager

    init(
        fileManager: FileManager = .default,
        applicationSupportURL: URL? = nil
    ) {
        self.fileManager = fileManager
        let supportURL = applicationSupportURL
            ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        fileURL = supportURL
            .appendingPathComponent("VercelAnalyticsBar", isDirectory: true)
            .appendingPathComponent("Cache", isDirectory: true)
            .appendingPathComponent("analytics-snapshots.json")
    }

    func read() throws -> [SnapshotCacheEntry] {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return []
        }

        do {
            try secureExistingCachePermissions()
            let data = try Data(contentsOf: fileURL)
            let cache = try JSONDecoder().decode(CacheFile.self, from: data)
            guard cache.version == Self.currentSchemaVersion else {
                throw CacheFileError.incompatibleVersion
            }
            try validate(cache.entries)
            return cache.entries
        } catch {
            try? fileManager.removeItem(at: fileURL)
            return []
        }
    }

    func write(_ entries: [SnapshotCacheEntry]) throws {
        try validate(entries)
        let cache = CacheFile(version: Self.currentSchemaVersion, entries: entries)
        let data = try JSONEncoder().encode(cache)
        let directoryURL = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directoryURL.path)
        try data.write(to: fileURL, options: .atomic)
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }

    func clear() throws {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return
        }
        try fileManager.removeItem(at: fileURL)
    }

    private func validate(_ entries: [SnapshotCacheEntry]) throws {
        var keys = Set<SnapshotCacheKey>()

        for entry in entries {
            guard !entry.projectID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !entry.snapshot.projectName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  keys.insert(entry.key).inserted
            else {
                throw CacheFileError.invalidEntry
            }
        }
    }

    private func secureExistingCachePermissions() throws {
        let directoryURL = fileURL.deletingLastPathComponent()
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directoryURL.path)
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }
}

private struct CacheFile: Codable {
    let version: Int
    let entries: [SnapshotCacheEntry]
}

private enum CacheFileError: Error {
    case incompatibleVersion
    case invalidEntry
}
