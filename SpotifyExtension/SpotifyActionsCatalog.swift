import AppKit
import Foundation
import TunaKit

public final class SpotifyActionsCatalog: NSObject, ActionCatalog {
  public let identifier: String
  public let name: String
  public private(set) lazy var actions: [CatalogAction] = Self.makeActions()

  public required init(definition: ActionCatalogDefinition) {
    identifier = definition.identifier
    name = definition.name
    super.init()
  }

  static let resourceTypes: Set<TypeID> = [
    .spotifyTrack, .spotifyAlbum, .spotifyArtist, .spotifyPlaylist,
  ]

  static func makeActions() -> [CatalogAction] {
    var items: [CatalogAction] = []

    let play = PredicateAwareAction(id: "play", title: "Play") { subject, _ in
      SpotifyActions.play(subject)
    }
    play.systemSymbolName = "play.fill"
    play.supportedSubjectTypes = resourceTypes
    play.subjectPredicate = { $0 is SpotifyItem || $0 is SpotifyNowPlayingItem }
    items.append(play)

    let save = PredicateAwareAction(id: "save", title: "Save to Library") { subject, _ in
      SpotifyActions.setSaved(true, subject)
    }
    save.systemSymbolName = "plus.circle"
    save.supportedSubjectTypes = [.spotifyTrack, .spotifyAlbum]
    save.subjectPredicate = { ($0 as? SpotifyItem)?.resource.isSaved != true }
    items.append(save)

    let remove = PredicateAwareAction(id: "remove-from-library", title: "Remove from Library") {
      subject, _ in
      SpotifyActions.setSaved(false, subject)
    }
    remove.systemSymbolName = "minus.circle"
    remove.supportedSubjectTypes = [.spotifyTrack, .spotifyAlbum]
    remove.subjectPredicate = { ($0 as? SpotifyItem)?.resource.isSaved == true }
    items.append(remove)

    let addToPlaylist = PredicateAwareAction(id: "add-to-playlist", title: "Add to Playlist") {
      subject, target in
      SpotifyActions.add([subject], to: target)
    }
    addToPlaylist.batchCallback = { subjects, target in SpotifyActions.add(subjects, to: target) }
    addToPlaylist.targetRequirement = .required
    addToPlaylist.systemSymbolName = "text.badge.plus"
    addToPlaylist.supportedSubjectTypes = [.spotifyTrack, .spotifyAlbum]
    addToPlaylist.allowedTargetTypes = [.spotifyPlaylist]
    addToPlaylist.targetSearchScope = .catalogs(
      [SpotifyExtension.playlistsCatalogIdentifier], preparation: .refresh)
    addToPlaylist.subjectPredicate = { $0 is SpotifyItem }
    addToPlaylist.targetPredicate = {
      ($0 as? SpotifyItem)?.resource.canModifyPlaylist == true
    }
    items.append(addToPlaylist)

    let queue = PredicateAwareAction(id: "add-to-queue", title: "Add to Queue") { subject, _ in
      SpotifyActions.addToQueue(subject)
    }
    queue.systemSymbolName = "text.line.last.and.arrowtriangle.forward"
    queue.supportedSubjectTypes = [.spotifyTrack]
    queue.subjectPredicate = { ($0 as? SpotifyItem)?.resource.kind == .track }
    items.append(queue)

    let transfer = PredicateAwareAction(id: "transfer-playback", title: "Play on Device") {
      subject, target in
      SpotifyActions.transferPlayback(subject, to: target)
    }
    transfer.targetRequirement = .required
    transfer.systemSymbolName = "hifispeaker.2"
    transfer.supportedSubjectTypes = [.application, .spotifyTrack]
    transfer.allowedTargetTypes = [.spotifyDevice]
    transfer.targetSearchScope = .catalogs(
      [SpotifyExtension.devicesCatalogIdentifier], preparation: .refresh)
    transfer.subjectPredicate = {
      SpotifyActions.isSpotifyApplication($0) || $0 is SpotifyNowPlayingItem
    }
    transfer.targetPredicate = { ($0 as? SpotifyDeviceItem)?.device.isRestricted == false }
    items.append(transfer)

    let open = PredicateAwareAction(id: "open-in-spotify", title: "Open in Spotify") { subject, _ in
      SpotifyActions.open(subject)
    }
    open.systemSymbolName = "arrow.up.right.square"
    open.supportedSubjectTypes = resourceTypes
    open.subjectPredicate = { SpotifyActions.url(of: $0) != nil }
    items.append(open)

    let transport: [(String, String, String, @Sendable () throws -> Void)] = [
      ("play-pause", "Play/Pause", "playpause", { try SpotifyAppleScript.playPause() }),
      ("next-track", "Next Track", "forward.end", { try SpotifyAppleScript.nextTrack() }),
      (
        "previous-track", "Previous Track", "backward.end",
        { try SpotifyAppleScript.previousTrack() }
      ),
    ]
    for command in transport {
      let action = PredicateAwareAction(id: command.0, title: command.1) { _, _ in
        SpotifyActions.perform(command.3)
      }
      action.systemSymbolName = command.2
      action.supportedSubjectTypes = [.application]
      action.subjectPredicate = SpotifyActions.isSpotifyApplication
      items.append(action)
    }

    return items
  }
}

enum SpotifyActions {
  static func perform(_ work: @escaping @Sendable () throws -> Void) -> ActionResult {
    Task.detached(priority: .userInitiated) {
      do { try work() } catch { report(error) }
    }
    return .success
  }

  static func perform(_ work: @escaping @Sendable () async throws -> Void) -> ActionResult {
    Task.detached(priority: .userInitiated) {
      do { try await work() } catch { report(error) }
    }
    return .success
  }

  static func play(_ subject: CatalogItem) -> ActionResult {
    if subject is SpotifyNowPlayingItem { return perform { try SpotifyAppleScript.playPause() } }
    guard let item = subject as? SpotifyItem else {
      return .failure("Select something from Spotify")
    }
    return perform { try SpotifyAppleScript.play(uri: item.resource.uri) }
  }

  static func setSaved(_ saved: Bool, _ subject: CatalogItem) -> ActionResult {
    guard let resource = (subject as? SpotifyItem)?.resource else {
      return .failure("Select something from Spotify")
    }
    return perform { try await SpotifyAPIClient().setSaved(saved, resource: resource) }
  }

  static func add(_ subjects: [CatalogItem], to target: CatalogItem?) -> ActionResult {
    let resources = subjects.compactMap { ($0 as? SpotifyItem)?.resource }
    guard !resources.isEmpty, let playlist = (target as? SpotifyItem)?.resource else {
      return .failure("Select Spotify tracks or albums and a playlist")
    }
    return perform { try await SpotifyAPIClient().add(resources, to: playlist) }
  }

  static func addToQueue(_ subject: CatalogItem) -> ActionResult {
    guard let resource = (subject as? SpotifyItem)?.resource else {
      return .failure("Select a Spotify track")
    }
    return perform { try await SpotifyAPIClient().addToQueue(resource) }
  }

  static func transferPlayback(_ subject: CatalogItem, to target: CatalogItem?) -> ActionResult {
    guard isSpotifyApplication(subject) || subject is SpotifyNowPlayingItem,
      let device = (target as? SpotifyDeviceItem)?.device
    else { return .failure("Select a Spotify device") }
    return perform { try await SpotifyAPIClient().transferPlayback(to: device) }
  }

  static func open(_ subject: CatalogItem) -> ActionResult {
    guard let url = url(of: subject) else { return .failure("No Spotify link available") }
    guard
      let appURL = NSWorkspace.shared.urlForApplication(
        withBundleIdentifier: SpotifyAppleScript.bundleIdentifier)
    else {
      NSWorkspace.shared.open(url)
      return .success
    }
    let configuration = NSWorkspace.OpenConfiguration()
    configuration.activates = true
    NSWorkspace.shared.open([url], withApplicationAt: appURL, configuration: configuration)
    return .success
  }

  static func url(of subject: CatalogItem?) -> URL? {
    if let item = subject as? SpotifyItem { return item.resource.externalURL }
    if let entity = subject as? CatalogEntity, let path = entity.path { return URL(string: path) }
    return nil
  }

  static func isSpotifyApplication(_ subject: CatalogItem?) -> Bool {
    guard let entity = subject as? CatalogEntity,
      let path = entity.path,
      TypeRegistry.shared.inherits(entity.typeID, from: .application)
    else { return false }
    return Bundle(url: URL(fileURLWithPath: path))?.bundleIdentifier
      == SpotifyAppleScript.bundleIdentifier
  }

  private static func report(_ error: Error) {
    AppLog.error(.actions, "Spotify action failed: \(error.localizedDescription)")
    UserFeedback.beep()
  }
}
