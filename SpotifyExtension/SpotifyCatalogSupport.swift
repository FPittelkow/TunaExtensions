import AppKit
import Foundation
import TunaKit

struct SpotifyConnection: Sendable {
  let record: ExtensionConnectionRecord
  let accessToken: String
}

enum SpotifyCatalogSupport {
  static let providerIdentifier = "spotify"

  static let connectionDefinition = ExtensionConnectionDefinition(
    providerIdentifier: providerIdentifier,
    providerName: "Spotify",
    kind: .oauth,
    description: "Connect your Spotify account to search Spotify and browse your library.",
    connectButtonLabel: "Connect Spotify"
  )

  static func authRequiredItem() -> CatalogMessageItem {
    CatalogMessageItem(
      title: "Connect Spotify",
      message: "Connect Spotify in extension settings to search and browse your library.",
      symbolName: "person.crop.circle.badge.exclamationmark",
      tintColor: .systemOrange
    )
  }

  static func loadingItem(_ title: String = "Spotify") -> CatalogLoadingItem {
    CatalogLoadingItem(title: "Loading \(title)", message: "Asking Spotify.")
  }

  static func emptyItem(_ title: String, _ message: String) -> CatalogMessageItem {
    CatalogMessageItem(
      title: title, message: message, symbolName: "tray", tintColor: .secondaryLabelColor)
  }

  static func messageItem(for error: Error) -> CatalogMessageItem {
    if case SpotifyAPIError.missingConnection = error { return authRequiredItem() }
    let apiError = error as? SpotifyAPIError
    return CatalogMessageItem(
      title: apiError?.title ?? "Spotify Unavailable",
      message: error.localizedDescription,
      symbolName: "exclamationmark.triangle",
      tintColor: .systemOrange
    )
  }
}

private struct SpotifyRefreshResponse: Decodable {
  struct Payload: Decodable {
    let accessToken: String
    let refreshToken: String?
    let scopes: [String]
    let expiresAt: Date?

    enum CodingKeys: String, CodingKey {
      case accessToken = "access_token"
      case refreshToken = "refresh_token"
      case scopes
      case expiresAt = "expires_at"
    }
  }

  let data: Payload
}

actor SpotifyTokenManager {
  static let shared = SpotifyTokenManager()

  #if DEBUG
    private static let defaultRefreshURL = URL(
      string: "http://127.0.0.1:3038/api/v1/extension_oauth/token_refresh")!
  #else
    private static let defaultRefreshURL = URL(
      string: "https://tunaformac.com/api/v1/extension_oauth/token_refresh")!
  #endif

  private let refreshURL: URL
  private let session: URLSession
  private var refreshTasks: [String: Task<SpotifyConnection, Error>] = [:]

  init(session: URLSession = .shared, refreshURL: URL = defaultRefreshURL) {
    self.session = session
    self.refreshURL = refreshURL
  }

  func connection(extensionIdentifier: String, forceRefresh: Bool = false) async throws
    -> SpotifyConnection
  {
    let store = ExtensionConnectionStore(
      extensionIdentifier: extensionIdentifier,
      providerIdentifier: SpotifyCatalogSupport.providerIdentifier
    )
    guard let record = store.defaultRecord(), let accessToken = store.accessToken(for: record),
      !accessToken.isEmpty
    else {
      throw SpotifyAPIError.missingConnection
    }
    if !forceRefresh, record.expiresAt.map({ $0 > Date().addingTimeInterval(60) }) ?? true {
      return SpotifyConnection(record: record, accessToken: accessToken)
    }

    if let task = refreshTasks[extensionIdentifier] { return try await task.value }
    let task = Task { try await refresh(record: record, store: store) }
    refreshTasks[extensionIdentifier] = task
    defer { refreshTasks[extensionIdentifier] = nil }
    return try await task.value
  }

  private func refresh(record: ExtensionConnectionRecord, store: ExtensionConnectionStore)
    async throws -> SpotifyConnection
  {
    guard let currentRefreshToken = store.refreshToken(for: record), !currentRefreshToken.isEmpty
    else {
      throw SpotifyAPIError.reconnectRequired
    }
    var request = URLRequest(url: refreshURL)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try JSONSerialization.data(withJSONObject: [
      "provider_identifier": SpotifyCatalogSupport.providerIdentifier,
      "refresh_token": currentRefreshToken,
    ])
    let (data, response) = try await session.data(for: request)
    guard let http = response as? HTTPURLResponse else {
      throw SpotifyAPIError.invalidResponse
    }
    guard (200..<300).contains(http.statusCode) else {
      if http.statusCode == 400 || http.statusCode == 401 {
        throw SpotifyAPIError.reconnectRequired
      }
      if http.statusCode == 429 { throw SpotifyAPIError.rateLimited }
      throw SpotifyAPIError.unexpectedStatus(http.statusCode, nil)
    }
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let payload = try decoder.decode(SpotifyRefreshResponse.self, from: data).data
    var updated = record
    updated.expiresAt = payload.expiresAt
    if !payload.scopes.isEmpty { updated.scopes = payload.scopes }
    try store.save(
      updated,
      accessToken: payload.accessToken,
      refreshToken: payload.refreshToken ?? currentRefreshToken,
      makeDefault: true
    )
    return SpotifyConnection(record: updated, accessToken: payload.accessToken)
  }
}
