import AppKit
import Foundation
import TunaKit

public final class ChromeActionsCatalog: ActionCatalog {
  public let identifier: String
  public let name: String
  public private(set) lazy var actions: [CatalogAction] = Self.makeActions()

  public required init(definition: ActionCatalogDefinition) {
    identifier = definition.identifier
    name = definition.name
  }

  private static func makeActions() -> [CatalogAction] {
    let open = PredicateAwareAction(id: "open-in-chrome", title: "Open in Google Chrome") {
      subject, _ in
      if isCurrentPage(subject) {
        return .background(
          CommandBackgroundTask(title: "Resolving Chrome Current Page") {
            guard let url = ChromeCurrentPage.resolveURL() else {
              return .failure(message: "No Google Chrome page is available")
            }
            do {
              try ChromeLauncher.start(url: url)
              return .successWithoutResult()
            } catch {
              return .failure(message: "Google Chrome could not be opened")
            }
          })
      }
      guard let url = url(from: subject) else { return .failure("No URL to open") }
      if let bookmark = subject as? ChromeBookmarkItem {
        return ChromeLauncher.launch(profile: bookmark.bookmark.profile, url: url)
      }
      return ChromeLauncher.launch(url: url)
    }
    open.systemSymbolName = "globe"
    open.supportedSubjectTypes = [.url, .textSnippet]
    open.subjectPredicate = {
      ChromeBrowser.isInstalled && (isCurrentPage($0) || url(from: $0) != nil)
    }

    let openURL = PredicateAwareAction(id: "open-url", title: "Open URL") { _, target in
      guard let url = url(from: target) else { return .failure("No URL to open") }
      return ChromeLauncher.launch(url: url)
    }
    openURL.targetRequirement = .required
    openURL.systemSymbolName = "globe"
    openURL.supportedSubjectTypes = [.application]
    openURL.allowedTargetTypes = [.textSnippet, .url]
    openURL.subjectPredicate = isChromeApplication
    openURL.targetPredicate = { url(from: $0) != nil }

    let copy = PredicateAwareAction(id: "copy-url", title: "Copy URL") { subject, _ in
      if isCurrentPage(subject) {
        return .background(
          CommandBackgroundTask(title: "Resolving Chrome Current Page") {
            guard let resolvedURL = ChromeCurrentPage.resolveURL() else {
              return .failure(message: "No Google Chrome page is available")
            }
            let didCopy = await MainActor.run {
              NSPasteboard.general.clearContents()
              return NSPasteboard.general.setString(resolvedURL.absoluteString, forType: .string)
            }
            return didCopy
              ? .successWithoutResult()
              : .failure(message: "Failed to copy URL")
          })
      }
      guard let resolvedURL = url(from: subject) else { return .failure("No URL to copy") }
      NSPasteboard.general.clearContents()
      return NSPasteboard.general.setString(resolvedURL.absoluteString, forType: .string)
        ? .success
        : .failure("Failed to copy URL")
    }
    copy.systemSymbolName = "link"
    copy.supportedSubjectTypes = [.url, .textSnippet]
    copy.subjectPredicate = { isCurrentPage($0) || url(from: $0) != nil }

    return [open, openURL, copy]
  }

  private static func isCurrentPage(_ item: CatalogItem?) -> Bool {
    (item as? CatalogEntity)?.path == ChromeBrowser.currentPageToken
  }

  private static func isChromeApplication(_ item: CatalogItem?) -> Bool {
    guard let entity = item as? CatalogEntity,
      let path = entity.path,
      TypeRegistry.shared.inherits(entity.typeID, from: .application)
    else { return false }
    return Bundle(url: URL(fileURLWithPath: path))?.bundleIdentifier == ChromeBrowser.bundleIdentifier
  }

  private static func url(from item: CatalogItem?) -> URL? {
    guard let item else { return nil }
    let candidates = [
      item.displayTextFallback(),
      (item as? CatalogEntity)?.path,
      item.extended,
      item.detail,
      item.title,
    ]
    for candidate in candidates {
      guard let value = candidate?.trimmingCharacters(in: .whitespacesAndNewlines),
        let url = URL(string: value), url.scheme != nil
      else { continue }
      return url
    }
    return nil
  }
}
