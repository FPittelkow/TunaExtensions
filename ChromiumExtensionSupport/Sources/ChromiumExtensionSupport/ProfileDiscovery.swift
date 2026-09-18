import Foundation

public struct ProfileDiscoveryIssue: Equatable, Sendable {
    public let directoryName: String
    public let message: String
}

public struct ProfileDiscoveryResult: Sendable {
    public let profiles: [BrowserProfile]
    public let issues: [ProfileDiscoveryIssue]
}

public enum ProfileDiscovery {
    /// Reads only the explicitly configured Local State and referenced profile directories.
    public static func discover(browser: BrowserConfiguration) throws -> ProfileDiscoveryResult {
        let file = browser.userDataURL.appendingPathComponent("Local State")
        try SafePaths.readableFile(file, in: browser.userDataURL)
        return try discover(data: Data(contentsOf: file), browser: browser)
    }

    /// Uses supplied JSON, but still validates that referenced directories exist and stay in userDataURL.
    public static func discover(data: Data, browser: BrowserConfiguration) throws -> ProfileDiscoveryResult {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let profile = object["profile"] as? [String: Any],
              let cache = profile["info_cache"] as? [String: Any] else {
            throw ChromiumSupportError.invalidLocalState
        }
        let order = (profile["profiles_order"] as? [Any])?.compactMap { $0 as? String } ?? []
        var seen = Set<String>()
        // Stale order entries are ignored; unordered cache entries follow deterministically.
        let names = (order + cache.keys.sorted()).filter { cache[$0] != nil && seen.insert($0).inserted }
        var profiles: [BrowserProfile] = []
        var issues: [ProfileDiscoveryIssue] = []
        for directoryName in names {
            do {
                guard let entry = cache[directoryName] as? [String: Any] else {
                    throw ChromiumSupportError.invalidLocalState
                }
                let name = (entry["name"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? directoryName
                let profile = try BrowserProfile(browser: browser, directoryName: directoryName, displayName: name)
                try SafePaths.profileDirectory(profile)
                profiles.append(profile)
            } catch {
                issues.append(ProfileDiscoveryIssue(directoryName: directoryName, message: String(describing: error)))
            }
        }
        return ProfileDiscoveryResult(profiles: profiles, issues: issues)
    }
}
