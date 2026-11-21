import Foundation
import MusicKit

@MainActor
func authorizeLibrary() async throws {
    guard await MusicAuthorization.request() == .authorized else {
        throw ToolError("Allow Unbleep under Media & Apple Music in System Settings → Privacy & Security.")
    }
}

private func cleanSources(for local: LocalSong, in cloud: [Resource], catalog: [String: Resource]) -> [Resource] {
    cloud.filter { entry in
        guard let id = entry.catalogID, let song = catalog[id],
              song.attributes?.contentRating == "clean", let info = entry.song?.info else { return false }
        return local.info.matchesLibraryEntry(info)
    }
}

private func possibleSourceIDs(for local: [LocalSong], in cloud: [Resource]) -> Set<String> {
    Set(cloud.compactMap { resource in
        guard let info = resource.song?.info,
              local.contains(where: { $0.info.matchesLibraryEntry(info) }) else { return nil }
        return resource.catalogID
    })
}

private enum PreviewMatch {
    case swap(Swap)
    case unmatched(Unmatched)
}

@MainActor
private func findPreviewMatch(
    for local: LocalSong, in cloud: [Resource], catalog: [String: Resource], using api: AppleMusic
) async throws -> PreviewMatch {
    let sources = cleanSources(for: local, in: cloud, catalog: catalog)
    guard sources.count == 1, let librarySong = sources.first, let id = librarySong.catalogID,
          let catalogSong = catalog[id], let original = catalogSong.song,
          local.info.matchesLibraryEntry(original.info) else {
        let reason = sources.count > 1 ? "Multiple clean library entries match this track."
                                      : "No clean catalog version could be verified in the synced library."
        return .unmatched(Unmatched(localID: local.id, song: local.info, reason: reason, candidates: []))
    }

    var candidates: [SongReference] = []
    var match = "Apple-linked album edition"
    if let albumID = catalogSong.albumID {
        var linkedTracks: [Resource] = []
        for version in try await api.alternateAlbums(albumID) where isCatalogID(version.id) {
            try await linkedTracks.append(contentsOf: api.albumTracks(version.id))
        }
        candidates = explicitMatches(for: original, in: linkedTracks)
    }
    if candidates.isEmpty {
        candidates = explicitMatches(for: original, in: try await api.search(original.info))
        match = "Catalog search"
    }
    guard candidates.count == 1, let replacement = candidates.first else {
        let reason = candidates.isEmpty ? "No playable explicit edition matched." : "Multiple explicit editions matched."
        return .unmatched(Unmatched(localID: local.id, song: local.info, reason: reason, candidates: candidates))
    }
    return .swap(Swap(localID: local.id, libraryID: librarySong.id, clean: original, explicit: replacement,
                      match: match, alreadyInLibrary: containsCatalogSong(replacement, in: cloud),
                      protectedBy: local.protections))
}

@MainActor
func preview(
    using api: AppleMusic, local: [LocalSong], onProgress: (String) -> Void = { _ in }
) async throws -> Review {
    let clean = local.filter(\.isClean)
    print("Checking \(clean.count) clean tracks against your Apple Music library (\(api.storefront))…")
    onProgress("Reading your synced Music library…")
    let cloud = try await api.librarySongs { count in
        onProgress("Reading your synced Music library… \(count.formatted()) tracks loaded")
    }
    onProgress("Looking up catalog information for \(clean.count) clean tracks…")
    let catalog = try await api.catalogSongs(ids: possibleSourceIDs(for: clean, in: cloud))
    var outcomes: [(Int, PreviewMatch)] = []
    for start in stride(from: 0, to: clean.count, by: 4) {
        try await withThrowingTaskGroup(of: (Int, PreviewMatch).self) { group in
            for (index, song) in clean.enumerated().dropFirst(start).prefix(4) {
                group.addTask { (index, try await findPreviewMatch(for: song, in: cloud, catalog: catalog, using: api)) }
            }
            for try await match in group {
                outcomes.append(match)
                onProgress("Compared \(outcomes.count) of \(clean.count) clean tracks…")
            }
        }
    }
    var swaps: [Swap] = []
    var unmatched: [Unmatched] = []
    for (_, match) in outcomes.sorted(by: { $0.0 < $1.0 }) {
        switch match {
        case .swap(let swap): swaps.append(swap)
        case .unmatched(let item): unmatched.append(item)
        }
    }
    // A matched cloud ID must identify only one local clean entry.
    let counts = swaps.reduce(into: [String: Int]()) { $0[$1.libraryID, default: 0] += 1 }
    var unambiguous: [Swap] = []
    for swap in swaps {
        if counts[swap.libraryID] == 1 {
            unambiguous.append(swap)
        } else {
            unmatched.append(Unmatched(localID: swap.localID, song: swap.clean.info,
                reason: "Multiple clean tracks on this Mac match the same synced library entry.", candidates: [swap.explicit]))
        }
    }
    return Review(version: 1, storefront: api.storefront, scanned: clean.count, swaps: unambiguous, unmatched: unmatched)
}

struct VerifiedSwap {
    let swap: Swap
    let local: LocalSong
    let explicitIsInCloud: Bool
    let explicitLocalID: String?

    var removalBlocker: String? {
        if !local.protections.isEmpty { return local.protections.joined(separator: ", ") }
        if !explicitIsInCloud || explicitLocalID == nil { return "Couldn't verify the explicit track in both libraries" }
        return nil
    }
}

@MainActor
func resolveManualSwap(
    _ item: Unmatched, candidateID: String, storefront: String, using api: AppleMusic
) async throws -> Swap {
    guard storefront == api.storefront,
          item.canChooseEdition,
          item.candidates.contains(where: { $0.id == candidateID }) else {
        throw ToolError("This edition no longer belongs to the review. Scan again to refresh the matches.")
    }
    let clean = try readMacLibrary().filter { $0.isClean && $0.info.matchesLibraryEntry(item.song) }
    guard clean.count == 1, let local = clean.first, local.id == item.localID, isLocalID(local.id) else {
        throw ToolError("Unbleep couldn’t identify one clean copy on this Mac. Scan again to refresh the matches.")
    }
    let cloud = try await api.librarySongs()
    let sourceIDs = possibleSourceIDs(for: [local], in: cloud)
    let catalog = try await api.catalogSongs(ids: sourceIDs.union([candidateID]))
    let sources = cleanSources(for: local, in: cloud, catalog: catalog)
    guard sources.count == 1, let source = sources.first, let id = source.catalogID,
          let original = catalog[id]?.song, local.info.matchesLibraryEntry(original.info) else {
        throw ToolError("Unbleep couldn’t verify the clean copy in your synced library. Scan again once Music finishes syncing.")
    }
    guard let candidate = catalog[candidateID], let replacement = explicitMatch(for: original, in: candidate) else {
        throw ToolError("Apple Music no longer shows this as a playable explicit match.")
    }
    return Swap(localID: local.id, libraryID: source.id, clean: original, explicit: replacement,
                match: "Selected during review", alreadyInLibrary: containsCatalogSong(replacement, in: cloud),
                protectedBy: local.protections)
}

@MainActor
func removeIfCurrent(_ item: VerifiedSwap, in library: [LocalSong]) throws -> CleanRemovalOutcome {
    let swap = item.swap
    if let blocker = item.removalBlocker { return .kept(blocker) }
    guard library.contains(where: {
        $0.id == swap.localID && $0.isClean && $0.info == item.local.info && $0.protections.isEmpty
    }), let explicitID = item.explicitLocalID, library.contains(where: {
        $0.id == explicitID && $0.isExplicit && $0.info.matchesLibraryEntry(swap.explicit.info)
    }) else {
        return .kept("The local library changed during review.")
    }
    return try removeCleanSong(swap, explicitID: explicitID)
}

@MainActor
func verify(
    _ review: Review, using api: AppleMusic,
    onAlreadyAbsent: (Swap) -> Void = { _ in }, onSkip: (Swap) -> Void = { _ in }
) async throws -> [VerifiedSwap] {
    guard review.version == 1, review.storefront == api.storefront else {
        throw ToolError("This review belongs to a different storefront or tool version. Run preview again.")
    }
    let cloud = try await api.librarySongs()
    let local = try readMacLibrary()
    let clean = local.filter(\.isClean)
    let explicit = local.filter(\.isExplicit)
    let reviewedIDs = Set(review.swaps.flatMap { [$0.clean.id, $0.explicit.id] }.filter(isCatalogID))
    let reviewedLocalIDs = Set(review.swaps.map(\.localID))
    let ids = possibleSourceIDs(for: clean.filter { reviewedLocalIDs.contains($0.id) }, in: cloud)
    let catalog = try await api.catalogSongs(ids: reviewedIDs.union(ids))
    var verified: [VerifiedSwap] = []
    for swap in review.swaps {
        guard let original = catalog[swap.clean.id]?.song,
              catalog[swap.clean.id]?.attributes?.contentRating == "clean",
              original.info.matchesLibraryEntry(swap.clean.info),
              let replacement = catalog[swap.explicit.id],
              let target = explicitMatch(for: original, in: replacement),
              target.info.matchesLibraryEntry(swap.explicit.info) else {
            onSkip(swap)
            continue
        }
        let explicitIsInCloud = containsCatalogSong(target, in: cloud)
        let localMatches = clean.filter { $0.info.matchesLibraryEntry(original.info) }
        if explicitIsInCloud, localMatches.isEmpty, !local.contains(where: { $0.id == swap.localID }),
           !cloud.contains(where: { $0.id == swap.libraryID || $0.catalogID == original.id }) {
            onAlreadyAbsent(swap)
            continue
        }
        guard localMatches.count == 1, let source = localMatches.first, source.id == swap.localID,
              isLocalID(source.id),
              cleanSources(for: source, in: cloud, catalog: catalog).map(\.id) == [swap.libraryID],
              cloud.contains(where: { $0.id == swap.libraryID && $0.catalogID == original.id }) else {
            onSkip(swap)
            continue
        }
        let localReplacements = explicit.filter { $0.info.matchesLibraryEntry(target.info) }
        verified.append(VerifiedSwap(swap: swap, local: source,
            explicitIsInCloud: explicitIsInCloud,
            explicitLocalID: localReplacements.count == 1 ? localReplacements.first?.id : nil))
    }
    return verified
}
