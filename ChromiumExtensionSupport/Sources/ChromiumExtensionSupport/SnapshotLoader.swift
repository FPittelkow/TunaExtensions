import Foundation

public struct ProfileSnapshot: Sendable {
    public let profile: BrowserProfile
    public let bookmarks: [BookmarkRecord]
    public let issues: [BookmarkParseIssue]
    public let isCached: Bool
}

public struct ProfileLoadFailure: Sendable {
    public let profile: BrowserProfile
    public let message: String
}

public struct BrowserSnapshot: Sendable {
    public let browser: BrowserConfiguration
    public let profiles: [ProfileSnapshot]
    public let discoveryIssues: [ProfileDiscoveryIssue]
    public let failures: [ProfileLoadFailure]
    public var bookmarks: [BookmarkRecord] { profiles.flatMap(\.bookmarks) }
}

/// Serializes cache access. Cache hits require a readable regular file with matching size and dates.
/// Metadata caching cannot detect edits that preserve all metadata; use invalidateCache() to force a read.
public actor SnapshotLoader {
    private struct Metadata: Equatable {
        let resolvedPath: String
        let size: UInt64
        let modified: Date
        let created: Date?
        let fileNumber: UInt64?

        init?(_ url: URL) {
            let resolved = url.resolvingSymlinksInPath()
            guard let attributes = try? FileManager.default.attributesOfItem(atPath: resolved.path),
                  let size = attributes[.size] as? NSNumber,
                  let modified = attributes[.modificationDate] as? Date else { return nil }
            self.resolvedPath = resolved.path
            self.size = size.uint64Value
            self.modified = modified
            self.created = attributes[.creationDate] as? Date
            self.fileNumber = (attributes[.systemFileNumber] as? NSNumber)?.uint64Value
        }
    }

    private struct CacheEntry {
        let metadata: Metadata
        let parsed: BookmarkParseResult
    }

    private var cache: [BrowserProfile: CacheEntry] = [:]

    public init() {}

    public func invalidateCache() { cache.removeAll() }

    /// A Local State failure throws; individual profile failures are returned alongside successes.
    public func load(browser: BrowserConfiguration) throws -> BrowserSnapshot {
        let discovery = try ProfileDiscovery.discover(browser: browser)
        let active = Set(discovery.profiles)
        cache = cache.filter { $0.key.browser != browser || active.contains($0.key) }
        var snapshots: [ProfileSnapshot] = []
        var failures: [ProfileLoadFailure] = []
        for profile in discovery.profiles {
            do {
                snapshots.append(try load(profile: profile))
            } catch {
                failures.append(ProfileLoadFailure(profile: profile, message: String(describing: error)))
            }
        }
        return BrowserSnapshot(browser: browser, profiles: snapshots,
                               discoveryIssues: discovery.issues, failures: failures)
    }

    public func load(profile: BrowserProfile) throws -> ProfileSnapshot {
        do {
            try SafePaths.profileDirectory(profile)
            let file = profile.directoryURL.appendingPathComponent("Bookmarks")
            try SafePaths.readableFile(file, in: profile.directoryURL)
            let before = Metadata(file)
            if let before, let entry = cache[profile], entry.metadata == before {
                return ProfileSnapshot(profile: profile, bookmarks: entry.parsed.bookmarks,
                                       issues: entry.parsed.issues, isCached: true)
            }
            let parsed = try BookmarkParser.parse(Data(contentsOf: file), profile: profile)
            if let before, before == Metadata(file) {
                cache[profile] = CacheEntry(metadata: before, parsed: parsed)
            } else {
                cache.removeValue(forKey: profile)
            }
            return ProfileSnapshot(profile: profile, bookmarks: parsed.bookmarks, issues: parsed.issues, isCached: false)
        } catch {
            cache.removeValue(forKey: profile)
            throw error
        }
    }
}
