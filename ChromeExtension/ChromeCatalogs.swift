import AppKit
import ChromiumExtensionSupport
import Foundation
import TunaKit

enum ChromeBrowser {
  static let bundleIdentifier = "com.google.Chrome"
  static let currentPageToken = "tuna.runtime.chrome-current-page"

  static var configuration: BrowserConfiguration {
    let home = FileManager.default.homeDirectoryForCurrentUser
    let applicationURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)
      ?? URL(fileURLWithPath: "/Applications/Google Chrome.app", isDirectory: true)
    return BrowserConfiguration(
      id: "chrome",
      displayName: "Google Chrome",
      bundleIdentifier: bundleIdentifier,
      userDataURL: home.appending(path: "Library/Application Support/Google/Chrome", directoryHint: .isDirectory),
      applicationURL: applicationURL
    )
  }

  static var isInstalled: Bool {
    NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) != nil
      || FileManager.default.fileExists(atPath: "/Applications/Google Chrome.app")
  }
}

private enum ChromeCatalogMode {
  case source
  case browse
}

public final class ChromeBookmarksCatalog: ChromeBookmarksCatalogBase {
  public required init(definition: CatalogDefinition) {
    super.init(definition: definition, mode: .source)
  }
}

public final class ChromeBookmarksBrowseCatalog: ChromeBookmarksCatalogBase {
  public required init(definition: CatalogDefinition) {
    super.init(definition: definition, mode: .browse)
  }
}

@MainActor
public class ChromeBookmarksCatalogBase: NSObject, Catalog {
  public let identifier: String
  public let name: String
  public var availabilityStatus: CatalogAvailabilityStatus = .normal

  private static let loader = SnapshotLoader()
  private let mode: ChromeCatalogMode
  private let itemsStore = LockedValue<[CatalogItem]>([])
  private let childrenStore = LockedValue<[CatalogItem]>([])
  private lazy var browseItem = BrowseCatalogItem(
    title: "Chrome Bookmarks",
    id: "chrome.bookmarks",
    detail: "Browse bookmarks from every Chrome profile",
    catalogIcon: .init(symbolName: "book", color: .blue)
  ) { [weak self] in
    self?.childrenStore.readValue { $0 } ?? []
  }

  public var objects: [CatalogItem] {
    switch mode {
    case .source: itemsStore.readValue { $0 }
    case .browse: [browseItem]
    }
  }

  fileprivate init(definition: CatalogDefinition, mode: ChromeCatalogMode) {
    identifier = definition.identifier
    name = definition.name
    self.mode = mode
    super.init()
  }

  public required init(definition: CatalogDefinition) {
    fatalError("Use a concrete Chrome bookmarks catalog type.")
  }

  public func scan() async {
    do {
      let snapshot = try await Self.loader.load(browser: ChromeBrowser.configuration)
      let items = snapshot.bookmarks.map(ChromeBookmarkItem.init)
      switch mode {
      case .source: itemsStore.value = items
      case .browse: childrenStore.value = profileGroups(snapshot: snapshot)
      }

      let issueCount = snapshot.discoveryIssues.count
        + snapshot.failures.count
        + snapshot.profiles.reduce(0) { $0 + $1.issues.count }
      availabilityStatus = issueCount == 0
        ? .normal
        : .degraded("Some Chrome profiles or bookmarks could not be loaded")
    } catch {
      availabilityStatus = .disabled("Chrome profile data could not be loaded")
      itemsStore.value = []
      childrenStore.value = []
    }
    reportScanFinished()
  }

  private func profileGroups(snapshot: BrowserSnapshot) -> [CatalogItem] {
    snapshot.profiles.map { profile in
      ChromeProfileGroupItem(
        profile: profile.profile,
        children: profile.bookmarks.map(ChromeBookmarkItem.init)
      )
    }
  }
}

public final class ChromeProfilesCatalog: ChromeProfilesCatalogBase {
  public required init(definition: CatalogDefinition) {
    super.init(definition: definition, mode: .source)
  }
}

public final class ChromeProfilesBrowseCatalog: ChromeProfilesCatalogBase {
  public required init(definition: CatalogDefinition) {
    super.init(definition: definition, mode: .browse)
  }
}

@MainActor
public class ChromeProfilesCatalogBase: NSObject, Catalog {
  public let identifier: String
  public let name: String
  public var availabilityStatus: CatalogAvailabilityStatus = .normal

  private let mode: ChromeCatalogMode
  private let profilesStore = LockedValue<[CatalogItem]>([])
  private lazy var browseItem = BrowseCatalogItem(
    title: "Chrome Profiles",
    id: "chrome.profiles",
    detail: "Open a Chrome profile",
    catalogIcon: .init(symbolName: "person.crop.circle", color: .blue)
  ) { [weak self] in
    self?.profilesStore.readValue { $0 } ?? []
  }

  public var objects: [CatalogItem] {
    switch mode {
    case .source: profilesStore.readValue { $0 }
    case .browse: [browseItem]
    }
  }

  fileprivate init(definition: CatalogDefinition, mode: ChromeCatalogMode) {
    identifier = definition.identifier
    name = definition.name
    self.mode = mode
    super.init()
  }

  public required init(definition: CatalogDefinition) {
    fatalError("Use a concrete Chrome profiles catalog type.")
  }

  public func scan() async {
    let browser = ChromeBrowser.configuration
    let result = await Task.detached(priority: .utility) {
      try ProfileDiscovery.discover(browser: browser)
    }.result

    switch result {
    case .success(let discovery):
      if ChromeBrowser.isInstalled {
        profilesStore.value = discovery.profiles.map(makeChromeProfileItem)
        availabilityStatus = discovery.issues.isEmpty
          ? .normal
          : .degraded("Some Chrome profiles could not be loaded")
      } else {
        profilesStore.value = []
        availabilityStatus = .disabled("Google Chrome is not installed")
      }
    case .failure:
      profilesStore.value = []
      availabilityStatus = .disabled("Chrome profiles could not be loaded")
    }
    reportScanFinished()
  }
}

public final class ChromeUtilitiesCatalog: Catalog {
  public let identifier: String
  public let name: String
  public var availabilityStatus: CatalogAvailabilityStatus = .normal

  private let objectsStore = LockedValue<[CatalogItem]>([])

  public var objects: [CatalogItem] { objectsStore.readValue { $0 } }

  public required init(definition: CatalogDefinition) {
    identifier = definition.identifier
    name = definition.name
  }

  public func scan() async {
    if ChromeBrowser.isInstalled {
      objectsStore.value = [
        ChromeCurrentPageItem(), makeChromeNewWindowItem(), makeChromeNewIncognitoWindowItem(),
      ]
      availabilityStatus = .normal
    } else {
      objectsStore.value = []
      availabilityStatus = .disabled("Google Chrome is not installed")
    }
    reportScanFinished()
  }
}

final class ChromeBookmarkItem: CatalogEntity, @unchecked Sendable {
  let bookmark: BookmarkRecord

  init(_ bookmark: BookmarkRecord) {
    self.bookmark = bookmark
    super.init(id: bookmark.id, title: bookmark.title.isEmpty ? bookmark.url.absoluteString : bookmark.title,
               path: bookmark.url.absoluteString)
    typeID = .chromeURL
  }

  override var detail: String? {
    ([bookmark.profile.displayName] + bookmark.folderPath.map(Self.displayFolder)).joined(separator: " · ")
  }

  override var searchText: String {
    ([title, bookmark.url.absoluteString, bookmark.profile.displayName]
      + bookmark.folderPath.map(Self.displayFolder)).joined(separator: " ")
  }

  private static func displayFolder(_ key: String) -> String {
    switch key {
    case "bookmark_bar": "Bookmarks Bar"
    case "other": "Other Bookmarks"
    case "synced": "Mobile Bookmarks"
    default: key
    }
  }
}

private final class ChromeProfileGroupItem: CatalogEntity, CatalogHierarchyNode,
  @unchecked Sendable
{
  private let children: [CatalogItem]

  init(profile: BrowserProfile, children: [CatalogItem]) {
    self.children = children
    super.init(id: profile.id, title: profile.displayName, path: nil)
  }

  func hierarchyChildren() -> [CatalogItem] { children }

  override var detail: String? { "Chrome profile · \(children.count) bookmarks" }

  override func preview(maxDimension: CGFloat) -> CatalogItemPreview {
    .systemSymbol("person.crop.circle", tintColor: .systemBlue)
  }
}

private func makeChromeProfileItem(_ profile: BrowserProfile) -> CatalogItem {
  CommandItem(
    id: profile.id,
    title: profile.displayName,
    symbol: "person.crop.circle",
    detail: "Open Chrome profile",
    headlessEligibility: .guaranteed,
    executionPolicy: .dismiss
  ) {
    ChromeLauncher.launch(profile: profile, newWindow: true)
  }
}

private final class ChromeCurrentPageItem: CatalogEntity, @unchecked Sendable {
  init() {
    super.init(id: ChromeBrowser.currentPageToken, title: "Current Page", path: ChromeBrowser.currentPageToken)
    typeID = .chromeURL
  }

  override var detail: String? { "Front tab in Google Chrome" }

  override func preview(maxDimension: CGFloat) -> CatalogItemPreview {
    .systemSymbol("globe", tintColor: .systemBlue)
  }
}

private func makeChromeNewWindowItem() -> CatalogItem {
  CommandItem(
    id: "new-window", title: "New Chrome Window", symbol: "macwindow.badge.plus",
    detail: "Open a new Google Chrome window", headlessEligibility: .guaranteed,
    executionPolicy: .dismiss
  ) {
    ChromeLauncher.launch(newWindow: true)
  }
}

private func makeChromeNewIncognitoWindowItem() -> CatalogItem {
  CommandItem(
    id: "new-incognito-window", title: "New Incognito Window", symbol: "eye.slash",
    detail: "Open a private Google Chrome window", headlessEligibility: .guaranteed,
    executionPolicy: .dismiss
  ) {
    ChromeLauncher.launch(newWindow: true, incognito: true)
  }
}

enum ChromeLauncher {
  static func start(
    profile: BrowserProfile? = nil,
    url: URL? = nil,
    newWindow: Bool = false,
    incognito: Bool = false
  ) throws {
    let command = try BrowserCommandBuilder.command(
      browser: ChromeBrowser.configuration,
      profile: profile,
      newWindow: newWindow,
      incognito: incognito,
      urls: url.map { [$0] } ?? []
    )
    let process = Process()
    process.executableURL = command.executableURL
    process.arguments = command.arguments
    try process.run()
  }

  static func launch(
    profile: BrowserProfile? = nil,
    url: URL? = nil,
    newWindow: Bool = false,
    incognito: Bool = false
  ) -> ActionResult {
    do {
      try start(profile: profile, url: url, newWindow: newWindow, incognito: incognito)
      return .success
    } catch {
      AppLog.error(.actions, "Failed to open Google Chrome: \(error.localizedDescription)")
      return .failure("Google Chrome could not be opened")
    }
  }
}

enum ChromeCurrentPage {
  static var runOverride: (@Sendable (String) -> String?)?

  static func resolveURL() -> URL? {
    if runOverride == nil,
      NSRunningApplication.runningApplications(withBundleIdentifier: ChromeBrowser.bundleIdentifier)
        .isEmpty
    {
      return nil
    }
    let script = """
      tell application id "com.google.Chrome"
        if (count of windows) is 0 then return ""
        return URL of active tab of front window
      end tell
      """
    let output: String?
    if let runOverride {
      output = runOverride(script)
    } else {
      output = try? CLIProcessRunner.runSync(
        CLIProcessRequest(executablePath: "/usr/bin/osascript", arguments: ["-e", script])
      ).standardOutput
    }
    guard let value = output?.trimmingCharacters(in: .whitespacesAndNewlines),
      let url = URL(string: value), url.scheme != nil
    else { return nil }
    return url
  }
}
