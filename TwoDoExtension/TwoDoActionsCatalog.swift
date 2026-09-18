import AppKit
import Foundation
import TunaKit

public final class TwoDoActionsCatalog: NSObject, ActionCatalog {
  public let identifier: String
  public let name: String
  public private(set) lazy var actions: [CatalogAction] = [
    Self.makeShowAction(), Self.makeAddToInboxAction(), Self.makeAddToTodayAction(),
  ]

  public required init(definition: ActionCatalogDefinition) {
    identifier = definition.identifier
    name = definition.name
    super.init()
  }

  static func makeShowAction(
    open: @escaping (URL) async -> Bool = { url in
      await MainActor.run { NSWorkspace.shared.open(url) }
    }
  ) -> PredicateAwareAction {
    let action = PredicateAwareAction(id: "show-in-2do", title: "Show in 2Do") { subject, _ in
      guard subject is TwoDoFocusListItem else {
        return .failure("No 2Do Focus List selected")
      }
      guard await open(TwoDoURLBuilder.todayURL) else {
        return .failure("Could not open 2Do. Install 2Do for Mac and try again.")
      }
      return .success
    }
    action.systemSymbolName = "sun.max"
    action.supportedSubjectTypes = [.twoDoFocusList]
    action.subjectPredicate = { $0 is TwoDoFocusListItem }
    action.targetRequirement = .none
    return action
  }

  static func makeAddToInboxAction(
    open: @escaping (URL) async -> Bool = { url in
      await MainActor.run { NSWorkspace.shared.open(url) }
    }
  ) -> PredicateAwareAction {
    makeAddAction(
      id: "add-to-inbox",
      title: "Add to 2Do Inbox",
      symbolName: "tray.and.arrow.down",
      url: TwoDoURLBuilder.addTaskURL(title:),
      open: open)
  }

  static func makeAddToTodayAction(
    open: @escaping (URL) async -> Bool = { url in
      await MainActor.run { NSWorkspace.shared.open(url) }
    }
  ) -> PredicateAwareAction {
    makeAddAction(
      id: "add-to-today",
      title: "Add to 2Do Today",
      symbolName: "calendar",
      url: TwoDoURLBuilder.addTaskDueTodayURL(title:),
      open: open)
  }

  private static func makeAddAction(
    id: String,
    title: String,
    symbolName: String,
    url: @escaping (String) -> URL,
    open: @escaping (URL) async -> Bool
  ) -> PredicateAwareAction {
    let action = PredicateAwareAction(id: id, title: title) { subject, _ in
      guard let taskTitle = taskTitle(from: subject) else {
        return .failure("Missing task title")
      }
      guard await open(url(taskTitle)) else {
        return .failure("Could not open 2Do. Install 2Do for Mac and try again.")
      }
      return .success
    }
    action.systemSymbolName = symbolName
    action.supportedSubjectTypes = [.textSnippet]
    action.subjectPredicate = { taskTitle(from: $0) != nil }
    action.targetRequirement = .none
    return action
  }

  static func taskTitle(from subject: CatalogItem?) -> String? {
    guard
      let title = subject?.textInputValue()?.trimmingCharacters(in: .whitespacesAndNewlines),
      !title.isEmpty
    else { return nil }
    return title
  }
}

enum TwoDoURLBuilder {
  static var todayURL: URL {
    var components = URLComponents()
    components.scheme = "twodo"
    components.host = "x-callback-url"
    components.path = "/showtoday"
    return components.url!
  }

  static func addTaskURL(title: String) -> URL {
    addURL(title: title, due: nil)
  }

  static func addTaskDueTodayURL(title: String) -> URL {
    addURL(title: title, due: "0")
  }

  private static func addURL(title: String, due: String?) -> URL {
    var components = URLComponents()
    components.scheme = "twodo"
    components.host = "x-callback-url"
    components.path = "/add"
    var queryItems = [
      percentEncodedQueryItem(name: "task", value: title),
      percentEncodedQueryItem(name: "forlist", value: "Inbox"),
    ]
    if let due {
      queryItems.append(URLQueryItem(name: "due", value: due))
    }
    components.percentEncodedQueryItems = queryItems
    return components.url!
  }

  /// Percent-encodes a query value using only RFC 3986 unreserved characters, so literal "+"
  /// is escaped to "%2B" instead of being left ambiguous with encoded spaces (unlike
  /// `URLQueryItem`'s default `.urlQueryAllowed` encoding, which leaves "+" untouched).
  private static func percentEncodedQueryItem(name: String, value: String) -> URLQueryItem {
    URLQueryItem(
      name: name,
      value: value.addingPercentEncoding(withAllowedCharacters: .rfc3986Unreserved) ?? value)
  }
}

extension CharacterSet {
  fileprivate static let rfc3986Unreserved = CharacterSet(
    charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
}
