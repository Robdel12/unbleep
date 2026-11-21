import Foundation

struct ReviewQueue: Codable {
    enum Decision: String, Codable {
        case approve
        case skip
    }

    let review: Review
    private(set) var decisions: [Decision] = []
    private(set) var changesStarted = false
    private(set) var application: ReviewApplication?
    private var manualSwaps: [Swap]?

    var current: Swap? {
        review.swaps.indices.contains(decisions.count) ? review.swaps[decisions.count] : nil
    }

    var canUndo: Bool { !changesStarted && (!decisions.isEmpty || manualSwaps?.isEmpty == false) }
    var skippedCount: Int { decisions.count(where: { $0 == .skip }) }

    var unmatched: [Unmatched] {
        let selectedIDs = Set((manualSwaps ?? []).map(\.localID))
        return review.unmatched.filter { !selectedIDs.contains($0.localID) }
    }

    var approvedSwaps: [Swap] {
        let swaps = zip(review.swaps, decisions).compactMap { swap, decision in decision == .approve ? swap : nil }
        return swaps + (manualSwaps ?? [])
    }

    var approved: Review {
        Review(version: review.version, storefront: review.storefront, swaps: approvedSwaps, unmatched: [])
    }

    mutating func decide(_ decision: Decision) {
        guard current != nil, !changesStarted else { return }
        decisions.append(decision)
    }

    mutating func undo() {
        guard canUndo else { return }
        if manualSwaps?.isEmpty == false {
            manualSwaps?.removeLast()
            if manualSwaps?.isEmpty == true {
                application = application?.cleanupSummary.map { .cleanup($0) }
            }
            return
        }
        decisions.removeLast()
        application = nil
    }

    mutating func startChanges() {
        guard current == nil, !approvedSwaps.isEmpty else { return }
        changesStarted = true
    }

    mutating func recordApplication(_ application: ReviewApplication) {
        guard current == nil, !approvedSwaps.isEmpty else { return }
        self.application = application
    }

    mutating func queueManualSwap(_ swap: Swap) throws {
        guard current == nil,
              let item = unmatched.first(where: { $0.localID == swap.localID }),
              item.canChooseEdition,
              item.candidates.contains(where: { $0.id == swap.explicit.id }) else {
            throw ToolError("This song is no longer waiting for an edition choice.")
        }
        let reviewed = review.swaps + (manualSwaps ?? [])
        guard !reviewed.contains(where: { $0.localID == swap.localID || $0.libraryID == swap.libraryID }) else {
            throw ToolError("This clean library entry already has a swap in the review.")
        }
        manualSwaps = (manualSwaps ?? []) + [swap]
        application = .pendingAdditions(application?.cleanupSummary)
    }

    var nextApplicationAction: ApplicationAction? {
        let approvedCount = approvedSwaps.count
        guard current == nil, approvedCount > 0 else { return nil }
        switch application {
        case .pendingAdditions:
            return .addApproved
        case .additions:
            return .checkSync
        case .cleanup(let summary):
            if summary.needsAdditions { return .addMissing }
            let reported = summary.removedIDs.count + summary.absentIDs.count + summary.kept.count
            return summary.needsSyncCheck || reported < approvedCount ? .checkSync : nil
        case nil:
            return changesStarted ? .checkSync : .addApproved
        }
    }

    enum ApplicationAction: Equatable {
        case addApproved
        case addMissing
        case checkSync
    }
}
