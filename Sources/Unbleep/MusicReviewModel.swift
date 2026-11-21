import Foundation
import Observation

struct MusicKitSetup: Codable {
    var teamID = ""
    var keyID = ""
    var keyPath = ""

    var isComplete: Bool {
        [teamID, keyID, keyPath].allSatisfy { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    var environment: [String: String] {
        var environment = ProcessInfo.processInfo.environment
        if isComplete {
            environment.removeValue(forKey: "MUSIC_DEVELOPER_TOKEN")
            environment["MUSIC_TEAM_ID"] = teamID.trimmingCharacters(in: .whitespacesAndNewlines)
            environment["MUSIC_KEY_ID"] = keyID.trimmingCharacters(in: .whitespacesAndNewlines)
            environment["MUSIC_KEY_FILE"] = keyPath
        }
        return environment
    }
}

@Observable
@MainActor
final class MusicReviewModel {
    enum Activity {
        case idle
        case working(String)
        case message(String)
        case confirmRemoval(RemovalPlan)
    }

    private(set) var queue: ReviewQueue?
    private(set) var setup = MusicKitSetup()
    private(set) var activity: Activity = .idle
    private let defaults: UserDefaults?
    @ObservationIgnored private var catalogCache = CatalogResponseCache()

    init(defaults: UserDefaults? = .standard, opening url: URL? = nil) {
        self.defaults = defaults
        if let data = defaults?.data(forKey: "musicKitSetup"),
           let setup = try? JSONDecoder().decode(MusicKitSetup.self, from: data) {
            self.setup = setup
        }
        if let url {
            openReview(url)
        } else if let data = defaults?.data(forKey: "reviewQueue"),
                  let queue = try? JSONDecoder().decode(ReviewQueue.self, from: data),
                  (try? queue.review.validate()) != nil {
            self.queue = queue
        }
    }

    var isWorking: Bool {
        if case .working = activity { return true }
        return false
    }

    var removalPlan: RemovalPlan? {
        if case .confirmRemoval(let plan) = activity { return plan }
        return nil
    }

    func saveSetup(_ setup: MusicKitSetup) {
        self.setup = setup
        catalogCache = CatalogResponseCache()
        defaults?.set(try? JSONEncoder().encode(setup), forKey: "musicKitSetup")
    }

    func report(_ error: Error) {
        activity = .message(error.localizedDescription)
    }

    func openReview(_ url: URL) {
        guard !isWorking else { return }
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        do {
            let review = try JSONDecoder().decode(Review.self, from: Data(contentsOf: url))
            try review.validate()
            queue = ReviewQueue(review: review)
            activity = .idle
            saveQueue()
        } catch {
            report(error)
        }
    }

    func decide(_ decision: ReviewQueue.Decision) {
        guard !isWorking else { return }
        queue?.decide(decision)
        saveQueue()
    }

    func undo() {
        guard !isWorking else { return }
        queue?.undo()
        activity = .idle
        saveQueue()
    }

    func scan() async {
        await perform("Connecting to Apple Music…") {
            let api = try await connect(catalogCache: catalogCache)
            activity = .working("Reading tracks on this Mac…")
            let local = try readMacLibrary()
            let review = try await preview(using: api, local: local) { message in
                activity = .working(message)
            }
            queue = ReviewQueue(review: review)
            saveQueue()
            return .idle
        }
    }

    func compareManualEdition(_ item: Unmatched, candidateID: String) async -> Swap? {
        guard let queue, queue.current == nil else { return nil }
        var comparison: Swap?
        await perform("Verifying both versions of \(item.song.title)…") {
            let api = try await connect(catalogCache: catalogCache)
            comparison = try await resolveManualSwap(item, candidateID: candidateID, storefront: queue.review.storefront, using: api)
            return .idle
        }
        return comparison
    }

    func queueManualSwap(_ swap: Swap) throws {
        guard !isWorking else { return }
        try queue?.queueManualSwap(swap)
        saveQueue()
        activity = .idle
    }

    func addApproved() async {
        guard let approved else { return }
        await perform("Checking approved tracks…") {
            let api = try await connect()
            var alreadyAbsent = 0
            let verified = try await verify(approved, using: api, onAlreadyAbsent: { _ in alreadyAbsent += 1 })
            let ids = Set(verified.filter { !$0.explicitIsInCloud }.map { $0.swap.explicit.id })
            let unverified = approved.swaps.count - verified.count - alreadyAbsent
            if verified.isEmpty && alreadyAbsent == 0 {
                return .message("None of the approved versions could be verified. Scan again to refresh the matches.")
            }
            if !ids.isEmpty {
                queue?.startChanges()
                saveQueue()
                activity = .working("Adding \(ids.count) explicit versions…")
                try await api.add(ids)
            }
            let previousCleanup = queue?.application?.cleanupSummary
            queue?.recordApplication(.additions(submitted: ids.count, unverified: unverified, previousCleanup: previousCleanup))
            saveQueue()
            return .idle
        }
    }

    func checkRemoval() async {
        guard let approved else { return }
        await perform("Checking Apple Music for explicit versions…") {
            let api = try await connect()
            var summary = CleanupSummary()
            let verified = try await verify(approved, using: api, onAlreadyAbsent: {
                summary.absentIDs.insert($0.localID)
            }, onSkip: {
                summary.kept.append(RetainedTrack($0, reason: .unverified))
            })
            if let previous = queue?.application?.cleanupSummary {
                summary.removedIDs = previous.removedIDs.intersection(summary.absentIDs)
                summary.absentIDs.subtract(summary.removedIDs)
            }
            var ready: [VerifiedSwap] = []
            var canInspectMusic = true
            for (index, item) in verified.enumerated() {
                let reason: RetainedTrack.Reason
                if !item.explicitIsInCloud {
                    reason = .missingExplicit
                } else if !item.local.protections.isEmpty {
                    reason = .preserved(item.local.protections.joined(separator: ", "))
                } else if let explicitID = item.explicitLocalID {
                    if canInspectMusic {
                        activity = .working("Checking clean copy \(index + 1) of \(verified.count) in Music…")
                        await Task.yield()
                        do {
                            if let outcome = try checkCleanSong(item.swap, explicitID: explicitID) {
                                summary.record(outcome, for: item.swap)
                                continue
                            }
                        } catch {
                            // Keep the live check on removal if Music automation isn't available here.
                            canInspectMusic = false
                        }
                    }
                    ready.append(item)
                    continue
                } else {
                    reason = .waitingForSync
                }
                summary.kept.append(RetainedTrack(item.swap, reason: reason))
            }
            guard !ready.isEmpty else {
                queue?.recordApplication(.cleanup(summary))
                saveQueue()
                return .idle
            }
            return .confirmRemoval(RemovalPlan(ready: ready, summary: summary))
        }
    }

    func cancelRemoval() {
        if case .confirmRemoval = activity { activity = .idle }
    }

    func remove(_ plan: RemovalPlan) async {
        await perform("Removing clean copies in Music…") {
            let library = try readMacLibrary()
            queue?.startChanges()
            saveQueue()
            var summary = plan.summary
            for (index, item) in plan.ready.enumerated() {
                activity = .working("Removing clean copies in Music (\(index + 1) of \(plan.ready.count))…")
                do {
                    summary.record(try removeIfCurrent(item, in: library), for: item.swap)
                } catch {
                    summary.kept.append(RetainedTrack(item.swap, reason: .unconfirmed(error.localizedDescription)))
                    for remaining in plan.ready.dropFirst(index + 1) {
                        summary.kept.append(RetainedTrack(remaining.swap, reason: .unconfirmed("The removal stopped before this track was checked.")))
                    }
                    break
                }
                queue?.recordApplication(.cleanup(summary))
                saveQueue()
                await Task.yield()
            }
            queue?.recordApplication(.cleanup(summary))
            saveQueue()
            return .idle
        }
    }

    private var approved: Review? {
        guard let queue, queue.current == nil else { return nil }
        let review = queue.approved
        return review.swaps.isEmpty ? nil : review
    }

    private func saveQueue() {
        guard let queue else { return }
        defaults?.set(try? JSONEncoder().encode(queue), forKey: "reviewQueue")
    }

    func authorizePlayback() async throws {
        try await authorizeLibrary()
        try AppleMusic.configureTokenProvider(environment: setup.environment)
    }

    private func connect(catalogCache: CatalogResponseCache? = nil) async throws -> AppleMusic {
        try await authorizeLibrary()
        return try await AppleMusic.connect(environment: setup.environment, catalogCache: catalogCache)
    }

    private func perform(_ label: String, _ work: () async throws -> Activity) async {
        guard !isWorking else { return }
        activity = .working(label)
        do {
            activity = try await work()
        } catch {
            report(error)
        }
    }
}
