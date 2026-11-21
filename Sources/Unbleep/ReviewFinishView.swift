import SwiftUI

struct ReviewFinishView: View {
    let queue: ReviewQueue
    let model: MusicReviewModel

    var body: some View {
        let unmatched = queue.unmatched
        let choices = unmatched.filter(\.canChooseEdition)
        let kept = unmatched.filter { !$0.canChooseEdition }
        VStack(alignment: .leading, spacing: 36) {
            header
            if !queue.approvedSwaps.isEmpty {
                StepTrack(current: stepIndex)
                if let action = queue.nextApplicationAction {
                    nextStep(action)
                } else {
                    ActivityLine(activity: model.activity)
                }
            } else {
                HStack(spacing: 16) {
                    Button("Scan Again") { Task { await model.scan() } }
                        .buttonStyle(.quiet)
                        .disabled(model.isWorking)
                    ActivityLine(activity: model.activity)
                }
            }
            if !choices.isEmpty {
                ManualEditionChoices(items: choices, model: model)
            }
            if let summary = queue.application?.cleanupSummary {
                cleanupResults(summary)
            }
            if !kept.isEmpty {
                UnmatchedTracks(items: kept, storefront: queue.review.storefront)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text(headline)
                    .font(.poster(52))
                    .accessibilityAddTraits(.isHeader)
                Text(subheadline)
                    .font(.system(size: 15))
                    .foregroundStyle(.white.opacity(0.62))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
    }

    private var headline: String {
        if queue.review.swaps.isEmpty && queue.approvedSwaps.isEmpty { return "Nothing to swap" }
        if queue.approvedSwaps.isEmpty { return "All skipped" }
        if queue.nextApplicationAction == nil { return "All set" }
        return "Review done"
    }

    private var subheadline: String {
        let approved = queue.approvedSwaps.count
        let skipped = queue.skippedCount
        if queue.review.swaps.isEmpty && approved == 0 {
            return "Unbleep didn’t find a clean track with a verified explicit match."
        }
        if approved == 0 {
            return skipped == 1 ? "You kept the clean version of 1 track." : "You kept the clean versions of all \(skipped) tracks."
        }
        let tail = skipped > 0 ? ", \(skipped) skipped." : "."
        if queue.nextApplicationAction == nil {
            return "\(approved) swapped\(tail) Your library is up to date."
        }
        let swaps = approved == 1 ? "1 track to swap" : "\(approved) tracks to swap"
        return "\(swaps)\(tail) Nothing in your library has changed yet."
    }

    // MARK: Next step

    private var stepIndex: Int {
        switch queue.nextApplicationAction {
        case .addApproved, .addMissing: 0
        case .checkSync: 1
        case nil: 3
        }
    }

    private func nextStep(_ action: ReviewQueue.ApplicationAction) -> some View {
        let step = applicationStep(action)
        return VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text(step.title)
                    .font(.system(size: 17, weight: .semibold))
                Text(step.detail)
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.62))
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 16) {
                Button(step.button) { Task { await step.run() } }
                    .buttonStyle(.signal)
                    .keyboardShortcut(.defaultAction)
                    .disabled(model.isWorking)
                ActivityLine(activity: model.activity)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.panel, in: .rect(cornerRadius: 18))
    }

    private func applicationStep(_ action: ReviewQueue.ApplicationAction)
        -> (title: String, detail: String, button: String, run: @MainActor () async -> Void) {
        switch action {
        case .addApproved:
            return ("Add the explicit versions",
                    "Unbleep adds them to your Apple Music library. Your clean copies stay put until you check sync.",
                    "Add Explicit Versions", model.addApproved)
        case .addMissing:
            return ("Some explicit versions didn’t arrive",
                    "Add them again before removing their clean copies.",
                    "Add Missing Versions", model.addApproved)
        case .checkSync:
            return ("Check sync", syncDetail, "Check Sync", model.checkRemoval)
        }
    }

    private var syncDetail: String {
        guard case .additions(let submitted, let unverified, _) = queue.application else {
            return "Unbleep checks which explicit versions reached this Mac, then asks before removing any clean copies."
        }
        if submitted > 0 {
            let additions = submitted == 1 ? "1 explicit version" : "\(submitted) explicit versions"
            return "Apple Music accepted \(additions). Once they sync to this Mac, Unbleep asks before removing the clean copies."
        }
        if unverified == 0 {
            return "The explicit versions are already in your library. Unbleep asks before removing the clean copies."
        }
        return "Unbleep checks which explicit versions reached this Mac, then asks before removing any clean copies."
    }

    // MARK: Results

    private func cleanupResults(_ summary: CleanupSummary) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeading(title: "Clean copies", detail: resultsLine(summary))
            ForEach(summary.kept) { item in
                TrackRow(title: item.song.title, artist: item.song.artist, note: item.reason.description)
            }
        }
    }

    private func resultsLine(_ summary: CleanupSummary) -> String {
        [
            summary.removedIDs.isEmpty ? nil : "\(summary.removedIDs.count) removed",
            summary.absentIDs.isEmpty ? nil : "\(summary.absentIDs.count) already gone",
            summary.preservedCount == 0 ? nil : "\(summary.preservedCount) kept",
            summary.needsAttentionCount == 0 ? nil : "\(summary.needsAttentionCount) need attention",
        ].compactMap { $0 }.joined(separator: ", ")
    }
}

/// Undo, re-check, or rescan once the review is done.
struct ReviewOptionsMenu: View {
    let queue: ReviewQueue
    let model: MusicReviewModel

    var body: some View {
        Menu {
            if queue.canUndo {
                Button("Undo Last Decision", action: model.undo)
                    .keyboardShortcut("z", modifiers: .command)
            }
            if queue.application?.cleanupSummary != nil && queue.nextApplicationAction == nil {
                Button("Check Sync Again") { Task { await model.checkRemoval() } }
            }
            Button("Scan Again") { Task { await model.scan() } }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.45))
                .frame(width: 28, height: 28)
                .contentShape(.rect)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Review options")
        .accessibilityLabel("Review options")
        .disabled(model.isWorking)
    }
}

/// The three things that happen after review, in order. Done steps are filled, the current one is lit.
private struct StepTrack: View {
    let current: Int
    private let steps = ["Add explicit versions", "Check sync", "Remove clean copies"]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(steps.indices, id: \.self) { index in
                HStack(spacing: 8) {
                    marker(index)
                    Text(steps[index])
                        .font(.system(size: 13, weight: index == current ? .semibold : .regular))
                        .foregroundStyle(.white.opacity(index == current ? 1 : index < current ? 0.62 : 0.38))
                        .lineLimit(1)
                }
                if index < steps.count - 1 {
                    Rectangle()
                        .fill(index < current ? Color.signal.opacity(0.6) : Color.hairline)
                        .frame(height: 1)
                        .frame(minWidth: 12, maxWidth: 48)
                        .padding(.horizontal, 10)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(current < steps.count ? "Next: \(steps[current])" : "All steps done")
    }

    @ViewBuilder
    private func marker(_ index: Int) -> some View {
        if index < current {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 15))
                .foregroundStyle(Color.signal)
        } else {
            Text("\(index + 1)")
                .font(.system(size: 11, weight: .bold).monospacedDigit())
                .foregroundStyle(index == current ? Color.night : .white.opacity(0.4))
                .frame(width: 18, height: 18)
                .background(Circle().fill(index == current ? Color.signal : .clear))
                .overlay { Circle().strokeBorder(.white.opacity(index == current ? 0 : 0.2)) }
        }
    }
}

/// A small heading over a list, with an optional count or summary beside it.
struct SectionHeading: View {
    let title: String
    var detail: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 17, weight: .semibold))
                .accessibilityAddTraits(.isHeader)
            if let detail, !detail.isEmpty {
                Text(detail)
                    .font(.system(size: 13).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
        .padding(.bottom, 6)
    }
}

/// A song in a list: title, artist, and a line saying what happened to it.
struct TrackRow<Accessory: View>: View {
    let title: String
    let artist: String
    let note: String
    @ViewBuilder var accessory: Accessory

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                (Text(title).fontWeight(.semibold) + Text("  \(artist)").foregroundStyle(.white.opacity(0.5)))
                    .font(.system(size: 14))
                    .lineLimit(1)
                Text(note)
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.5))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            accessory
        }
        .padding(.vertical, 11)
        .overlay(alignment: .top) { Rectangle().fill(Color.hairline).frame(height: 1) }
    }
}

extension TrackRow where Accessory == EmptyView {
    init(title: String, artist: String, note: String) {
        self.init(title: title, artist: artist, note: note) { EmptyView() }
    }
}

#if DEBUG
#Preview("Finish, add step") {
    ScrollView {
        ReviewFinishView(queue: PreviewFixtures.finishedQueue, model: MusicReviewModel(preview: PreviewFixtures.finishedQueue))
            .padding(40)
    }
    .frame(width: 760, height: 720)
    .background(Color.night)
    .foregroundStyle(.white)
    .preferredColorScheme(.dark)
}

#Preview("Finish, cleaned up") {
    ScrollView {
        ReviewFinishView(queue: PreviewFixtures.cleanedUpQueue, model: MusicReviewModel(preview: PreviewFixtures.cleanedUpQueue))
            .padding(40)
    }
    .frame(width: 760, height: 720)
    .background(Color.night)
    .foregroundStyle(.white)
    .preferredColorScheme(.dark)
}
#endif
