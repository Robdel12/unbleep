import Foundation
import Testing
@testable import Unbleep

@Test @MainActor func repeatCatalogLookupsReuseSuccessfulResponses() async throws {
    let cache = CatalogResponseCache()
    let url = try #require(URL(string: "https://api.music.apple.com/v1/catalog/us/songs?ids=123"))
    var calls = 0
    let fetch: @MainActor () async throws -> Data = {
        calls += 1
        return Data("123".utf8)
    }
    let decode: (Data) throws -> Int = { try JSONDecoder().decode(Int.self, from: $0) }

    let first = try await cache.value(for: url, decode: decode, fetch: fetch)
    let second = try await cache.value(for: url, decode: decode, fetch: fetch)

    #expect(first == 123 && second == 123)
    #expect(calls == 1)
}

@Test @MainActor func unreadableCatalogResponsesCanBeFetchedAgain() async throws {
    let cache = CatalogResponseCache()
    let url = try #require(URL(string: "https://api.music.apple.com/v1/catalog/us/songs?ids=123"))
    let decode: (Data) throws -> Int = { try JSONDecoder().decode(Int.self, from: $0) }
    await #expect(throws: DecodingError.self) {
        try await cache.value(for: url, decode: decode) { Data("not a response".utf8) }
    }
    let result = try await cache.value(for: url, decode: decode) { Data("123".utf8) }
    #expect(result == 123)
}
