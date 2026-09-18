import AppKit
import Foundation
import TunaKit

@MainActor
public final class SpotifyControlsCatalog: NSObject, Catalog, RescanSchedulingCatalog {
  static let playbackNotification = Notification.Name("com.spotify.client.PlaybackStateChanged")

  public let identifier: String
  public let name: String
  public var rescanHandler: (() -> Void)?

  private var nowPlayingItem: CatalogItem?
  private lazy var commands = Self.makeCommands()
  private var observer: NSObjectProtocol?
  private var refreshTask: Task<Void, Never>?

  public var objects: [CatalogItem] { (nowPlayingItem.map { [$0] } ?? []) + commands }

  public required init(definition: CatalogDefinition) {
    identifier = definition.identifier
    name = definition.name
    super.init()
    observer = DistributedNotificationCenter.default().addObserver(
      forName: Self.playbackNotification, object: nil, queue: .main
    ) { [weak self] _ in
      MainActor.assumeIsolated { self?.scheduleRefresh() }
    }
  }

  deinit {
    if let observer { DistributedNotificationCenter.default().removeObserver(observer) }
    refreshTask?.cancel()
  }

  public func scan() async {
    let nowPlaying = await Task.detached(priority: .utility) {
      try? SpotifyAppleScript.nowPlaying()
    }.value
    nowPlayingItem = (nowPlaying ?? nil).map(SpotifyNowPlayingItem.init)
    reportScanFinished()
  }

  private func scheduleRefresh() {
    refreshTask?.cancel()
    refreshTask = Task { [weak self] in
      try? await Task.sleep(for: .milliseconds(300))
      guard !Task.isCancelled else { return }
      self?.rescanHandler?()
    }
  }

  nonisolated static func makeCommands() -> [CatalogItem] {
    let definitions: [(String, String, String, String, @Sendable () throws -> Void)] = [
      (
        "play-pause", "Play/Pause", "playpause", "Play or pause Spotify",
        { try SpotifyAppleScript.playPause() }
      ),
      (
        "next-track", "Next Track", "forward.end", "Skip to the next track",
        { try SpotifyAppleScript.nextTrack() }
      ),
      (
        "previous-track", "Previous Track", "backward.end", "Go back to the previous track",
        { try SpotifyAppleScript.previousTrack() }
      ),
    ]
    return definitions.map { id, title, symbol, detail, run in
      CommandItem(
        id: id,
        title: title,
        symbol: symbol,
        detail: detail,
        tintColor: .systemGreen,
        headlessEligibility: .guaranteed,
        executionPolicy: .dismiss
      ) {
        SpotifyActions.perform(run)
      }
    }
  }
}

@MainActor
public final class SpotifySearchCatalog: NSObject, Catalog {
  public let identifier: String
  public let name: String

  private lazy var rootItem = ScopedSearchBrowseCatalogItem(
    title: "Spotify",
    id: "spotify.search",
    detail: "Search tracks, albums, artists, and playlists",
    catalogIcon: .init(symbolName: "music.note", color: .green),
    childrenProvider: { [] },
    searchHandler: { query in
      let resources = try await SpotifyAPIClient().search(query)
      return resources.isEmpty
        ? [SpotifyCatalogSupport.emptyItem("No Results", "Nothing on Spotify matched your search.")]
        : resources.map { SpotifyItem.make($0, catalogIdentifier: "spotify.search") }
    }
  )

  public var objects: [CatalogItem] { [rootItem] }

  public required init(definition: CatalogDefinition) {
    identifier = definition.identifier
    name = definition.name
    super.init()
  }

  public func scan() async {
    reportScanFinished()
  }
}

@MainActor
public final class SpotifyLibraryCatalog: NSObject, Catalog, RetainedCatalogStateReleasing {
  public let identifier: String
  public let name: String

  private lazy var rootItem = DeferredBrowseCatalogItem(
    title: "Your Library",
    id: "spotify.library",
    detail: "Saved music and playlists on Spotify",
    catalogIcon: .init(symbolName: "books.vertical", color: .green),
    loadingItemProvider: { SpotifyCatalogSupport.loadingItem("Library") },
    errorItemProvider: { SpotifyCatalogSupport.messageItem(for: $0) },
    didLoad: { [identifier] in
      NotificationCenter.default.post(name: CatalogDidFinishScan, object: identifier)
    },
    loadChildren: { Self.sections(catalogIdentifier: "spotify.library") }
  )

  public var objects: [CatalogItem] { [rootItem] }

  public required init(definition: CatalogDefinition) {
    identifier = definition.identifier
    name = definition.name
    super.init()
  }

  public func scan() async {
    rootItem.reset()
    reportScanFinished()
  }

  public func releaseRetainedState() { rootItem.reset() }

  nonisolated static func sections(catalogIdentifier: String) -> [CatalogItem] {
    [
      section(
        "Saved Tracks", id: "tracks", detail: "Tracks saved to your library", symbol: "music.note",
        catalogIdentifier: catalogIdentifier
      ) {
        try await SpotifyAPIClient().savedTracks()
      },
      section(
        "Saved Albums", id: "albums", detail: "Albums saved to your library",
        symbol: "square.stack", catalogIdentifier: catalogIdentifier
      ) {
        try await SpotifyAPIClient().savedAlbums()
      },
      section(
        "Artists", id: "artists", detail: "Artists you follow", symbol: "music.mic",
        catalogIdentifier: catalogIdentifier
      ) {
        try await SpotifyAPIClient().followedArtists()
      },
      section(
        "Playlists", id: "playlists", detail: "Your Spotify playlists", symbol: "music.note.list",
        catalogIdentifier: catalogIdentifier
      ) {
        try await SpotifyAPIClient().playlists()
      },
    ]
  }

  nonisolated private static func section(
    _ title: String,
    id: String,
    detail: String,
    symbol: String,
    catalogIdentifier: String,
    load: @escaping @Sendable () async throws -> [SpotifyResource]
  ) -> CatalogItem {
    DeferredBrowseCatalogItem(
      title: title,
      id: "spotify.library.\(id)",
      detail: detail,
      catalogIcon: .init(symbolName: symbol, color: .green),
      loadingItemProvider: { SpotifyCatalogSupport.loadingItem(title) },
      errorItemProvider: { SpotifyCatalogSupport.messageItem(for: $0) },
      didLoad: {
        NotificationCenter.default.post(name: CatalogDidFinishScan, object: catalogIdentifier)
      },
      loadChildren: {
        let resources = try await load()
        return resources.isEmpty
          ? [
            SpotifyCatalogSupport.emptyItem("No \(title)", "This Spotify library section is empty.")
          ]
          : resources.map { SpotifyItem.make($0, catalogIdentifier: catalogIdentifier) }
      }
    )
  }
}

@MainActor
public final class SpotifyPlaylistsCatalog: NSObject, Catalog, RescanSchedulingCatalog,
  StartupScanningCatalog
{
  public let identifier: String
  public let name: String
  public let scansOnStartup = false
  public var rescanHandler: (() -> Void)?
  private var items: [CatalogItem] = []

  public var objects: [CatalogItem] { items }

  public required init(definition: CatalogDefinition) {
    identifier = definition.identifier
    name = definition.name
    super.init()
  }

  public func scan() async {
    do {
      items = try await SpotifyAPIClient().playlists().map {
        SpotifyItem.make($0, catalogIdentifier: SpotifyExtension.playlistsCatalogIdentifier)
      }
    } catch {
      items = [SpotifyCatalogSupport.messageItem(for: error)]
    }
    reportScanFinished()
  }
}

@MainActor
public final class SpotifyDevicesCatalog: NSObject, Catalog, RescanSchedulingCatalog,
  StartupScanningCatalog
{
  public let identifier: String
  public let name: String
  public let scansOnStartup = false
  public var rescanHandler: (() -> Void)?
  private var items: [CatalogItem] = []

  public var objects: [CatalogItem] { items }

  public required init(definition: CatalogDefinition) {
    identifier = definition.identifier
    name = definition.name
    super.init()
  }

  public func scan() async {
    do {
      let devices = try await SpotifyAPIClient().devices().filter { !$0.isRestricted }
      items =
        devices.isEmpty
        ? [SpotifyCatalogSupport.emptyItem("No Devices", "Open Spotify on a device and try again.")]
        : devices.map(SpotifyDeviceItem.init)
    } catch {
      items = [SpotifyCatalogSupport.messageItem(for: error)]
    }
    reportScanFinished()
  }
}
