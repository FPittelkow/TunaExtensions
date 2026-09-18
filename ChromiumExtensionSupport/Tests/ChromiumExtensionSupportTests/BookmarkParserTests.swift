import Foundation
import Testing
@testable import ChromiumExtensionSupport

struct BookmarkParserTests {
    @Test func recursiveRootsAndProvenance() throws {
        let fixture = try Fixture()
        let profile = try fixture.profile("Profile 1", name: "Work")
        let data = try json(["roots": [
            "other": folder([bookmark("3", guid: "c")]),
            "bookmark_bar": folder([bookmark(), folder([folder([bookmark("2", guid: "b", name: "雪")], name: "Inner")], name: "Outer")])
        ]])
        let result = try BookmarkParser.parse(data, profile: profile)
        #expect(result.bookmarks.map(\.nativeID) == ["1", "2", "3"])
        #expect(result.bookmarks[1].folderPath == ["bookmark_bar", "Outer", "Inner"])
        #expect(result.bookmarks[1].title == "雪")
        #expect(result.bookmarks.allSatisfy { $0.profile == profile && $0.browser == fixture.browser })
        #expect(result.issues.isEmpty)
    }

    @Test func identitiesSurviveRenamingMovingAndReordering() throws {
        let fixture = try Fixture()
        let profile = try fixture.profile()
        let initial = try BookmarkParser.parse(bookmarksData([bookmark()]), profile: profile).bookmarks[0]
        let renamed = try BrowserProfile(browser: fixture.browser, directoryName: "Default", displayName: "New name")
        let moved = try BookmarkParser.parse(bookmarksData([folder([bookmark("999", name: "Renamed", url: "https://changed.test")])]),
                                              profile: renamed).bookmarks[0]
        #expect(initial.id == moved.id)
        let fallback = try BookmarkParser.parse(bookmarksData([bookmark(guid: nil)]), profile: profile).bookmarks[0]
        let fallbackMoved = try BookmarkParser.parse(bookmarksData([folder([bookmark(guid: nil, name: "Other")])]), profile: profile).bookmarks[0]
        #expect(fallback.id == fallbackMoved.id)
        #expect(fallback.id != initial.id)
    }

    @Test func identitiesAreNamespacedAndDelimiterSafe() throws {
        let fixture = try Fixture()
        let first = try fixture.profile()
        let second = try fixture.profile("Profile 1")
        let other = try Fixture(id: "other-browser")
        let third = try other.profile()
        let data = try bookmarksData([bookmark()])
        let ids = try [first, second, third].map { try BookmarkParser.parse(data, profile: $0).bookmarks[0].id }
        #expect(Set(ids).count == 3)
        #expect(stableID(["a:b", "c"]) != stableID(["a", "b:c"]))
        #expect(stableID(["雪", "x"]) != stableID(["雪x", ""]))
    }

    @Test func malformedNodesAndDuplicatesPreserveValidSiblings() throws {
        let fixture = try Fixture()
        let profile = try fixture.profile()
        let nodes: [Any] = [
            1, ["type": "folder"], ["type": "unknown"],
            bookmark("2", guid: "bad-url", url: "relative/path"),
            bookmark("3", guid: "control", url: "https://example.test/\n"),
            ["type": "url", "url": "https://example.test"],
            bookmark(), bookmark(), bookmark("4", guid: nil)
        ]
        let result = try BookmarkParser.parse(bookmarksData(nodes), profile: profile)
        #expect(result.bookmarks.count == 2)
        #expect(result.issues.count == 7)
        #expect(result.issues[0].location == "bookmark_bar/0")
    }

    @Test func preservesBookmarkletsAndEmptyTitles() throws {
        let fixture = try Fixture()
        let result = try BookmarkParser.parse(bookmarksData([bookmark(name: "", url: "javascript:alert(1)")]),
                                              profile: fixture.profile())
        #expect(result.bookmarks.first?.url.scheme == "javascript")
        #expect(result.bookmarks.first?.title == "")
    }

    @Test(arguments: ["{", "[]", "{}", "{\"roots\":[]}"])
    func malformedDocuments(data: String) throws {
        let fixture = try Fixture()
        #expect(throws: (any Error).self) {
            try BookmarkParser.parse(Data(data.utf8), profile: fixture.profile())
        }
    }

    @Test func emptyRootsAreValid() throws {
        let fixture = try Fixture()
        let result = try BookmarkParser.parse(json(["roots": [:]]), profile: fixture.profile())
        #expect(result.bookmarks.isEmpty)
        #expect(result.issues.isEmpty)
    }
}
