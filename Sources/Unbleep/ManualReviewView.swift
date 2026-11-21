import SwiftUI

struct ManualEditionChoices: View {
    let items: [Unmatched]
    let model: MusicReviewModel
    @State private var comparison: Comparison?

    private struct Comparison: Identifiable {
        let swap: Swap
        var id: String { swap.localID }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeading(
                title: "Pick an edition",
                detail: "Apple Music has more than one explicit version of these. Compare one with your clean copy, then add it."
            )
            ForEach(items, id: \.localID) { item in
                VStack(alignment: .leading, spacing: 8) {
                    (Text(item.song.title).fontWeight(.semibold)
                     + Text("  \(item.song.artist)").foregroundStyle(.white.opacity(0.5)))
                        .font(.system(size: 14))
                    VStack(spacing: 0) {
                        ForEach(item.candidates.filter { isCatalogID($0.id) }, id: \.id) { candidate in
                            editionRow(candidate, for: item)
                        }
                    }
                    .background(Color.panel, in: .rect(cornerRadius: 14))
                }
            }
        }
        .sheet(item: $comparison) { comparison in
            ManualTrackComparison(swap: comparison.swap, model: model)
        }
    }

    private func editionRow(_ candidate: SongReference, for item: Unmatched) -> some View {
        HStack(spacing: 12) {
            ExplicitBadge(size: 14)
            VStack(alignment: .leading, spacing: 2) {
                Text(candidate.info.album)
                    .font(.system(size: 14, weight: .medium))
                Text(editionDetails(candidate, among: item.candidates))
                    .font(.system(size: 12).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.5))
            }
            Spacer()
            if let url = candidate.appleMusicURL {
                Link(destination: url) {
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.5))
                        .frame(width: 28, height: 28)
                }
                .help("Open this edition in Apple Music")
                .accessibilityLabel("Open in Apple Music")
            }
            Button("Compare") {
                Task {
                    if let swap = await model.compareManualEdition(item, candidateID: candidate.id) {
                        comparison = Comparison(swap: swap)
                    }
                }
            }
            .buttonStyle(.quiet)
            .help("Compare this edition with your clean copy")
            .disabled(model.isWorking)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func editionDetails(_ candidate: SongReference, among candidates: [SongReference]) -> String {
        func details(_ edition: SongReference) -> [String] {
            [edition.releaseDate.map { String($0.prefix(4)) },
             playbackTimeLabel(Double(edition.info.milliseconds) / 1_000),
             "Disc \(edition.info.disc), track \(edition.info.track)"].compactMap { $0 }
        }
        var parts = details(candidate)
        if candidates.contains(where: {
            $0.id != candidate.id && $0.info.album == candidate.info.album && details($0) == parts
        }) {
            parts.append("Catalog ID \(candidate.id)")
        }
        return parts.joined(separator: ", ")
    }
}

private struct ManualTrackComparison: View {
    let swap: Swap
    let model: MusicReviewModel
    @Environment(\.dismiss) private var dismiss
    @State private var audition = TrackAudition()
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            TrackComparisonView(swap: swap, audition: audition, authorize: model.authorizePlayback)
            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.circle")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.75))
            }
            HStack(spacing: 10) {
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(.quiet)
                    .keyboardShortcut(.cancelAction)
                Button(swap.protectedBy.isEmpty ? "Swap" : "Add Explicit") {
                    do {
                        try model.queueManualSwap(swap)
                        dismiss()
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                }
                .buttonStyle(.signal)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(32)
        .frame(minWidth: 640, idealWidth: 720)
        .background(Color.night)
        .foregroundStyle(.white)
        .tint(.signal)
        .preferredColorScheme(.dark)
        .onDisappear { audition.stop() }
    }
}

struct UnmatchedTracks: View {
    let items: [Unmatched]
    let storefront: String
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.snappy(duration: 0.25)) { expanded.toggle() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .bold))
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                        .foregroundStyle(.white.opacity(0.5))
                    Text(items.count == 1 ? "1 song stays clean" : "\(items.count) songs stay clean")
                        .font(.system(size: 17, weight: .semibold))
                    Spacer()
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityValue(expanded ? "Expanded" : "Collapsed")

            if expanded {
                Text("Unbleep couldn’t verify an explicit match for these. You can look for another release in Apple Music.")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.5))
                    .padding(.top, 6)
                    .padding(.bottom, 10)
                ForEach(items, id: \.localID) { item in
                    TrackRow(title: item.song.title, artist: item.song.artist, note: item.reason) {
                        if let edition = item.candidates.first?.appleMusicURL {
                            Link("View Explicit", destination: edition).fixedSize()
                        } else if let search = searchURL(for: item.song) {
                            Link("Search Apple Music", destination: search).fixedSize()
                        }
                    }
                    .font(.system(size: 13, weight: .medium))
                }
            }
        }
    }

    private func searchURL(for song: SongInfo) -> URL? {
        guard isStorefrontID(storefront) else { return nil }
        var search = URLComponents()
        search.scheme = "https"
        search.host = "music.apple.com"
        search.path = "/\(storefront)/search"
        search.queryItems = [URLQueryItem(name: "term", value: "\(song.title) \(song.artist)")]
        return search.url
    }
}

#if DEBUG
#Preview("Edition choices") {
    VStack(alignment: .leading, spacing: 36) {
        ManualEditionChoices(items: [PreviewFixtures.choosable], model: MusicReviewModel(preview: PreviewFixtures.finishedQueue))
        UnmatchedTracks(items: [PreviewFixtures.unmatched], storefront: "us")
    }
    .padding(40)
    .frame(width: 760)
    .background(Color.night)
    .foregroundStyle(.white)
    .tint(.signal)
    .preferredColorScheme(.dark)
}
#endif
