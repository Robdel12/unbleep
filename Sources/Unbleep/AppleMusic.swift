import CryptoKit
import Foundation
@preconcurrency import MusicKit

struct Resource: Decodable {
    let id: String
    let type: String
    let attributes: Attributes?
    let relationships: [String: Relationship]?

    struct Relationship: Decodable {
        let data: [Resource]?
    }

    struct Attributes: Decodable {
        struct PlayParams: Decodable {
            let id: String?
            let catalogId: String?
        }

        let name: String?
        let artistName: String?
        let albumName: String?
        let discNumber: Int?
        let trackNumber: Int?
        let durationInMillis: Int?
        let contentRating: String?
        let releaseDate: String?
        let playParams: PlayParams?
        let url: URL?
    }

    var song: SongReference? {
        guard type == "songs" || type == "library-songs",
              let attributes, let title = attributes.name, let artist = attributes.artistName,
              let album = attributes.albumName, let track = attributes.trackNumber,
              let milliseconds = attributes.durationInMillis else { return nil }
        let info = SongInfo(title: title, artist: artist, album: album, disc: attributes.discNumber ?? 1,
                            track: track, milliseconds: milliseconds)
        return SongReference(id: id, info: info, url: attributes.url, releaseDate: attributes.releaseDate)
    }

    var catalogID: String? {
        let id = attributes?.playParams?.catalogId ?? relationships?["catalog"]?.data?.first?.id
        return id.flatMap { isCatalogID($0) ? $0 : nil }
    }

    var albumID: String? {
        let id = relationships?["albums"]?.data?.first?.id
        return id.flatMap { isCatalogID($0) ? $0 : nil }
    }

    var isPlayableExplicit: Bool {
        type == "songs" && isCatalogID(id) && attributes?.contentRating == "explicit"
            && attributes?.playParams?.id == id
    }
}

struct Page: Decodable {
    let data: [Resource]
    let next: String?
}

private struct SearchResponse: Decodable {
    let results: [String: Page]
}

func isCatalogID(_ id: String) -> Bool {
    !id.isEmpty && id.utf8.allSatisfy { (48...57).contains($0) }
}

func isStorefrontID(_ id: String) -> Bool {
    id.utf8.count == 2 && id.utf8.allSatisfy { (97...122).contains($0) }
}

private func suppliedDeveloperToken(_ environment: [String: String]) throws -> String? {
    if let token = environment["MUSIC_DEVELOPER_TOKEN"], !token.isEmpty { return token }
    let team = environment["MUSIC_TEAM_ID"] ?? ""
    let keyID = environment["MUSIC_KEY_ID"] ?? ""
    let path = environment["MUSIC_KEY_FILE"] ?? ""
    if team.isEmpty && keyID.isEmpty && path.isEmpty { return nil }
    guard !team.isEmpty, !keyID.isEmpty, !path.isEmpty else {
        throw ToolError("Set MUSIC_TEAM_ID, MUSIC_KEY_ID, and MUSIC_KEY_FILE together, as described in docs/usage.md.")
    }
    let key: P256.Signing.PrivateKey
    do {
        let pem = try String(contentsOfFile: NSString(string: path).expandingTildeInPath, encoding: .utf8)
        key = try P256.Signing.PrivateKey(pemRepresentation: pem)
    } catch {
        throw ToolError("Couldn't load the MusicKit .p8 key at MUSIC_KEY_FILE.")
    }

    let now = Int(Date().timeIntervalSince1970)
    let header = try JSONSerialization.data(withJSONObject: ["alg": "ES256", "kid": keyID])
    let claims = try JSONSerialization.data(withJSONObject: ["iss": team, "iat": now, "exp": now + 3600])
    let message = "\(base64URL(header)).\(base64URL(claims))"
    let signature = try key.signature(for: Data(message.utf8))
    return "\(message).\(base64URL(signature.rawRepresentation))"
}

private func base64URL(_ data: Data) -> String {
    data.base64EncodedString()
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
}

private final class SuppliedTokenProvider: MusicUserTokenProvider, MusicDeveloperTokenProvider, @unchecked Sendable {
    private let token: String

    init(token: String) {
        self.token = token
        super.init()
    }

    func developerToken(options: MusicTokenRequestOptions) async throws -> String { token }
}

private struct AppleMusicHTTPError: LocalizedError {
    let status: Int
    let path: String
    var errorDescription: String? {
        switch status {
        case 401:
            return "Apple Music rejected the developer token. Check that MusicKit is enabled for this build’s App ID or that the Media Services key is valid."
        case 403:
            return "Apple Music denied access to \(path). Check that Music is signed in with Sync Library enabled."
        default:
            return "Apple Music returned HTTP \(status) for \(path)."
        }
    }
}

@MainActor
struct AppleMusic {
    let storefront: String
    private let catalogCache: CatalogResponseCache?
    private var catalog: String { "/v1/catalog/\(storefront)" }

    static func configureTokenProvider(environment: [String: String]) throws {
        if let supplied = try suppliedDeveloperToken(environment) {
            MusicDataRequest.tokenProvider = SuppliedTokenProvider(token: supplied)
        } else {
            MusicDataRequest.tokenProvider = DefaultMusicTokenProvider()
        }
    }

    static func connect(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        catalogCache: CatalogResponseCache? = nil
    ) async throws -> Self {
        try configureTokenProvider(environment: environment)
        let url = try requestURL("/v1/me/storefront", [:])
        let data = try await send(URLRequest(url: url))
        let page = try JSONDecoder().decode(Page.self, from: data)
        guard let storefront = page.data.first?.id, isStorefrontID(storefront) else {
            throw ToolError("Apple Music didn't return a storefront for this account.")
        }
        return Self(storefront: storefront, catalogCache: catalogCache)
    }

    func librarySongs(onPage: (Int) -> Void = { _ in }) async throws -> [Resource] {
        try await pages("/v1/me/library/songs", ["limit": "100"], onPage: onPage)
    }

    func catalogSongs(ids: Set<String>) async throws -> [String: Resource] {
        let ordered = ids.sorted()
        var songs: [String: Resource] = [:]
        for start in stride(from: 0, to: ordered.count, by: 50) {
            let batch = ordered.dropFirst(start).prefix(50)
            let page: Page = try await get("\(catalog)/songs", ["ids": batch.joined(separator: ",")])
            for song in page.data { songs[song.id] = song }
        }
        return songs
    }

    func alternateAlbums(_ albumID: String) async throws -> [Resource] {
        do {
            return try await pages("\(catalog)/albums/\(albumID)/view/other-versions", [:])
        } catch let error as AppleMusicHTTPError where error.status == 404 {
            return []
        }
    }

    func albumTracks(_ albumID: String) async throws -> [Resource] {
        try await pages("\(catalog)/albums/\(albumID)/tracks", [:])
    }

    func search(_ song: SongInfo) async throws -> [Resource] {
        let response: SearchResponse = try await get("\(catalog)/search", [
            "term": "\(song.artist) \(song.title)", "types": "songs", "limit": "25",
        ])
        return response.results["songs"]?.data ?? []
    }

    func add(_ ids: Set<String>) async throws {
        let ordered = ids.sorted()
        for start in stride(from: 0, to: ordered.count, by: 25) {
            let batch = ordered.dropFirst(start).prefix(25)
            let url = try Self.requestURL("/v1/me/library", ["ids[songs]": batch.joined(separator: ",")])
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            _ = try await Self.send(request)
        }
    }

    private func pages(
        _ path: String, _ query: [String: String], onPage: (Int) -> Void = { _ in }
    ) async throws -> [Resource] {
        var page: Page = try await get(path, query)
        var all = page.data
        onPage(all.count)
        var seen = Set<String>()
        while let next = page.next {
            guard seen.insert(next).inserted else { throw ToolError("Apple Music repeated a page of results.") }
            page = try await get(next, query)
            all.append(contentsOf: page.data)
            onPage(all.count)
        }
        return all
    }

    private func get<T: Decodable>(_ path: String, _ query: [String: String] = [:]) async throws -> T {
        let url = try Self.requestURL(path, query)
        let request = URLRequest(url: url)
        func decode(_ data: Data) throws -> T {
            do {
                return try JSONDecoder().decode(T.self, from: data)
            } catch let error as DecodingError {
                throw ToolError("Apple Music returned an unreadable response for \(url.path). \(error)")
            }
        }
        if let catalogCache, url.path.hasPrefix("/v1/catalog/") {
            return try await catalogCache.value(for: url, decode: decode) { try await Self.send(request) }
        }
        return try decode(await Self.send(request))
    }

    private static func requestURL(_ path: String, _ query: [String: String]) throws -> URL {
        guard path.hasPrefix("/v1/"), var url = URLComponents(string: "https://api.music.apple.com"),
              let relative = URLComponents(string: path), relative.host == nil, relative.scheme == nil else {
            throw ToolError("Apple Music returned an invalid API path.")
        }
        url.percentEncodedPath = relative.percentEncodedPath
        url.percentEncodedQuery = relative.percentEncodedQuery
        if !query.isEmpty {
            // Apple may omit the original page size from its continuation URL.
            let existing = Set((relative.queryItems ?? []).map(\.name))
            var defaults = URLComponents()
            defaults.queryItems = query.keys.sorted().filter { !existing.contains($0) }.map {
                URLQueryItem(name: $0, value: query[$0])
            }
            if let items = defaults.percentEncodedQueryItems, !items.isEmpty {
                url.percentEncodedQueryItems = (relative.percentEncodedQueryItems ?? []) + items
            }
        }
        guard let target = url.url else { throw ToolError("Couldn't build an Apple Music API URL.") }
        return target
    }

    private static func send(_ input: URLRequest) async throws -> Data {
        var request = input
        request.timeoutInterval = 30
        do {
            return try await MusicDataRequest(urlRequest: request).response().data
        } catch let error as MusicDataRequest.Error {
            throw AppleMusicHTTPError(status: error.status, path: request.url?.path ?? "/v1/")
        } catch MusicTokenRequestError.developerTokenRequestFailed {
            throw ToolError("MusicKit couldn’t issue a developer token. Enable MusicKit for this build’s App ID or enter a Media Services key in MusicKit Setup.")
        } catch let error as MusicTokenRequestError {
            throw ToolError("MusicKit couldn’t authorize your Apple Music account (\(error)). Check that Music is signed in and the app has Media & Apple Music access.")
        }
    }
}
