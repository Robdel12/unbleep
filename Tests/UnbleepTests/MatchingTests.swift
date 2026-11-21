import Foundation
import Testing
@testable import Unbleep

@Test func matchesAnExplicitEditionOfTheSameTrack() throws {
    let source = try #require(song(id: "1", album: "The Album (Clean)", rating: "clean").song)
    let replacement = try song(id: "2", album: "The Album", rating: "explicit")
    let result = explicitMatches(for: source, in: [replacement, replacement])
    #expect(result.map(\.id) == ["2"])
}

@Test func ignoresEditsDeluxeEditionsAndUnplayableTracks() throws {
    let source = try #require(song(id: "1", rating: "clean").song)
    let candidates = try [
        song(id: "2", title: "The Song (Live)", rating: "explicit"),
        song(id: "3", artist: "A Tribute Band", rating: "explicit"),
        song(id: "4", album: "The Album (Deluxe)", rating: "explicit"),
        song(id: "5", rating: "explicit", milliseconds: 196_999),
        song(id: "6", rating: "explicit", track: 4),
        song(id: "7", rating: "clean"),
        song(id: "8", rating: nil),
        song(id: "9", rating: "explicit", playable: false),
    ]
    #expect(explicitMatches(for: source, in: candidates).isEmpty)
}

@Test func reportsBothMatchesSoAmbiguousEditionsCanBeSkipped() throws {
    let source = try #require(song(id: "1", rating: "clean").song)
    let candidates = try [
        song(id: "3", album: "The Album (Explicit)", rating: "explicit"),
        song(id: "2", rating: "explicit"),
    ]
    #expect(explicitMatches(for: source, in: candidates).map(\.id) == ["2", "3"])
}

@Test func requiresTheExactExplicitCatalogIDInTheSyncedLibrary() throws {
    let explicit = try #require(song(id: "2", rating: "explicit").song)
    let cleanLibraryCopy = try song(id: "i.clean", rating: nil, catalogID: "1")
    let explicitLibraryCopy = try song(id: "i.explicit", rating: nil, catalogID: "2")
    #expect(!containsCatalogSong(explicit, in: [cleanLibraryCopy]))
    #expect(containsCatalogSong(explicit, in: [cleanLibraryCopy, explicitLibraryCopy]))
}

private func song(
    id: String, title: String = "The Song", artist: String = "The Artist",
    album: String = "The Album", rating: String?, milliseconds: Int = 200_000,
    track: Int = 3, playable: Bool = true, catalogID: String? = nil
) throws -> Resource {
    var attributes: [String: Any] = [
        "name": title, "artistName": artist, "albumName": album,
        "durationInMillis": milliseconds, "trackNumber": track, "discNumber": 1,
    ]
    attributes["contentRating"] = rating
    if playable {
        var playParams = ["id": id]
        playParams["catalogId"] = catalogID
        attributes["playParams"] = playParams
    }
    let object: [String: Any] = [
        "id": id, "type": catalogID == nil ? "songs" : "library-songs",
        "attributes": attributes,
        "relationships": ["artists": ["href": "/v1/catalog/us/songs/\(id)/artists"]],
    ]
    return try JSONDecoder().decode(Resource.self, from: JSONSerialization.data(withJSONObject: object))
}
