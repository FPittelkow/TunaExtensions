import Foundation
import Testing
@testable import ChromiumExtensionSupport

struct BrowserCommandTests {
    @Test func profileWindowIncognitoAndURLArguments() throws {
        let url = try #require(URL(string: "https://example.test/a?q=';$(echo%20test)&x=1"))
        let args = try BrowserCommandBuilder.arguments(profileDirectory: "Profile 1", newWindow: true,
                                                      incognito: true, urls: [url])
        #expect(args == ["--profile-directory=Profile 1", "--new-window", "--incognito", "--", url.absoluteString])
        #expect(try BrowserCommandBuilder.arguments().isEmpty)
        #expect(try BrowserCommandBuilder.arguments(newWindow: true) == ["--new-window"])
        #expect(try BrowserCommandBuilder.arguments(incognito: true) == ["--incognito"])
        #expect(try BrowserCommandBuilder.arguments(profileDirectory: "Default") == ["--profile-directory=Default"])
    }

    @Test func argumentLikeProfileNamesCannotInjectFlags() throws {
        let name = "--incognito --new-window;$(echo test)"
        #expect(try BrowserCommandBuilder.arguments(profileDirectory: name) == ["--profile-directory=\(name)"])
    }

    @Test func multipleURLsAndFileURLsStaySeparate() throws {
        let urls = [URL(fileURLWithPath: "/synthetic/a file.html"), try #require(URL(string: "chrome://bookmarks"))]
        #expect(try BrowserCommandBuilder.arguments(urls: urls) == ["--"] + urls.map(\.absoluteString))
    }

    @Test(arguments: ["../Default", "bad\nname", "/tmp", "Profile\\1"])
    func invalidProfilesFail(name: String) {
        #expect(throws: (any Error).self) { try BrowserCommandBuilder.arguments(profileDirectory: name) }
    }

    @Test(arguments: ["--incognito", "relative/path", "//example.test/path"])
    func relativeAndOptionURLsFail(value: String) throws {
        let url = try #require(URL(string: value))
        #expect(throws: ChromiumSupportError.invalidURL(url.absoluteString)) {
            try BrowserCommandBuilder.arguments(urls: [url])
        }
    }

    @Test func resolvesExecutableWithoutLaunching() throws {
        let fixture = try Fixture()
        let executable = try fixture.application()
        let profile = try fixture.profile("Profile 1")
        let command = try BrowserCommandBuilder.command(browser: fixture.browser, profile: profile, incognito: true)
        #expect(command.executableURL == executable)
        #expect(command.arguments == ["--user-data-dir=\(fixture.browser.userDataURL.path)",
                                      "--profile-directory=Profile 1", "--incognito"])
    }

    @Test func userDataPathIsOneArgumentAndMustBeAFileURL() throws {
        let directory = URL(fileURLWithPath: "/synthetic/User Data;$(echo test)")
        #expect(try BrowserCommandBuilder.arguments(userDataURL: directory) == ["--user-data-dir=\(directory.path)"])
        #expect(throws: (any Error).self) {
            try BrowserCommandBuilder.arguments(userDataURL: URL(string: "https://example.test/data")!)
        }
        #expect(throws: (any Error).self) {
            try BrowserCommandBuilder.arguments(userDataURL: URL(fileURLWithPath: "/synthetic/bad\npath"))
        }
    }

    @Test func mismatchedProfileRejected() throws {
        let fixture = try Fixture()
        let other = try Fixture(id: "other")
        let profile = try other.profile()
        #expect(throws: ChromiumSupportError.profileBrowserMismatch) {
            try BrowserCommandBuilder.command(browser: fixture.browser, profile: profile)
        }
    }

    @Test func invalidOrMissingExecutableRejected() throws {
        let fixture = try Fixture()
        #expect(throws: (any Error).self) { try BrowserCommandBuilder.command(browser: fixture.browser) }
        let executable = try fixture.application()
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: executable.path)
        #expect(throws: ChromiumSupportError.invalidApplication) {
            try BrowserCommandBuilder.command(browser: fixture.browser)
        }
        _ = try fixture.application(executableName: "../../outside")
        #expect(throws: ChromiumSupportError.invalidDirectoryName("../../outside")) {
            try BrowserCommandBuilder.command(browser: fixture.browser)
        }
    }

    @Test func executableSymlinkEscapeRejected() throws {
        let fixture = try Fixture()
        let executable = try fixture.application()
        let outside = fixture.root.appendingPathComponent("outside")
        try FileManager.default.moveItem(at: executable, to: outside)
        try FileManager.default.createSymbolicLink(at: executable, withDestinationURL: outside)
        #expect(throws: (any Error).self) { try BrowserCommandBuilder.command(browser: fixture.browser) }
    }
}
