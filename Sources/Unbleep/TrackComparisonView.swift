import MusicKit
import SwiftUI

struct TrackComparisonView: View {
    let swap: Swap
    let audition: TrackAudition
    let authorize: @MainActor () async throws -> Void
    @ObservedObject private var playback = ApplicationMusicPlayer.shared.state

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 0) {
                track(.clean, heading: "In your library", shortcut: "1")
                Divider()
                track(.explicit, heading: "Replace with", shortcut: "2")
            }
            .fixedSize(horizontal: false, vertical: true)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay {
                RoundedRectangle(cornerRadius: 14).strokeBorder(.primary.opacity(0.12))
                    .allowsHitTesting(false)
            }

            switch audition.state {
            case .idle:
                EmptyView()
            case .loading(let side):
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Loading the \(side.label.lowercased()) version…")
                }
                .font(.callout)
                .foregroundStyle(.secondary)
            case .ready(let side):
                AuditionScrubber(audition: audition, side: side, duration: Double(side.song(in: swap).info.milliseconds) / 1000)
            case .failed(let message):
                Text(message).font(.callout).foregroundStyle(.secondary)
            }

            if !swap.protectedBy.isEmpty {
                Label("Keep the clean copy · \(swap.protectedBy.joined(separator: ", "))", systemImage: "lock")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func track(_ side: TrackAudition.Side, heading: String, shortcut: KeyEquivalent) -> some View {
        let song = side.song(in: swap)
        let replacement = side == .explicit
        let playing = audition.activeSide == side && playback.playbackStatus == .playing
        let action = playing ? "Pause" : "Play"
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text(heading).font(.headline)
                Spacer()
                Text(side.label)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(replacement ? Color.accentColor.opacity(0.14) : Color.primary.opacity(0.07), in: Capsule())
            }

            Text(song.info.title)
                .font(.system(.title, design: .default).weight(.semibold))
                .tracking(-0.55)
                .padding(.top, 22)
            Text(song.info.artist).font(.headline).padding(.top, 4)
            Text(song.info.album).foregroundStyle(.secondary).padding(.top, 5)
            Text(metadata(song.info))
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
                .padding(.top, 8)
            if let releaseDate = song.releaseDate {
                Text("Released \(releaseDate)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            }

            Spacer(minLength: 14)
            HStack(spacing: 12) {
                Button {
                    audition.toggle(side, in: swap, authorize: authorize)
                } label: {
                    Label("\(action) \(side.label)", systemImage: playing ? "pause.fill" : "play.fill")
                }
                .buttonStyle(.bordered)
                .keyboardShortcut(shortcut, modifiers: [])
                .help("\(action) the \(side.label.lowercased()) version (\(String(shortcut.character)))")
                .disabled(audition.isLoading)
                if let url = song.appleMusicURL {
                    Link(destination: url) {
                        Label("Apple Music", systemImage: "arrow.up.right")
                            .labelStyle(.iconOnly)
                    }
                    .help("Open this edition in Apple Music")
                }
            }
            .font(.callout)
            if replacement && swap.alreadyInLibrary {
                Label("Already in your library", systemImage: "checkmark")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, minHeight: 216, maxHeight: .infinity, alignment: .topLeading)
        .background(replacement ? Color.accentColor.opacity(0.055) : .clear)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(heading)
    }

    private func metadata(_ song: SongInfo) -> String {
        "\(playbackTimeLabel(Double(song.milliseconds) / 1000))  ·  Disc \(song.disc)  ·  Track \(song.track)"
    }
}

private struct AuditionScrubber: View {
    let audition: TrackAudition
    let side: TrackAudition.Side
    let duration: TimeInterval
    @State private var draftPosition: TimeInterval?

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.25)) { _ in
            let current = audition.player.playbackTime
            let position = draftPosition ?? (current.isFinite ? min(max(0, current), duration) : 0)
            HStack(spacing: 12) {
                Text(side.label)
                    .font(.callout.weight(.semibold))
                Text(playbackTimeLabel(position))
                    .accessibilityHidden(true)
                Slider(
                    value: Binding(
                        get: { position },
                        set: { value in
                            if draftPosition == nil { audition.seek(to: value, duration: duration) }
                            else { draftPosition = value }
                        }
                    ),
                    in: 0...max(1, duration),
                    onEditingChanged: { editing in
                        if editing {
                            draftPosition = position
                        } else if let draftPosition {
                            audition.seek(to: draftPosition, duration: duration)
                            self.draftPosition = nil
                        }
                    }
                )
                .accessibilityLabel("\(side.label) playback position")
                .accessibilityValue(playbackTimeLabel(position))
                Text(playbackTimeLabel(duration))
                    .accessibilityHidden(true)
            }
            .font(.callout.monospacedDigit())
            .foregroundStyle(.secondary)
            .padding(.horizontal, 4)
        }
    }
}

func playbackTimeLabel(_ interval: TimeInterval) -> String {
    let seconds = Int(max(0, interval))
    return String(format: "%d:%02d", seconds / 60, seconds % 60)
}

extension SongReference {
    var appleMusicURL: URL? {
        guard let url, url.scheme == "https", url.host == "music.apple.com" else { return nil }
        return url
    }
}
