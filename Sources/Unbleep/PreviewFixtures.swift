#if DEBUG
import Foundation

/// Sample library data for SwiftUI previews.
enum PreviewFixtures {
    static func song(
        _ id: String, _ title: String, _ artist: String, album: String,
        track: Int = 4, seconds: Int = 220, released: String? = "2019-08-16"
    ) -> SongReference {
        SongReference(
            id: id,
            info: SongInfo(title: title, artist: artist, album: album, disc: 1, track: track, milliseconds: seconds * 1000),
            url: URL(string: "https://music.apple.com/us/song/\(id)"),
            releaseDate: released
        )
    }

    static let swaps: [Swap] = [
        Swap(localID: "A1", libraryID: "i.A1",
             clean: song("1001", "Static After Midnight", "Soft Circuits", album: "Side Effects"),
             explicit: song("2001", "Static After Midnight", "Soft Circuits", album: "Side Effects", seconds: 222),
             alreadyInLibrary: false, protectedBy: []),
        Swap(localID: "A2", libraryID: "i.A2",
             clean: song("1002", "Paper Teeth", "Juniper Vale", album: "Small Hours (Clean)", track: 2, seconds: 187),
             explicit: song("2002", "Paper Teeth", "Juniper Vale", album: "Small Hours", track: 2, seconds: 189, released: "2021-03-05"),
             alreadyInLibrary: true, protectedBy: []),
        Swap(localID: "A3", libraryID: "i.A3",
             clean: song("1003", "Everybody Wants a Little Noise Tonight", "The Lowlight Parade", album: "Overpass", track: 9, seconds: 254),
             explicit: song("2003", "Everybody Wants a Little Noise Tonight", "The Lowlight Parade", album: "Overpass (Deluxe)", track: 9, seconds: 254),
             alreadyInLibrary: false, protectedBy: ["Playlist: Road Trip", "Purchased track"]),
    ]

    static let choosable = Unmatched(
        localID: "U1",
        song: SongInfo(title: "Gravel Hymn", artist: "Mara Quill", album: "Undertow", disc: 1, track: 6, milliseconds: 201_000),
        reason: "Multiple explicit editions matched.",
        candidates: [
            song("3001", "Gravel Hymn", "Mara Quill", album: "Undertow", track: 6, seconds: 201, released: "2018-04-20"),
            song("3002", "Gravel Hymn", "Mara Quill", album: "Undertow (10th Anniversary)", track: 6, seconds: 202, released: "2028-04-20"),
        ]
    )

    static let unmatched = Unmatched(
        localID: "U2",
        song: SongInfo(title: "Neon Psalm", artist: "Dead Air Choir", album: "Vigil", disc: 1, track: 1, milliseconds: 233_000),
        reason: "No playable explicit edition matched.",
        candidates: []
    )

    static var review: Review {
        Review(version: 1, storefront: "us", swaps: swaps, unmatched: [choosable, unmatched])
    }

    /// A queue with `decided` decisions already made, alternating approve and skip.
    static func queue(decided: Int) -> ReviewQueue {
        var queue = ReviewQueue(review: review)
        for index in 0..<decided {
            queue.decide(index == 1 ? .skip : .approve)
        }
        return queue
    }

    static var finishedQueue: ReviewQueue { queue(decided: swaps.count) }

    static var cleanedUpQueue: ReviewQueue {
        var queue = finishedQueue
        var summary = CleanupSummary()
        summary.removedIDs = ["A1"]
        summary.kept = [RetainedTrack(swaps[2], reason: .preserved("Playlist: Road Trip, Purchased track"))]
        queue.startChanges()
        queue.recordApplication(.cleanup(summary))
        return queue
    }

    static var emptyQueue: ReviewQueue {
        ReviewQueue(review: Review(version: 1, storefront: "us", swaps: [], unmatched: [unmatched]))
    }
}
#endif
