import Foundation

/// Pass executableURL and arguments directly to Process. No shell quoting or execution is performed.
public struct BrowserCommand: Equatable, Sendable {
    public let executableURL: URL
    public let arguments: [String]
}

public enum BrowserCommandBuilder {
    /// URL operands follow `--` and remain separate arguments, including spaces and shell metacharacters.
    /// Bookmarklets and other absolute schemes are preserved; callers choose which URLs to offer to users.
    public static func arguments(userDataURL: URL? = nil, profileDirectory: String? = nil, newWindow: Bool = false,
                                 incognito: Bool = false, urls: [URL] = []) throws -> [String] {
        var result: [String] = []
        if let userDataURL {
            guard userDataURL.isFileURL,
                  !userDataURL.path.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
                throw ChromiumSupportError.unsafePath(userDataURL.absoluteString)
            }
            result.append("--user-data-dir=\(userDataURL.path)")
        }
        if let profileDirectory {
            try SafePaths.validateComponent(profileDirectory)
            result.append("--profile-directory=\(profileDirectory)")
        }
        if newWindow { result.append("--new-window") }
        if incognito { result.append("--incognito") }
        if !urls.isEmpty {
            result.append("--")
            for url in urls {
                let value = url.absoluteString
                guard url.scheme != nil, !value.hasPrefix("-"),
                      !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
                    throw ChromiumSupportError.invalidURL(value)
                }
                result.append(value)
            }
        }
        return result
    }

    /// Resolves CFBundleExecutable inside the configured application and selects its configured user data.
    /// Does not launch the browser or require the profile to exist yet.
    public static func command(browser: BrowserConfiguration, profile: BrowserProfile? = nil,
                               newWindow: Bool = false, incognito: Bool = false,
                               urls: [URL] = []) throws -> BrowserCommand {
        if let profile, profile.browser != browser { throw ChromiumSupportError.profileBrowserMismatch }
        let arguments = try arguments(userDataURL: browser.userDataURL, profileDirectory: profile?.directoryName, newWindow: newWindow,
                                      incognito: incognito, urls: urls)
        let infoURL = browser.applicationURL.appendingPathComponent("Contents/Info.plist")
        try SafePaths.readableFile(infoURL, in: browser.applicationURL)
        guard let info = try PropertyListSerialization.propertyList(from: Data(contentsOf: infoURL),
                                                                   format: nil) as? [String: Any],
              let name = info["CFBundleExecutable"] as? String else {
            throw ChromiumSupportError.invalidApplication
        }
        try SafePaths.validateComponent(name)
        let executable = browser.applicationURL.appendingPathComponent("Contents/MacOS").appendingPathComponent(name)
        try SafePaths.readableFile(executable, in: browser.applicationURL)
        guard FileManager.default.isExecutableFile(atPath: executable.path) else {
            throw ChromiumSupportError.invalidApplication
        }
        return BrowserCommand(executableURL: executable, arguments: arguments)
    }
}
