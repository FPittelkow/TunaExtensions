import Foundation
import Testing
@testable import ChromiumExtensionSupport

struct SnapshotLoaderTests {
    @Test func partialFailuresAndRecovery() async throws {
        let fixture = try Fixture()
        let good = try fixture.profile()
        let malformed = try fixture.profile("Profile 1")
        let missing = try fixture.profile("Profile 2")
        try fixture.localState(["Default": [:], "Profile 1": [:], "Profile 2": [:], "Gone": [:]])
        try fixture.bookmarks(bookmarksData([bookmark(), ["type": "bad"]]), profile: good)
        try fixture.bookmarks(Data("{".utf8), profile: malformed)
        let loader = SnapshotLoader()
        let first = try await loader.load(browser: fixture.browser)
        #expect(first.browser == fixture.browser)
        #expect(first.profiles.map(\.profile) == [try BrowserProfile(browser: fixture.browser, directoryName: "Default", displayName: "Default")])
        #expect(first.bookmarks.count == 1)
        #expect(first.profiles[0].issues.count == 1)
        #expect(first.failures.map(\.profile.directoryName) == ["Profile 1", "Profile 2"])
        #expect(first.discoveryIssues.map(\.directoryName) == ["Gone"])
        try fixture.bookmarks(bookmarksData([]), profile: malformed)
        try fixture.bookmarks(bookmarksData([]), profile: missing)
        let second = try await loader.load(browser: fixture.browser)
        #expect(second.profiles.count == 3)
        #expect(second.profiles[0].isCached)
        #expect(second.failures.isEmpty)
    }

    @Test func cacheHitModificationAndExplicitInvalidation() async throws {
        let fixture = try Fixture()
        let profile = try fixture.profile()
        try fixture.bookmarks(bookmarksData([bookmark()]), profile: profile)
        let loader = SnapshotLoader()
        #expect(try await !loader.load(profile: profile).isCached)
        #expect(try await loader.load(profile: profile).isCached)
        try fixture.bookmarks(bookmarksData([bookmark(name: "Changed title with a different size")]), profile: profile)
        let changed = try await loader.load(profile: profile)
        #expect(!changed.isCached)
        #expect(changed.bookmarks[0].title == "Changed title with a different size")
        #expect(try await loader.load(profile: profile).isCached)
        await loader.invalidateCache()
        #expect(try await !loader.load(profile: profile).isCached)
    }

    @Test func modificationDateInvalidatesSameSizeContent() async throws {
        let fixture = try Fixture()
        let profile = try fixture.profile()
        try fixture.bookmarks(bookmarksData([bookmark(name: "AAAA")]), profile: profile)
        let loader = SnapshotLoader()
        _ = try await loader.load(profile: profile)
        try fixture.bookmarks(bookmarksData([bookmark(name: "BBBB")]), profile: profile)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 100)],
                                               ofItemAtPath: profile.directoryURL.appendingPathComponent("Bookmarks").path)
        let result = try await loader.load(profile: profile)
        #expect(!result.isCached)
        #expect(result.bookmarks[0].title == "BBBB")
    }

    @Test func deletedAndMalformedFilesNeverReturnStaleCache() async throws {
        let fixture = try Fixture()
        let profile = try fixture.profile()
        let loader = SnapshotLoader()
        let data = try bookmarksData([bookmark()])
        try fixture.bookmarks(data, profile: profile)
        _ = try await loader.load(profile: profile)
        try FileManager.default.removeItem(at: profile.directoryURL.appendingPathComponent("Bookmarks"))
        await #expect(throws: (any Error).self) { try await loader.load(profile: profile) }
        try fixture.bookmarks(data, profile: profile)
        #expect(try await !loader.load(profile: profile).isCached)
        try fixture.bookmarks(Data("broken".utf8), profile: profile)
        await #expect(throws: (any Error).self) { try await loader.load(profile: profile) }
        try fixture.bookmarks(data, profile: profile)
        #expect(try await !loader.load(profile: profile).isCached)
    }

    @Test func escapingBookmarkSymlinkRejectedEvenAfterCaching() async throws {
        let fixture = try Fixture()
        let profile = try fixture.profile()
        let data = try bookmarksData([bookmark()])
        try fixture.bookmarks(data, profile: profile)
        let loader = SnapshotLoader()
        _ = try await loader.load(profile: profile)
        let outside = fixture.root.appendingPathComponent("outside.json")
        try data.write(to: outside)
        let file = profile.directoryURL.appendingPathComponent("Bookmarks")
        try FileManager.default.removeItem(at: file)
        try FileManager.default.createSymbolicLink(at: file, withDestinationURL: outside)
        await #expect(throws: (any Error).self) { try await loader.load(profile: profile) }
    }

    @Test func containedBookmarkSymlinkTracksTargetMetadata() async throws {
        let fixture = try Fixture()
        let profile = try fixture.profile()
        let target = profile.directoryURL.appendingPathComponent("Bookmarks.actual")
        try bookmarksData([bookmark()]).write(to: target)
        try FileManager.default.createSymbolicLink(at: profile.directoryURL.appendingPathComponent("Bookmarks"),
                                                  withDestinationURL: target)
        let loader = SnapshotLoader()
        #expect(try await !loader.load(profile: profile).isCached)
        #expect(try await loader.load(profile: profile).isCached)
        try bookmarksData([bookmark(name: "Changed symlink target")]).write(to: target)
        let changed = try await loader.load(profile: profile)
        #expect(!changed.isCached)
        #expect(changed.bookmarks[0].title == "Changed symlink target")
    }

    @Test func directoryAndUnreadableFilesRejected() async throws {
        let fixture = try Fixture()
        let profile = try fixture.profile()
        let file = profile.directoryURL.appendingPathComponent("Bookmarks")
        let loader = SnapshotLoader()
        try FileManager.default.createDirectory(at: file, withIntermediateDirectories: true)
        await #expect(throws: (any Error).self) { try await loader.load(profile: profile) }
        try FileManager.default.removeItem(at: file)
        try fixture.bookmarks(bookmarksData([bookmark()]), profile: profile)
        _ = try await loader.load(profile: profile)
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: file.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path) }
        // Privileged runners may still read mode-000 files; test denial when the OS enforces it.
        if !FileManager.default.isReadableFile(atPath: file.path) {
            await #expect(throws: (any Error).self) { try await loader.load(profile: profile) }
        }
    }

    @Test func cachesKeepBrowsersAndProfilesSeparate() async throws {
        let first = try Fixture()
        let second = try Fixture(id: "another-browser")
        let profiles = try [first.profile(), first.profile("Profile 1"), second.profile()]
        try first.bookmarks(bookmarksData([bookmark(name: "first")]), profile: profiles[0])
        try first.bookmarks(bookmarksData([bookmark(name: "second")]), profile: profiles[1])
        try second.bookmarks(bookmarksData([bookmark(name: "third")]), profile: profiles[2])
        let loader = SnapshotLoader()
        for (index, profile) in profiles.enumerated() {
            let result = try await loader.load(profile: profile)
            #expect(result.bookmarks[0].title == ["first", "second", "third"][index])
            #expect(!result.isCached)
        }
        for profile in profiles { #expect(try await loader.load(profile: profile).isCached) }
    }

    @Test func missingLocalStateThrows() async throws {
        let fixture = try Fixture()
        await #expect(throws: (any Error).self) { try await SnapshotLoader().load(browser: fixture.browser) }
    }
}
