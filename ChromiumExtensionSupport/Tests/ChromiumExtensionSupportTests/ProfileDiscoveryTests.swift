import Foundation
import Testing
@testable import ChromiumExtensionSupport

struct ProfileDiscoveryTests {
    @Test func orderingNamesAndStaleEntries() throws {
        let fixture = try Fixture()
        _ = try fixture.profile()
        _ = try fixture.profile("Profile 2")
        _ = try fixture.profile("Profile 1")
        try fixture.localState(["Default": ["name": "Personal"], "Profile 1": [:], "Profile 2": ["name": ""]],
                               order: ["Profile 2", "gone", "Profile 2"])
        let result = try ProfileDiscovery.discover(browser: fixture.browser)
        #expect(result.profiles.map(\.directoryName) == ["Profile 2", "Default", "Profile 1"])
        #expect(result.profiles.map(\.displayName) == ["Profile 2", "Personal", "Profile 1"])
        #expect(result.profiles.allSatisfy { $0.browser == fixture.browser })
        #expect(result.issues.isEmpty)
    }

    @Test func missingOrderUsesSortedCacheAndEmptyCacheIsValid() throws {
        let fixture = try Fixture()
        _ = try fixture.profile()
        let data = try json(["profile": ["info_cache": ["Default": [:]]]])
        #expect(try ProfileDiscovery.discover(data: data, browser: fixture.browser).profiles.count == 1)
        try fixture.localState([:])
        #expect(try ProfileDiscovery.discover(browser: fixture.browser).profiles.isEmpty)
    }

    @Test(arguments: ["", ".", "..", "../outside", "/absolute", "Profile/1", "Profile\\1", "bad\nname", "bad\0name"])
    func unsafeDirectoryNames(name: String) throws {
        let fixture = try Fixture()
        #expect(throws: ChromiumSupportError.invalidDirectoryName(name)) {
            try BrowserProfile(browser: fixture.browser, directoryName: name, displayName: "Invalid")
        }
    }

    @Test func invalidProfilesDoNotHideValidProfiles() throws {
        let fixture = try Fixture()
        _ = try fixture.profile()
        let outside = fixture.root.appendingPathComponent("User Data Neighbor")
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: fixture.browser.userDataURL.appendingPathComponent("Escape"),
                                                  withDestinationURL: outside)
        try Data().write(to: fixture.browser.userDataURL.appendingPathComponent("NotDirectory"))
        try fixture.localState(["Default": [:], "../User Data Neighbor": [:], "Escape": [:],
                                "Missing": [:], "NotDirectory": [:], "Malformed": 7])
        let result = try ProfileDiscovery.discover(browser: fixture.browser)
        #expect(result.profiles.map(\.directoryName) == ["Default"])
        #expect(result.issues.count == 5)
    }

    @Test(arguments: ["{}", "[]", "{", "{\"profile\":{\"info_cache\":[]}}"])
    func malformedLocalState(data: String) throws {
        let fixture = try Fixture()
        #expect(throws: (any Error).self) {
            try ProfileDiscovery.discover(data: Data(data.utf8), browser: fixture.browser)
        }
    }

    @Test func missingOrEscapingLocalStateFails() throws {
        let fixture = try Fixture()
        #expect(throws: (any Error).self) { try ProfileDiscovery.discover(browser: fixture.browser) }
        let outside = fixture.root.appendingPathComponent("outside.json")
        try json(["profile": ["info_cache": [:]]]).write(to: outside)
        try FileManager.default.createSymbolicLink(at: fixture.browser.userDataURL.appendingPathComponent("Local State"),
                                                  withDestinationURL: outside)
        #expect(throws: (any Error).self) { try ProfileDiscovery.discover(browser: fixture.browser) }
    }

    @Test func containedDirectorySymlinksAndMixedOrderEntries() throws {
        let fixture = try Fixture()
        _ = try fixture.profile()
        try FileManager.default.createSymbolicLink(at: fixture.browser.userDataURL.appendingPathComponent("Alias"),
                                                  withDestinationURL: fixture.browser.userDataURL.appendingPathComponent("Default"))
        let data = try json(["profile": ["info_cache": ["Default": [:], "Alias": [:]],
                                         "profiles_order": [7, "Default", false, "Alias"]]])
        let result = try ProfileDiscovery.discover(data: data, browser: fixture.browser)
        #expect(result.profiles.map(\.directoryName) == ["Default", "Alias"])
        #expect(result.issues.isEmpty)
    }
}
