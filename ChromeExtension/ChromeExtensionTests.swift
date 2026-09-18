import Foundation
import TunaKit
import XCTest

@testable import TunaChrome

final class ChromeExtensionTests: XCTestCase {
  @MainActor
  func testDeclarationHasProfileAwareChromeSurfaces() throws {
    let instance = try ChromeExtension(bundle: Bundle(for: ChromeExtension.self))
    let declaration = try XCTUnwrap(instance.declaration)
    try declaration.validate()

    XCTAssertEqual(
      declaration.catalogs.map(\.id),
      [
        "chrome.bookmarks", "chrome.bookmarks.browse", "chrome.profiles",
        "chrome.profiles.browse", "chrome.utilities",
      ])
    XCTAssertEqual(declaration.actionCatalogs.map(\.id), ["chrome.actions"])
    XCTAssertEqual(declaration.typeRegistrations.map(\.typeID), [.chromeURL])
    XCTAssertEqual(
      declaration.defaultActionRankings.first?.actions.map(\.actionID),
      ["open-in-chrome", "copy-url"])
    XCTAssertEqual(declaration.appBrowseEnrichments.first?.bundleIdentifiers, ["com.google.Chrome"])
    XCTAssertEqual(declaration.appActionEnrichments.first?.bundleIdentifiers, ["com.google.Chrome"])
  }

  @MainActor
  func testActionsExposeURLGrammar() {
    let catalog = ChromeActionsCatalog(
      definition: ActionCatalogDefinition(identifier: "chrome.actions", name: "Chrome Actions")
    )

    XCTAssertEqual(catalog.actions.map(\.id), ["open-in-chrome", "open-url", "copy-url"])
    XCTAssertEqual(catalog.actions[0].supportedSubjectTypes, [.url, .textSnippet])
    XCTAssertEqual(catalog.actions[1].supportedSubjectTypes, [.application])
    XCTAssertEqual(catalog.actions[1].targetRequirement, .required)
  }

  func testCurrentPageParserReadsOnlyTheURL() {
    defer { ChromeCurrentPage.runOverride = nil }
    ChromeCurrentPage.runOverride = { _ in "https://example.com/path" }

    XCTAssertEqual(ChromeCurrentPage.resolveURL()?.absoluteString, "https://example.com/path")
  }
}
