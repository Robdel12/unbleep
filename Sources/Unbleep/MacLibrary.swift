import Foundation
import iTunesLibrary

struct LocalSong {
    let id: String
    let info: SongInfo
    let isClean: Bool
    let isExplicit: Bool
    let protections: [String]
}

func isLocalID(_ id: String) -> Bool {
    id.utf8.count == 16 && id.utf8.allSatisfy { (48...57).contains($0) || (65...70).contains($0) }
}

private func persistentID(_ item: ITLibMediaItem) -> String {
    String(format: "%016llX", item.persistentID.uint64Value)
}

func readMacLibrary() throws -> [LocalSong] {
    let library = try ITLibrary(apiVersion: "1.1")
    var playlists: [String: Set<String>] = [:]
    // Zero is ITLibDistinguishedPlaylistKindNone (a user playlist).
    for playlist in library.allPlaylists where !playlist.isPrimary && playlist.distinguishedKind.rawValue == 0 {
        for item in playlist.items {
            playlists[persistentID(item), default: []].insert(playlist.name)
        }
    }
    return library.allMediaItems.filter { $0.mediaKind == .kindSong }.map { item in
        let id = persistentID(item)
        var protections = playlists[id, default: []].sorted().map { "Playlist: \($0)" }
        if item.locationType == .file {
            protections.append("Downloaded or local file")
        }
        if item.isPurchased { protections.append("Purchased track") }
        let info = SongInfo(title: item.title, artist: item.artist?.name ?? "", album: item.album.title ?? "",
                            disc: max(1, item.album.discNumber), track: item.trackNumber, milliseconds: item.totalTime)
        return LocalSong(id: id, info: info, isClean: item.lyricsContentRating == .clean,
                         isExplicit: item.lyricsContentRating == .explicit, protections: protections)
    }
}

enum CleanRemovalOutcome: Equatable {
    case removed
    case alreadyAbsent
    case kept(String)
}

@MainActor
func removeCleanSong(_ swap: Swap, explicitID: String) throws -> CleanRemovalOutcome {
    guard let outcome = try cleanSongOutcome(swap, explicitID: explicitID, remove: true) else {
        throw ToolError("Music didn't confirm the removal result.")
    }
    return outcome
}

@MainActor
func checkCleanSong(_ swap: Swap, explicitID: String) throws -> CleanRemovalOutcome? {
    try cleanSongOutcome(swap, explicitID: explicitID, remove: false)
}

@MainActor
private func cleanSongOutcome(_ swap: Swap, explicitID: String, remove: Bool) throws -> CleanRemovalOutcome? {
    guard isLocalID(swap.localID), isLocalID(explicitID), swap.localID != explicitID else {
        throw ToolError("Invalid Music persistent ID.")
    }
    // The local SDK checks the rating and local files. Recheck Music's live
    // playlist membership, cloud status and favorites before sending delete.
    let finish = remove ? """
        delete (some track of musicLibrary whose persistent ID is itemID)
        if exists (some track of musicLibrary whose persistent ID is itemID) then
            return "Music still shows the clean track"
        end if
        return "Removed in Music"
        """ : #"return "Ready for removal""#
    let source = """
    with timeout of 25 seconds
        tell application id "com.apple.Music"
            set itemID to "\(swap.localID)"
            set musicLibrary to first library playlist
            set foundTracks to (every track of musicLibrary whose persistent ID is itemID)
            if (count of foundTracks) is 0 then return "Already absent in Music"
            if (count of foundTracks) is not 1 then return "Persistent ID is ambiguous"
            set cleanTrack to item 1 of foundTracks
            if media kind of cleanTrack is not song or cloud status of cleanTrack is not subscription then
                return "Music did not identify this as an Apple Music subscription song"
            end if
            if favorited of cleanTrack then return "Favorited in Music"
            if class of cleanTrack is file track then
                if location of cleanTrack is not missing value then return "Downloaded or local file"
            end if
            repeat with customPlaylist in (every user playlist whose special kind is none)
                if exists (some track of customPlaylist whose persistent ID is itemID) then
                    return "Playlist: " & name of customPlaylist
                end if
            end repeat
            if not (exists (some track of musicLibrary whose persistent ID is "\(explicitID)")) then
                return "The explicit track is no longer in Music"
            end if
            \(finish)
        end tell
    end timeout
    """
    guard let script = NSAppleScript(source: source) else { throw ToolError("Couldn't create the Music automation script.") }
    var details: NSDictionary?
    let result = script.executeAndReturnError(&details)
    if let details {
        let message = details[NSAppleScript.errorMessage] as? String ?? "The Music automation command failed."
        throw ToolError(message)
    }
    guard let status = result.stringValue else { throw ToolError("Music didn't confirm the removal result.") }
    switch status {
    case "Ready for removal": return nil
    case "Removed in Music": return .removed
    case "Already absent in Music": return .alreadyAbsent
    default: return .kept(status)
    }
}
