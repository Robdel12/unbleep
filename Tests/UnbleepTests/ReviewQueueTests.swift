import Foundation
import Testing
@testable import Unbleep

@Test func approvalAndSkipAdvanceToTheNextTrack() {
    var queue = reviewQueue()
    #expect(queue.current?.localID == "first")

    queue.decide(.approve)
    #expect(queue.current?.localID == "second")

    queue.decide(.skip)
    #expect(queue.current == nil)
    #expect(queue.approved.swaps.map(\.localID) == ["first"])
    #expect(queue.skippedCount == 1)
}

@Test func resumingAndUndoingReturnsToTheLastDecision() throws {
    var original = reviewQueue()
    original.decide(.skip)
    original.decide(.approve)
    let saved = try JSONEncoder().encode(original)
    var resumed = try JSONDecoder().decode(ReviewQueue.self, from: saved)

    resumed.undo()
    #expect(resumed.current?.localID == "second")
    #expect(resumed.approved.swaps.isEmpty)
    #expect(resumed.skippedCount == 1)
}

@Test func undoStopsWhenLibraryChangesStart() {
    var queue = reviewQueue()
    queue.decide(.approve)
    queue.startChanges()
    #expect(queue.canUndo)

    queue.decide(.skip)
    queue.startChanges()
    queue.undo()
    #expect(queue.current == nil)
    #expect(queue.approved.swaps.map(\.localID) == ["first"])
}

@Test func aPreviouslyAppliedReviewReopensAtTheSyncCheck() throws {
    var queue = reviewQueue()
    queue.decide(.approve)
    queue.decide(.skip)
    #expect(queue.nextApplicationAction == .addApproved)

    queue.startChanges()
    let saved = try JSONEncoder().encode(queue)
    let resumed = try JSONDecoder().decode(ReviewQueue.self, from: saved)

    #expect(resumed.application == nil)
    #expect(resumed.nextApplicationAction == .checkSync)
}

@Test func cleanupResultsSaveTheTrackMusicKeptAndItsReason() throws {
    var queue = reviewQueue()
    queue.decide(.approve)
    queue.decide(.approve)
    queue.startChanges()
    queue.recordApplication(.additions(submitted: 2, unverified: 0, previousCleanup: nil))
    #expect(queue.nextApplicationAction == .checkSync)

    var summary = CleanupSummary()
    summary.record(.removed, for: queue.review.swaps[0])
    queue.recordApplication(.cleanup(summary))
    #expect(queue.nextApplicationAction == .checkSync)

    summary.record(.kept("Favorited in Music"), for: queue.review.swaps[1])
    queue.recordApplication(.cleanup(summary))
    let saved = try JSONEncoder().encode(queue)
    let resumed = try JSONDecoder().decode(ReviewQueue.self, from: saved)
    let results = try #require(resumed.application?.cleanupSummary)

    #expect(results.removedIDs == ["first"])
    #expect(results.absentIDs.isEmpty)
    #expect(results.kept.map(\.song.title) == ["second"])
    #expect(results.kept.map(\.reason.description) == ["Favorited in Music"])
    #expect(resumed.nextApplicationAction == nil)
}

@Test func cleanupCanRetryAMissingVersionAndKeepEarlierResults() throws {
    var queue = reviewQueue()
    queue.decide(.approve)
    queue.decide(.approve)
    var summary = CleanupSummary()
    summary.record(.alreadyAbsent, for: queue.review.swaps[0])
    summary.kept = [RetainedTrack(queue.review.swaps[1], reason: .missingExplicit)]
    queue.recordApplication(.cleanup(summary))
    #expect(queue.nextApplicationAction == .addMissing)

    queue.recordApplication(.additions(submitted: 1, unverified: 0, previousCleanup: summary))
    #expect(queue.nextApplicationAction == .checkSync)
    let results = try #require(queue.application?.cleanupSummary)
    #expect(results.absentIDs == ["first"])
    #expect(results.removedIDs.isEmpty)
}

@Test func choosingAnExplicitEditionRestartsAdditionsAndKeepsPreviousResults() throws {
    let (item, swap) = manualChoice()
    var queue = reviewQueue(unmatched: [item])
    queue.decide(.approve)
    queue.decide(.skip)
    queue.startChanges()
    var earlierResults = CleanupSummary()
    earlierResults.record(.removed, for: queue.review.swaps[0])
    queue.recordApplication(.cleanup(earlierResults))
    #expect(queue.nextApplicationAction == nil)

    try queue.queueManualSwap(swap)
    let saved = try JSONEncoder().encode(queue)
    let resumed = try JSONDecoder().decode(ReviewQueue.self, from: saved)

    #expect(resumed.current == nil)
    #expect(resumed.unmatched.isEmpty)
    #expect(resumed.approved.swaps.map(\.localID) == ["first", item.localID])
    #expect(resumed.approved.swaps.last?.explicit.id == swap.explicit.id)
    #expect(resumed.skippedCount == 1)
    #expect(resumed.nextApplicationAction == .addApproved)
    #expect(resumed.application?.cleanupSummary?.removedIDs == ["first"])
}

@Test func aDraftEditionChoiceCanBeUndoneAndChosenAgain() throws {
    let (item, swap) = manualChoice()
    var queue = reviewQueue(unmatched: [item])
    queue.decide(.skip)
    queue.decide(.skip)
    try queue.queueManualSwap(swap)
    #expect(throws: ToolError.self) { try queue.queueManualSwap(swap) }

    queue.undo()
    #expect(queue.approved.swaps.isEmpty)
    #expect(queue.unmatched.map(\.localID) == [item.localID])
    #expect(queue.skippedCount == 2)
    try queue.queueManualSwap(swap)
    #expect(queue.approved.swaps.map(\.localID) == [item.localID])
}

@Test func aTrackWithoutAlternativeEditionsStaysOutOfTheSwapQueue() {
    let (item, swap) = manualChoice()
    let blocked = Unmatched(localID: item.localID, song: item.song, reason: "Unverified clean copy",
                            candidates: [swap.explicit])
    var queue = reviewQueue(unmatched: [blocked])
    queue.decide(.skip)
    queue.decide(.skip)

    #expect(!blocked.canChooseEdition)
    #expect(throws: ToolError.self) { try queue.queueManualSwap(swap) }
    #expect(queue.approved.swaps.isEmpty)
}

private func manualChoice() -> (Unmatched, Swap) {
    let info = SongInfo(title: "Third", artist: "The Artist", album: "The Album",
                        disc: 1, track: 3, milliseconds: 200_000)
    let candidates = ["31", "32"].map { SongReference(id: $0, info: info, url: nil) }
    let item = Unmatched(localID: "third", song: info, reason: "Multiple explicit editions matched.",
                         candidates: candidates)
    let swap = Swap(localID: item.localID, libraryID: "i.third",
                    clean: SongReference(id: "30", info: info, url: nil), explicit: candidates[1],
                    match: "Selected during review", alreadyInLibrary: false, protectedBy: [])
    return (item, swap)
}

private func reviewQueue(unmatched: [Unmatched] = []) -> ReviewQueue {
    let tracks = ["first", "second"].enumerated().map { position, id in
        let info = SongInfo(title: id, artist: "The Artist", album: "The Album",
                            disc: 1, track: position + 1, milliseconds: 200_000)
        return Swap(localID: id, libraryID: "i.\(id)", clean: SongReference(id: "1\(position)", info: info, url: nil),
                    explicit: SongReference(id: "2\(position)", info: info, url: nil),
                    match: "Catalog search", alreadyInLibrary: false, protectedBy: [])
    }
    return ReviewQueue(review: Review(version: 1, storefront: "us", scanned: tracks.count + unmatched.count,
                                     swaps: tracks, unmatched: unmatched))
}
