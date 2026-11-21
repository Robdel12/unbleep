import Foundation

struct SongInfo: Codable, Equatable {
    let title: String
    let artist: String
    let album: String
    let disc: Int
    let track: Int
    let milliseconds: Int

    var description: String { "\(artist) — \(title) (\(album), disc \(disc), track \(track))" }

    func matchesLibraryEntry(_ other: Self) -> Bool {
        sameTrack(other, album: .exact, tolerance: 1_250)
    }

    func matchesExplicitEdition(_ other: Self) -> Bool {
        sameTrack(other, album: .ignoreRatingTag, tolerance: 3_000)
    }

    private enum AlbumComparison { case exact, ignoreRatingTag }

    private func sameTrack(_ other: Self, album comparison: AlbumComparison, tolerance: Int) -> Bool {
        guard track > 0, disc > 0, milliseconds > 0, other.milliseconds > 0,
              milliseconds <= Int32.max, other.milliseconds <= Int32.max,
              !title.isEmpty, !artist.isEmpty, !album.isEmpty else { return false }
        let albumName = { (title: String) in
            comparison == .exact ? normalized(title) : editionName(title)
        }
        return normalized(title) == normalized(other.title)
            && normalized(artist) == normalized(other.artist)
            && albumName(album) == albumName(other.album)
            && track == other.track && disc == other.disc
            && abs(milliseconds - other.milliseconds) <= tolerance
    }
}

func normalized(_ text: String) -> String {
    text.folding(options: [.caseInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        .replacingOccurrences(of: "’", with: "'")
        .split(whereSeparator: \.isWhitespace).joined(separator: " ")
}

private func editionName(_ text: String) -> String {
    normalized(text).replacingOccurrences(
        of: #"\s*(?:\((?:clean|explicit)(?: version| edition)?\)|\[(?:clean|explicit)(?: version| edition)?\])$"#,
        with: "",
        options: .regularExpression
    )
}

struct SongReference: Codable, Equatable {
    let id: String
    let info: SongInfo
    let url: URL?
    var releaseDate: String? = nil
}

struct Swap: Codable {
    let localID: String
    let libraryID: String
    let clean: SongReference
    let explicit: SongReference
    let match: String
    let alreadyInLibrary: Bool
    let protectedBy: [String]
}

struct Unmatched: Codable {
    let localID: String
    let song: SongInfo
    let reason: String
    let candidates: [SongReference]

    var canChooseEdition: Bool {
        Set(candidates.map(\.id).filter(isCatalogID)).count > 1
    }
}

struct Review: Codable {
    let version: Int
    let storefront: String
    let scanned: Int
    let swaps: [Swap]
    let unmatched: [Unmatched]

    func validate() throws {
        guard version == 1 else { throw ToolError("This review uses a different version. Scan the library again.") }
        guard Set(swaps.map(\.localID)).count == swaps.count,
              Set(swaps.map(\.libraryID)).count == swaps.count else {
            throw ToolError("This review has duplicate clean entries. Scan the library again.")
        }
    }
}

func explicitMatches(for original: SongReference, in catalog: [Resource]) -> [SongReference] {
    var unique: [String: SongReference] = [:]
    for song in catalog {
        if let match = explicitMatch(for: original, in: song) {
            unique[match.id] = match
        }
    }
    return unique.values.sorted { $0.id < $1.id }
}

func explicitMatch(for original: SongReference, in song: Resource) -> SongReference? {
    guard song.id != original.id, song.isPlayableExplicit,
          let candidate = song.song, original.info.matchesExplicitEdition(candidate.info) else { return nil }
    return candidate
}

func containsCatalogSong(_ song: SongReference, in library: [Resource]) -> Bool {
    library.contains { $0.catalogID == song.id && $0.song?.info.matchesLibraryEntry(song.info) == true }
}

struct ToolError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}
