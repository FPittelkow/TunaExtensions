import AppKit
import Foundation
import TunaKit

extension TypeID {
  static let spotifyTrack = TypeID("com.tuna.type.spotify-track")
  static let spotifyAlbum = TypeID("com.tuna.type.spotify-album")
  static let spotifyArtist = TypeID("com.tuna.type.spotify-artist")
  static let spotifyPlaylist = TypeID("com.tuna.type.spotify-playlist")
  static let spotifyDevice = TypeID("com.tuna.type.spotify-device")
}

class SpotifyItem: CatalogEntity, TextValueProviding, CatalogAsyncPreviewProviding,
  @unchecked Sendable
{
  let resource: SpotifyResource
  let catalogIdentifier: String

  init(resource: SpotifyResource, catalogIdentifier: String) {
    self.resource = resource
    self.catalogIdentifier = catalogIdentifier
    super.init(
      id: "spotify.\(resource.kind.rawValue).\(resource.id)",
      title: resource.title,
      path: resource.externalURL.absoluteString
    )
    typeID = Self.typeID(for: resource.kind)
  }

  static func make(_ resource: SpotifyResource, catalogIdentifier: String) -> SpotifyItem {
    resource.isBrowsable
      ? SpotifyCollectionItem(resource: resource, catalogIdentifier: catalogIdentifier)
      : SpotifyItem(resource: resource, catalogIdentifier: catalogIdentifier)
  }

  var textValue: String { resource.externalURL.absoluteString }

  override var detail: String? { resource.subtitle }

  override var searchText: String { "\(resource.title) \(resource.subtitle)" }

  override func preview(maxDimension: CGFloat) -> CatalogItemPreview {
    .systemSymbol(Self.symbol(for: resource.kind), tintColor: .systemGreen)
  }

  override func placeholderPreview(maxDimension: CGFloat) -> CatalogItemPreview {
    preview(maxDimension: maxDimension)
  }

  func asyncPreview(maxDimension: CGFloat) async -> CatalogItemPreview? {
    guard let artworkURL = resource.artworkURL else { return nil }
    return await SpotifyArtworkLoader.shared.preview(for: artworkURL, maxDimension: maxDimension)
  }

  private static func typeID(for kind: SpotifyResource.Kind) -> TypeID {
    switch kind {
    case .track: return .spotifyTrack
    case .album: return .spotifyAlbum
    case .artist: return .spotifyArtist
    case .playlist: return .spotifyPlaylist
    }
  }

  private static func symbol(for kind: SpotifyResource.Kind) -> String {
    switch kind {
    case .track: return "music.note"
    case .album: return "square.stack"
    case .artist: return "music.mic"
    case .playlist: return "music.note.list"
    }
  }
}

final class SpotifyCollectionItem: SpotifyItem, CatalogHierarchyNode, @unchecked Sendable {
  private lazy var deferredContents = DeferredBrowseCatalogItem(
    title: resource.title,
    id: "spotify.contents.\(resource.kind.rawValue).\(resource.id)",
    detail: "Contents on Spotify",
    catalogIcon: .init(symbolName: "music.note.list", color: .green),
    loadingItemProvider: { SpotifyCatalogSupport.loadingItem("Contents") },
    errorItemProvider: { SpotifyCatalogSupport.messageItem(for: $0) },
    didLoad: { [catalogIdentifier] in
      NotificationCenter.default.post(name: CatalogDidFinishScan, object: catalogIdentifier)
    },
    loadChildren: { [resource, catalogIdentifier] in
      let children = try await SpotifyAPIClient().children(of: resource)
      return children.isEmpty
        ? [SpotifyCatalogSupport.emptyItem("No Contents", "Spotify returned no items.")]
        : children.map { SpotifyItem.make($0, catalogIdentifier: catalogIdentifier) }
    }
  )

  @MainActor func hierarchyChildren() -> [CatalogItem] {
    deferredContents.hierarchyChildren()
  }
}

final class SpotifyDeviceItem: CatalogEntity, @unchecked Sendable {
  let device: SpotifyDevice

  init(device: SpotifyDevice) {
    self.device = device
    super.init(id: "spotify.device.\(device.id)", title: device.name, path: nil)
    typeID = .spotifyDevice
  }

  override var detail: String? {
    [device.type, device.isActive ? "Active" : ""].filter { !$0.isEmpty }.joined(separator: " · ")
  }

  override func preview(maxDimension: CGFloat) -> CatalogItemPreview {
    .systemSymbol(
      device.isActive ? "speaker.wave.2.fill" : "speaker.wave.2", tintColor: .systemGreen)
  }
}

final class SpotifyNowPlayingItem: CatalogEntity, TextValueProviding, CatalogAsyncPreviewProviding,
  @unchecked Sendable
{
  static let identifier = "spotify.now-playing"
  let nowPlaying: SpotifyNowPlaying

  init(nowPlaying: SpotifyNowPlaying) {
    self.nowPlaying = nowPlaying
    let url = SpotifyNowPlayingItem.openURL(for: nowPlaying.uri)
    super.init(id: Self.identifier, title: "Now Playing", path: url?.absoluteString)
    typeID = .spotifyTrack
    previewIdentityVersion = UInt64(
      truncatingIfNeeded: "\(nowPlaying.uri).\(nowPlaying.state)".hashValue.magnitude)
  }

  var textValue: String { [nowPlaying.title, nowPlaying.artist].joined(separator: " — ") }

  override var detail: String? {
    [textValue, nowPlaying.state == .paused ? "Paused" : ""].filter { !$0.isEmpty }.joined(
      separator: " · ")
  }

  override func preview(maxDimension: CGFloat) -> CatalogItemPreview {
    .systemSymbol(
      nowPlaying.state == .playing ? "play.circle" : "pause.circle", tintColor: .systemGreen)
  }

  override func placeholderPreview(maxDimension: CGFloat) -> CatalogItemPreview {
    preview(maxDimension: maxDimension)
  }

  func asyncPreview(maxDimension: CGFloat) async -> CatalogItemPreview? {
    guard let url = nowPlaying.artworkURL else { return nil }
    return await SpotifyArtworkLoader.shared.preview(for: url, maxDimension: maxDimension)
  }

  private static func openURL(for uri: String) -> URL? {
    let parts = uri.split(separator: ":")
    guard parts.count == 3, parts[0] == "spotify" else { return nil }
    return URL(string: "https://open.spotify.com/\(parts[1])/\(parts[2])")
  }
}

actor SpotifyArtworkLoader {
  static let shared = SpotifyArtworkLoader()
  private var cache: [URL: Data?] = [:]

  func preview(for url: URL, maxDimension: CGFloat) async -> CatalogItemPreview? {
    let data: Data?
    if let cached = cache[url] {
      data = cached
    } else {
      data = try? await URLSession.shared.data(from: url).0
      cache[url] = data
    }
    guard let data, let image = NSImage(data: data) else { return nil }
    return CatalogItemPreview(image: image)
  }
}
