import Foundation
@testable import ChromiumExtensionSupport

/// Every filesystem test owns a fresh temporary tree and removes it on completion.
final class Fixture {
    let root: URL
    let browser: BrowserConfiguration

    init(id: String = "test-browser") throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        browser = BrowserConfiguration(id: id, displayName: "Test Browser", bundleIdentifier: "test.browser",
                                       userDataURL: root.appendingPathComponent("User Data"),
                                       applicationURL: root.appendingPathComponent("Test Browser.app"))
        try FileManager.default.createDirectory(at: browser.userDataURL, withIntermediateDirectories: true)
    }

    deinit { try? FileManager.default.removeItem(at: root) }

    func profile(_ directory: String = "Default", name: String = "Person") throws -> BrowserProfile {
        let profile = try BrowserProfile(browser: browser, directoryName: directory, displayName: name)
        try FileManager.default.createDirectory(at: profile.directoryURL, withIntermediateDirectories: true)
        return profile
    }

    func localState(_ entries: [String: Any], order: [String] = []) throws {
        try json(["profile": ["info_cache": entries, "profiles_order": order]])
            .write(to: browser.userDataURL.appendingPathComponent("Local State"))
    }

    func bookmarks(_ data: Data, profile: BrowserProfile) throws {
        try data.write(to: profile.directoryURL.appendingPathComponent("Bookmarks"))
    }

    func application(executableName: String = "Test Browser") throws -> URL {
        let contents = browser.applicationURL.appendingPathComponent("Contents")
        let macOS = contents.appendingPathComponent("MacOS")
        try FileManager.default.createDirectory(at: macOS, withIntermediateDirectories: true)
        let plist = try PropertyListSerialization.data(fromPropertyList: ["CFBundleExecutable": executableName],
                                                       format: .xml, options: 0)
        try plist.write(to: contents.appendingPathComponent("Info.plist"))
        let executable = macOS.appendingPathComponent("Test Browser")
        try Data("synthetic executable; never run".utf8).write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        return executable
    }
}

func json(_ value: Any) throws -> Data {
    try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
}

func bookmark(_ id: String = "1", guid: String? = "guid-1", name: String = "Example",
              url: String = "https://example.test/path?q=1") -> [String: Any] {
    var node: [String: Any] = ["type": "url", "id": id, "name": name, "url": url]
    if let guid { node["guid"] = guid }
    return node
}

func folder(_ children: [Any], name: String = "Folder") -> [String: Any] {
    ["type": "folder", "name": name, "children": children]
}

func bookmarksData(_ nodes: [Any]) throws -> Data {
    try json(["roots": ["bookmark_bar": folder(nodes)]])
}
