import Foundation
import Testing

@testable import TunaSpotify

@Suite(.serialized)
struct SpotifyExtensionTests {
  @Test func parsesNowPlaying() {
    let output = [
      "playing",
      "spotify:track:123",
      "Song",
      "Artist",
      "Album",
      "https://i.scdn.co/image/cover",
    ].joined(separator: SpotifyAppleScript.recordSeparator)

    let result = SpotifyAppleScript.parseNowPlaying(output)

    #expect(result?.state == .playing)
    #expect(result?.uri == "spotify:track:123")
    #expect(result?.title == "Song")
    #expect(result?.artist == "Artist")
    #expect(result?.album == "Album")
  }

  @Test func rejectsIncompleteNowPlaying() {
    #expect(SpotifyAppleScript.parseNowPlaying("playing") == nil)
  }

  @Test func escapesAppleScriptLiterals() {
    #expect(SpotifyAppleScript.Scripts.literal("a\\b\"c") == "\"a\\\\b\\\"c\"")
  }

  @Test func onlyResourcesWithAvailableContentsAreBrowsable() {
    let album = SpotifyResource(
      kind: .album,
      id: "album-1",
      title: "Album",
      subtitle: "Artist",
      uri: "spotify:album:album-1",
      externalURL: URL(string: "https://open.spotify.com/album/album-1")!,
      artworkURL: nil,
      isSaved: nil,
      isBrowsable: true,
      canModifyPlaylist: false
    )
    let track = SpotifyResource(
      kind: .track,
      id: "track-1",
      title: "Track",
      subtitle: "Artist",
      uri: "spotify:track:track-1",
      externalURL: URL(string: "https://open.spotify.com/track/track-1")!,
      artworkURL: nil,
      isSaved: nil,
      isBrowsable: false,
      canModifyPlaylist: false
    )
    let publicPlaylist = SpotifyResource(
      kind: .playlist,
      id: "playlist-1",
      title: "Playlist",
      subtitle: "Owner",
      uri: "spotify:playlist:playlist-1",
      externalURL: URL(string: "https://open.spotify.com/playlist/playlist-1")!,
      artworkURL: nil,
      isSaved: nil,
      isBrowsable: false,
      canModifyPlaylist: false
    )

    #expect(SpotifyItem.make(album, catalogIdentifier: "test") is SpotifyCollectionItem)
    #expect(!(SpotifyItem.make(track, catalogIdentifier: "test") is SpotifyCollectionItem))
    #expect(!(SpotifyItem.make(publicPlaylist, catalogIdentifier: "test") is SpotifyCollectionItem))
  }
}
