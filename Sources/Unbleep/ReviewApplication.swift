import Foundation

enum ReviewApplication: Codable {
    case pendingAdditions(CleanupSummary?)
    case additions(submitted: Int, unverified: Int, previousCleanup: CleanupSummary?)
    case cleanup(CleanupSummary)

    var cleanupSummary: CleanupSummary? {
        switch self {
        case .pendingAdditions(let previous): return previous
        case .additions(_, _, let previous): return previous
        case .cleanup(let summary): return summary
        }
    }
}

struct CleanupSummary: Codable {
    var removedIDs: Set<String> = []
    var absentIDs: Set<String> = []
    var kept: [RetainedTrack] = []

    var needsAdditions: Bool { kept.contains { $0.reason == .missingExplicit } }
    var needsSyncCheck: Bool { kept.contains { $0.reason == .waitingForSync } }
    var preservedCount: Int {
        kept.count(where: {
            if case .preserved = $0.reason { return true }
            return false
        })
    }
    var needsAttentionCount: Int { kept.count - preservedCount }

    mutating func record(_ outcome: CleanRemovalOutcome, for swap: Swap) {
        switch outcome {
        case .removed:
            removedIDs.insert(swap.localID)
            absentIDs.remove(swap.localID)
        case .alreadyAbsent:
            if !removedIDs.contains(swap.localID) { absentIDs.insert(swap.localID) }
        case .kept(let reason):
            kept.append(RetainedTrack(swap, reason: .preserved(reason)))
        }
    }
}

struct RetainedTrack: Codable, Identifiable {
    enum Reason: Codable, Equatable {
        case preserved(String)
        case missingExplicit
        case waitingForSync
        case unverified
        case unconfirmed(String)

        var description: String {
            switch self {
            case .preserved(let reason), .unconfirmed(let reason): return reason
            case .missingExplicit: return "The explicit version hasn’t appeared in your library."
            case .waitingForSync: return "The explicit version is still syncing to this Mac."
            case .unverified: return "The reviewed versions could not be verified."
            }
        }
    }

    let id: String
    let song: SongInfo
    let reason: Reason

    init(_ swap: Swap, reason: Reason) {
        id = swap.localID
        song = swap.clean.info
        self.reason = reason
    }
}

struct RemovalPlan {
    let ready: [VerifiedSwap]
    let summary: CleanupSummary
}
