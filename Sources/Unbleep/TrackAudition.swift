import Foundation
@preconcurrency import MusicKit
import Observation

@MainActor
@Observable
final class TrackAudition {
    enum Side {
        case clean
        case explicit

        var label: String { self == .clean ? "Clean" : "Explicit" }

        func song(in swap: Swap) -> SongReference {
            self == .clean ? swap.clean : swap.explicit
        }
    }

    enum State {
        case idle
        case loading(Side)
        case ready(Side)
        case failed(String)
    }

    private(set) var state: State = .idle
    let player = ApplicationMusicPlayer.shared
    @ObservationIgnored private var operation: Task<Void, Never>?
    @ObservationIgnored private var loadedPair: (id: String, songs: [Song])?

    var activeSide: Side? {
        if case .ready(let side) = state { return side }
        return nil
    }

    var isLoading: Bool {
        if case .loading = state { return true }
        return false
    }

    func toggle(_ side: Side, in swap: Swap, authorize: @escaping @MainActor () async throws -> Void) {
        guard !isLoading else { return }
        let status = player.state.playbackStatus
        if activeSide == side && status == .playing {
            player.pause()
            return
        }

        let canResume = activeSide == side && status == .paused
        let position = activeSide != nil && status != .stopped ? player.playbackTime : 0
        if activeSide != nil && !canResume { player.pause() }
        state = .loading(side)
        let previous = operation
        operation = Task {
            await previous?.value
            do {
                try Task.checkCancellation()
                if !canResume {
                    let song = try await playableSong(for: side, in: swap, authorize: authorize)
                    try Task.checkCancellation()
                    let queue = ApplicationMusicPlayer.Queue(for: [song])
                    if #available(macOS 26.4, *) { queue.affectsListeningHistory = false }
                    player.queue = queue
                    try await player.prepareToPlay()
                    try Task.checkCancellation()
                    seek(to: position, duration: song.duration ?? Double(side.song(in: swap).info.milliseconds) / 1000)
                }
                try await player.play()
                try Task.checkCancellation()
                state = .ready(side)
            } catch {
                player.stop()
                if !Task.isCancelled { state = .failed(error.localizedDescription) }
            }
        }
    }

    func seek(to position: TimeInterval, duration: TimeInterval) {
        guard position.isFinite, duration.isFinite, duration > 0 else { return }
        player.playbackTime = min(max(position, 0), max(0, duration - 0.25))
    }

    func stop() {
        operation?.cancel()
        if isLoading || activeSide != nil { player.stop() }
        state = .idle
        loadedPair = nil
    }

    private func playableSong(
        for side: Side, in swap: Swap, authorize: @MainActor () async throws -> Void
    ) async throws -> Song {
        if loadedPair?.id != swap.localID {
            let ids = [swap.clean.id, swap.explicit.id]
            guard ids.allSatisfy(isCatalogID), ids[0] != ids[1] else {
                throw ToolError("This pair needs valid Apple Music song IDs before it can play.")
            }
            try await authorize()
            guard try await MusicSubscription.current.canPlayCatalogContent else {
                throw ToolError("Playing full tracks requires an active Apple Music subscription.")
            }
            let request = MusicCatalogResourceRequest<Song>(matching: \.id, memberOf: ids.map { MusicItemID($0) })
            let response = try await request.response()
            try Task.checkCancellation()
            loadedPair = (swap.localID, Array(response.items))
        }
        let id = side.song(in: swap).id
        let rating: ContentRating = side == .clean ? .clean : .explicit
        guard let song = loadedPair?.songs.first(where: { $0.id.rawValue == id && $0.contentRating == rating }),
              song.playParameters != nil else {
            throw ToolError("The \(side.label.lowercased()) edition couldn’t be verified for playback in your Apple Music storefront.")
        }
        return song
    }
}
