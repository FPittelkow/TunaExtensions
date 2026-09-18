import Foundation
import TunaKit
import XCTest

@testable import TunaTwoDo

@MainActor
final class TwoDoExtensionTests: XCTestCase {
  func testDeclarationExposesTodaySourceWithGlobalScopeAndDefaultAction() throws {
    let extensionInstance = try TwoDoExtension(bundle: Bundle(for: TwoDoExtension.self))
    let declaration = try XCTUnwrap(extensionInstance.declaration)
    try declaration.validate()

    let catalog = try XCTUnwrap(declaration.catalogs.only)
    XCTAssertEqual(catalog.id, "twodo")
    XCTAssertEqual(catalog.presentation, .source)
    XCTAssertEqual(catalog.enabledByDefault, true)
    XCTAssertEqual(catalog.initialGlobalScope, .all)

    let registration = try XCTUnwrap(
      declaration.typeRegistrations.first(where: {
        $0.typeID == .twoDoFocusList
      }))
    XCTAssertEqual(registration.displayName, "2Do Focus Lists")
    XCTAssertEqual(registration.inheritsFrom, [.entity])

    let ranking = try XCTUnwrap(declaration.defaultActionRankings.only)
    XCTAssertEqual(ranking.typeID, .twoDoFocusList)
    XCTAssertEqual(ranking.actions.only?.catalogIdentifier, "twodo.actions")
    XCTAssertEqual(ranking.actions.only?.actionID, "show-in-2do")
  }

  func testCatalogExposesOnlyTheTodayFocusListItem() async throws {
    let catalog = TwoDoCatalog(
      definition: CatalogDefinition(
        identifier: "twodo",
        name: "2Do Focus Lists",
        enabledByDefault: true,
        initialGlobalScope: .all,
        settings: []
      )
    )

    await catalog.scan()

    let item = try XCTUnwrap(catalog.objects.only)
    XCTAssertEqual(item.id, "twodo.focus.today")
    XCTAssertEqual(item.title, "2Do Today")
    XCTAssertEqual(item.typeID, .twoDoFocusList)
  }

  func testTodayItemCopiesItsTwodoURL() {
    let item = TwoDoFocusListItem()
    XCTAssertEqual(item.textValue, "twodo://x-callback-url/showtoday")
    XCTAssertEqual(item.copyRepresentation, "twodo://x-callback-url/showtoday")
  }

  func testActionsExposeShowAndBothAddVariants() {
    let catalog = TwoDoActionsCatalog(
      definition: ActionCatalogDefinition(identifier: "twodo.actions", name: "2Do Actions")
    )

    XCTAssertEqual(
      Set(catalog.actions.map(\.id)), ["show-in-2do", "add-to-inbox", "add-to-today"])

    let show = catalog.actions.first(where: { $0.id == "show-in-2do" })
    XCTAssertEqual(show?.title, "Show in 2Do")
    XCTAssertEqual(show?.systemSymbolName, "sun.max")
    XCTAssertEqual(show?.supportedSubjectTypes, [.twoDoFocusList])
    XCTAssertEqual(show?.targetRequirement, CatalogActionTargetRequirement.none)
    XCTAssertFalse(show?.title.hasSuffix("…") ?? true)

    let addToInbox = catalog.actions.first(where: { $0.id == "add-to-inbox" })
    XCTAssertEqual(addToInbox?.title, "Add to 2Do Inbox")
    XCTAssertEqual(addToInbox?.systemSymbolName, "tray.and.arrow.down")
    XCTAssertEqual(addToInbox?.supportedSubjectTypes, [.textSnippet])
    XCTAssertEqual(addToInbox?.targetRequirement, CatalogActionTargetRequirement.none)

    let addToToday = catalog.actions.first(where: { $0.id == "add-to-today" })
    XCTAssertEqual(addToToday?.title, "Add to 2Do Today")
    XCTAssertEqual(addToToday?.systemSymbolName, "calendar")
    XCTAssertEqual(addToToday?.supportedSubjectTypes, [.textSnippet])
    XCTAssertEqual(addToToday?.targetRequirement, CatalogActionTargetRequirement.none)
  }

  func testAddActionsAcceptOnlyNonemptyTypedText() throws {
    let catalog = TwoDoActionsCatalog(
      definition: ActionCatalogDefinition(identifier: "twodo.actions", name: "2Do Actions")
    )

    for id in ["add-to-inbox", "add-to-today"] {
      let action = try XCTUnwrap(catalog.actions.first(where: { $0.id == id }))
      let predicate = try XCTUnwrap((action as? PredicateAwareAction)?.subjectPredicate)
      XCTAssertTrue(predicate(TextSnippetItem(text: "Buy milk")), id)
      XCTAssertFalse(predicate(TextSnippetItem(text: "   ")), id)
    }
  }

  func testAddTaskURLsPlaceTheTitleInTheInbox() {
    XCTAssertEqual(
      TwoDoURLBuilder.addTaskURL(title: "Buy milk & eggs").absoluteString,
      "twodo://x-callback-url/add?task=Buy%20milk%20%26%20eggs&forlist=Inbox")
    XCTAssertEqual(
      TwoDoURLBuilder.addTaskURL(title: "Review a+b").absoluteString,
      "twodo://x-callback-url/add?task=Review%20a%2Bb&forlist=Inbox")
    XCTAssertEqual(
      TwoDoURLBuilder.addTaskDueTodayURL(title: "Buy milk").absoluteString,
      "twodo://x-callback-url/add?task=Buy%20milk&forlist=Inbox&due=0")
  }

  func testAddToInboxAddsTypedTitleAndReportsDispatchFailure() async {
    let success = await TwoDoActionsCatalog.makeAddToInboxAction { _ in true }
      .callback(TextSnippetItem(text: "  Submit expenses  "), nil)
    guard case .success = success else {
      return XCTFail("Expected success result, got \(success)")
    }

    let dispatchFailure = await TwoDoActionsCatalog.makeAddToInboxAction { _ in false }
      .callback(TextSnippetItem(text: "Submit expenses"), nil)
    guard case .failure = dispatchFailure else {
      return XCTFail("Expected failure result, got \(dispatchFailure)")
    }

    let empty = await TwoDoActionsCatalog.makeAddToInboxAction { _ in true }
      .callback(TextSnippetItem(text: "   "), nil)
    guard case .failure(let message) = empty else {
      return XCTFail("Expected missing-title failure, got \(empty)")
    }
    XCTAssertEqual(message, "Missing task title")
  }

  func testAddToTodayAddsTypedTitleAndReportsDispatchFailure() async {
    let success = await TwoDoActionsCatalog.makeAddToTodayAction { _ in true }
      .callback(TextSnippetItem(text: "Call Sam"), nil)
    guard case .success = success else {
      return XCTFail("Expected success result, got \(success)")
    }

    let dispatchFailure = await TwoDoActionsCatalog.makeAddToTodayAction { _ in false }
      .callback(TextSnippetItem(text: "Call Sam"), nil)
    guard case .failure = dispatchFailure else {
      return XCTFail("Expected failure result, got \(dispatchFailure)")
    }
  }

  func testShowActionSucceedsWhenDispatchSucceeds() async {
    let action = TwoDoActionsCatalog.makeShowAction { _ in true }
    let result = await action.callback(TwoDoFocusListItem(), nil)

    guard case .success = result else {
      return XCTFail("Expected success result, got \(result)")
    }
  }

  func testShowActionReportsDispatchFailureHonestly() async {
    let action = TwoDoActionsCatalog.makeShowAction { _ in false }
    let result = await action.callback(TwoDoFocusListItem(), nil)

    guard case .failure(let message) = result else {
      return XCTFail("Expected failure result, got \(result)")
    }
    XCTAssertNotNil(message)
  }

  func testTodayURLMatchesTheDocumentedScheme() {
    XCTAssertEqual(TwoDoURLBuilder.todayURL.absoluteString, "twodo://x-callback-url/showtoday")
    XCTAssertEqual(TwoDoURLBuilder.todayURL.scheme, "twodo")
  }
}

extension Collection {
  fileprivate var only: Element? { count == 1 ? first : nil }
}
