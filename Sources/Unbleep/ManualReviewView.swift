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
            VStack(alignment: .leading, spacing: 5) {
                Text("Choose an explicit version")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                Text("Compare an edition with your clean copy, then queue it if it sounds right.")
                    .foregroundStyle(.secondary)
            }
            ForEach(items, id: \.localID) { item in
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.song.title).fontWeight(.semibold)
                    Text(item.song.artist).foregroundStyle(.secondary)
                    ForEach(item.candidates.filter { isCatalogID($0.id) }, id: \.id) { candidate in
                        Divider().padding(.top, 6)
                        editionRow(candidate, for: item)
                    }
                }
            }
        }
        .padding(16)
        .background(Color.primary.opacity(0.045), in: .rect(cornerRadius: 12))
        .sheet(item: $comparison) { comparison in
            ManualTrackComparison(swap: comparison.swap, model: model)
        }
    }

    private func editionRow(_ candidate: SongReference, for item: Unmatched) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(candidate.info.album)
                Text(editionDetails(candidate, among: item.candidates))
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let url = candidate.appleMusicURL {
                Link(destination: url) {
                    Label("View in Apple Music", systemImage: "arrow.up.right")
                        .labelStyle(.iconOnly)
                }
                .help("View this edition in Apple Music")
            }
            Button("Compare") {
                Task {
                    if let swap = await model.compareManualEdition(item, candidateID: candidate.id) {
                        comparison = Comparison(swap: swap)
                    }
                }
            }
            .help("Compare this edition with the clean copy")
            .disabled(model.isWorking)
        }
        .padding(.vertical, 5)
    }

    private func editionDetails(_ candidate: SongReference, among candidates: [SongReference]) -> String {
        func details(_ edition: SongReference) -> [String] {
            [edition.releaseDate, playbackTimeLabel(Double(edition.info.milliseconds) / 1_000),
             "Disc \(edition.info.disc), track \(edition.info.track)"].compactMap { $0 }
        }
        var parts = details(candidate)
        if candidates.contains(where: {
            $0.id != candidate.id && $0.info.album == candidate.info.album && details($0) == parts
        }) {
            parts.append("Catalog ID \(candidate.id)")
        }
        return parts.joined(separator: " · ")
    }
}

private struct ManualTrackComparison: View {
    let swap: Swap
    let model: MusicReviewModel
    @Environment(\.dismiss) private var dismiss
    @State private var audition = TrackAudition()
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Compare versions")
                .font(.title2.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
            TrackComparisonView(swap: swap, audition: audition, authorize: model.authorizePlayback)
            if let errorMessage {
                Text(errorMessage).foregroundStyle(.secondary)
            }
            HStack {
                Text("Apply this choice from the review screen.")
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button(swap.protectedBy.isEmpty ? "Queue Swap" : "Queue Addition") {
                    do {
                        try model.queueManualSwap(swap)
                        dismiss()
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(minWidth: 640, idealWidth: 720)
        .onDisappear { audition.stop() }
    }
}

struct UnmatchedTracks: View {
    let items: [Unmatched]
    let storefront: String

    var body: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 0) {
                Text("Unbleep will keep these clean copies. You can look for another release in Apple Music.")
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 8)
                ForEach(items, id: \.localID) { item in
                    Divider()
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(item.song.title) — \(item.song.artist)").fontWeight(.medium)
                            Text(item.reason).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if let edition = item.candidates.first?.appleMusicURL {
                            Link("View Explicit Version", destination: edition).fixedSize()
                        } else if let search = searchURL(for: item.song) {
                            Link("Search Apple Music", destination: search).fixedSize()
                        }
                    }
                    .padding(.vertical, 10)
                }
            }
            .padding(.top, 10)
        } label: {
            Text("\(items.count) without a verified swap")
                .font(.headline)
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
