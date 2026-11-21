import MusicKit
import SwiftUI

struct TrackComparisonView: View {
    let swap: Swap
    let audition: TrackAudition
    let authorize: @MainActor () async throws -> Void
    @ObservedObject private var playback = ApplicationMusicPlayer.shared.state

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(swap.clean.info.title)
                .font(.poster(54))
                .lineLimit(2)
                .minimumScaleFactor(0.6)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text(swap.clean.info.artist)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white.opacity(0.62))
                .padding(.top, 2)

            HStack(alignment: .top, spacing: 14) {
                tile(.clean, shortcut: "1")
                tile(.explicit, shortcut: "2")
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 26)

            auditionStatus
                .padding(.top, 14)

            if !swap.protectedBy.isEmpty {
                protectedNote.padding(.top, 14)
            }
        }
    }

    // MARK: Tiles

    private func tile(_ side: TrackAudition.Side, shortcut: KeyEquivalent) -> some View {
        let song = side.song(in: swap)
        let explicit = side == .explicit
        let active = audition.activeSide == side || isLoading(side)
        let playing = audition.activeSide == side && playback.playbackStatus == .playing
        let ink: Color = explicit ? .signal : .tape

        return Button {
            audition.toggle(side, in: swap, authorize: authorize)
        } label: {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 8) {
                    if explicit {
                        ExplicitBadge()
                    } else {
                        Image(systemName: "speaker.slash.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Color.tape)
                    }
                    Text(side.label)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(ink)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    if explicit && swap.alreadyInLibrary {
                        Label("In library", systemImage: "checkmark")
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.5))
                            .lineLimit(1)
                            .help("This explicit version is already in your library")
                    }
                    KeyHint(key: String(shortcut.character))
                }

                HStack(alignment: .center, spacing: 14) {
                    playGlyph(side, playing: playing, ink: ink)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(song.info.album)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white.opacity(explicit ? 1 : 0.8))
                            .lineLimit(1)
                        HStack(spacing: 10) {
                            Text(playbackTimeLabel(Double(song.info.milliseconds) / 1000))
                            if let year = song.releaseDate?.prefix(4), year.count == 4 {
                                Text(year)
                            }
                        }
                        .font(.system(size: 13).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.5))
                        .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(tileBackground(explicit: explicit, active: active))
            .overlay(alignment: .topTrailing) {
                if !explicit {
                    CensorTape(seed: 5)
                        .frame(width: 74, height: 16)
                        .rotationEffect(.degrees(32))
                        .offset(x: 18, y: -2)
                        .allowsHitTesting(false)
                }
            }
            .clipShape(.rect(cornerRadius: 16))
            .contentShape(.rect(cornerRadius: 16))
        }
        .buttonStyle(TileButtonStyle())
        .keyboardShortcut(shortcut, modifiers: [])
        .disabled(audition.isLoading)
        .help("\(playing ? "Pause" : "Play") the \(side.label.lowercased()) version (\(String(shortcut.character)))")
        .accessibilityLabel("\(playing ? "Pause" : "Play") \(side.label.lowercased()) version, \(song.info.album)")
        .contextMenu {
            if let url = song.appleMusicURL {
                Link("Open in Apple Music", destination: url)
            }
        }
    }

    private func playGlyph(_ side: TrackAudition.Side, playing: Bool, ink: Color) -> some View {
        ZStack {
            Circle().fill(ink.opacity(side == .explicit ? 1 : 0.22))
            if isLoading(side) {
                ProgressView().controlSize(.small)
            } else {
                Image(systemName: playing ? "pause.fill" : "play.fill")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(side == .explicit ? Color.night : .white)
                    .offset(x: playing ? 0 : 1.5)
                    .contentTransition(.symbolEffect(.replace))
            }
        }
        .frame(width: 42, height: 42)
    }

    @ViewBuilder
    private func tileBackground(explicit: Bool, active: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: 16)
        if explicit {
            shape.fill(
                LinearGradient(colors: [Color.signal.opacity(0.16), Color.signal.opacity(0.05)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
            )
            .overlay { shape.strokeBorder(Color.signal.opacity(active ? 0.9 : 0.35), lineWidth: active ? 1.5 : 1) }
        } else {
            shape.fill(Color.panel)
                .overlay { shape.strokeBorder(Color.tape.opacity(active ? 0.8 : 0.18), lineWidth: active ? 1.5 : 1) }
        }
    }

    private func isLoading(_ side: TrackAudition.Side) -> Bool {
        if case .loading(let loading) = audition.state { return loading == side }
        return false
    }

    // MARK: Status

    @ViewBuilder
    private var auditionStatus: some View {
        switch audition.state {
        case .idle, .loading:
            EmptyView()
        case .ready(let side):
            AuditionScrubber(audition: audition, side: side, duration: Double(side.song(in: swap).info.milliseconds) / 1000)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.circle")
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.7))
        }
    }

    private var protectedNote: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "lock.fill")
                .font(.system(size: 11))
                .foregroundStyle(Color.tape)
            Text("The clean copy stays too. ")
                .foregroundStyle(.white.opacity(0.8))
            + Text(swap.protectedBy.joined(separator: ", "))
                .foregroundStyle(.white.opacity(0.5))
        }
        .font(.system(size: 13))
    }
}

private struct TileButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.snappy(duration: 0.15), value: configuration.isPressed)
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
                .controlSize(.small)
                .tint(side == .explicit ? .signal : .tape)
                .accessibilityLabel("\(side.label) playback position")
                .accessibilityValue(playbackTimeLabel(position))
                Text(playbackTimeLabel(duration))
                    .accessibilityHidden(true)
            }
            .font(.system(size: 12).monospacedDigit())
            .foregroundStyle(.white.opacity(0.5))
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

#if DEBUG
#Preview("Comparison") {
    TrackComparisonView(swap: PreviewFixtures.swaps[0], audition: TrackAudition(), authorize: {})
        .padding(40)
        .frame(width: 760)
        .background(Color.night)
        .foregroundStyle(.white)
        .preferredColorScheme(.dark)
}

#Preview("Comparison, protected") {
    TrackComparisonView(swap: PreviewFixtures.swaps[2], audition: TrackAudition(), authorize: {})
        .padding(40)
        .frame(width: 760)
        .background(Color.night)
        .foregroundStyle(.white)
        .preferredColorScheme(.dark)
}
#endif
