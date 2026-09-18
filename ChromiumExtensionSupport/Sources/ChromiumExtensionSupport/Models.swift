import Foundation

/// Explicit paths keep each browser extension independent of system or user defaults.
public struct BrowserConfiguration: Hashable, Sendable {
    public let id: String
    public let displayName: String
    public let bundleIdentifier: String
    public let userDataURL: URL
    public let applicationURL: URL

    public init(id: String, displayName: String, bundleIdentifier: String,
                userDataURL: URL, applicationURL: URL) {
        self.id = id
        self.displayName = displayName
        self.bundleIdentifier = bundleIdentifier
        self.userDataURL = userDataURL
        self.applicationURL = applicationURL
    }
}

public struct BrowserProfile: Hashable, Sendable, Identifiable {
    public let browser: BrowserConfiguration
    public let directoryName: String
    public let displayName: String
    public var id: String { stableID([browser.id, directoryName]) }
    public var directoryURL: URL { browser.userDataURL.appendingPathComponent(directoryName, isDirectory: true) }

    /// Validates the directory name; discovery and loading also check filesystem containment.
    public init(browser: BrowserConfiguration, directoryName: String, displayName: String) throws {
        try SafePaths.validateComponent(directoryName)
        self.browser = browser
        self.directoryName = directoryName
        self.displayName = displayName
    }
}

public struct BookmarkRecord: Hashable, Sendable, Identifiable {
    public let id: String
    public let profile: BrowserProfile
    public var browser: BrowserConfiguration { profile.browser }
    public let title: String
    public let url: URL
    public let guid: String?
    public let nativeID: String?
    /// Root key followed by the names of enclosing folders, in order.
    public let folderPath: [String]
}

public enum ChromiumSupportError: Error, Equatable, Sendable {
    case invalidDirectoryName(String)
    case unsafePath(String)
    case invalidLocalState
    case invalidBookmarks
    case invalidURL(String)
    case invalidApplication
    case profileBrowserMismatch
}

// Length prefixes avoid collisions even when identifiers contain delimiters.
func stableID(_ components: [String]) -> String {
    components.map { "\($0.utf8.count):\($0)" }.joined()
}

enum SafePaths {
    static func validateComponent(_ name: String) throws {
        guard !name.isEmpty, name != ".", name != "..",
              !name.contains("/"), !name.contains("\\"),
              !name.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
            throw ChromiumSupportError.invalidDirectoryName(name)
        }
    }

    static func contained(_ candidate: URL, in root: URL) throws {
        guard root.isFileURL, candidate.isFileURL else {
            throw ChromiumSupportError.unsafePath(candidate.absoluteString)
        }
        let base = root.standardizedFileURL.resolvingSymlinksInPath().pathComponents
        let path = candidate.standardizedFileURL.resolvingSymlinksInPath().pathComponents
        guard path.count > base.count, path.starts(with: base) else {
            throw ChromiumSupportError.unsafePath(candidate.path)
        }
    }

    static func profileDirectory(_ profile: BrowserProfile) throws {
        try validateComponent(profile.directoryName)
        try contained(profile.directoryURL, in: profile.browser.userDataURL)
        let values = try profile.directoryURL.resolvingSymlinksInPath().resourceValues(forKeys: [.isDirectoryKey])
        guard values.isDirectory == true else {
            throw ChromiumSupportError.unsafePath(profile.directoryURL.path)
        }
    }

    static func readableFile(_ file: URL, in root: URL) throws {
        try contained(file, in: root)
        let values = try file.resolvingSymlinksInPath().resourceValues(forKeys: [.isRegularFileKey])
        guard values.isRegularFile == true, FileManager.default.isReadableFile(atPath: file.path) else {
            throw ChromiumSupportError.unsafePath(file.path)
        }
    }
}
