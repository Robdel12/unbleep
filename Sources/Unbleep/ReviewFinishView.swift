import SwiftUI

struct ReviewFinishView: View {
    let queue: ReviewQueue
    let model: MusicReviewModel
    let openReview: () -> Void

    var body: some View {
        let unmatched = queue.unmatched
        VStack(alignment: .leading, spacing: 22) {
            header
            if let action = queue.nextApplicationAction {
                nextStep(action)
            } else {
                ReviewActivityStatus(activity: model.activity)
            }
            let choices = unmatched.filter(\.canChooseEdition)
            if !choices.isEmpty {
                ManualEditionChoices(items: choices, model: model)
            }
            if let summary = queue.application?.cleanupSummary {
                cleanupResults(summary)
            }
            let kept = unmatched.filter { !$0.canChooseEdition }
            if !kept.isEmpty {
                UnmatchedTracks(items: kept, storefront: queue.review.storefront)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var header: some View {
        let approvedCount = queue.approvedSwaps.count
        return HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(approvedCount == 0 && queue.review.swaps.isEmpty ? "No automatic matches" : "Review complete")
                    .font(.system(size: 28, weight: .semibold))
                    .tracking(-0.75)
                    .accessibilityAddTraits(.isHeader)
                if approvedCount > 0 || queue.skippedCount > 0 {
                    let approved = "\(approvedCount) approved"
                    Text(queue.skippedCount > 0 ? "\(approved) · \(queue.skippedCount) skipped" : approved)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Menu {
                if queue.canUndo {
                    Button("Undo Last Decision", action: model.undo)
                        .keyboardShortcut("z", modifiers: .command)
                }
                if queue.application?.cleanupSummary != nil && queue.nextApplicationAction == nil {
                    Button("Check Sync Again") { Task { await model.checkRemoval() } }
                }
                Button("Scan Again") { Task { await model.scan() } }
                Button("Open Review…", action: openReview)
            } label: {
                Label("Review Options", systemImage: "ellipsis.circle")
                    .labelStyle(.iconOnly)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .disabled(model.isWorking)
        }
    }

    private func nextStep(_ action: ReviewQueue.ApplicationAction) -> some View {
        let step = applicationStep(action)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 24) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(step.title).font(.headline)
                    Text(step.detail)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Button(step.button) {
                    Task { await step.run() }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .fixedSize()
                .disabled(model.isWorking)
            }
            ReviewActivityStatus(activity: model.activity)
        }
        .padding(16)
        .background(Color.accentColor.opacity(0.075), in: .rect(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12).strokeBorder(Color.accentColor.opacity(0.18))
        }
    }

    private func applicationStep(_ action: ReviewQueue.ApplicationAction)
        -> (title: String, detail: String, button: String, run: @MainActor () async -> Void) {
        switch action {
        case .addApproved:
            return ("Add the explicit versions",
                    "Your approvals are saved. Add the explicit copies before reviewing clean copies for removal.",
                    "Add Approved Versions", model.addApproved)
        case .addMissing:
            return ("Some explicit versions are missing",
                    "Retry the missing additions before removing their clean copies.",
                    "Add Missing Versions", model.addApproved)
        case .checkSync:
            return ("Check which versions have synced", syncDetail, "Check Sync", model.checkRemoval)
        }
    }

    private var syncDetail: String {
        guard case .additions(let submitted, let unverified, _) = queue.application else {
            return "Check which explicit copies are in Music and review the clean copies you can remove."
        }
        if submitted > 0 {
            let additions = submitted == 1 ? "one addition" : "\(submitted) additions"
            return "Apple Music accepted \(additions). Check which clean copies are ready to remove."
        }
        if unverified == 0 {
            return "The explicit versions are in your synced library. Check which clean copies are ready to remove on this Mac."
        }
        return "Check which explicit copies are in Music and review the clean copies you can remove."
    }

    private func cleanupResults(_ summary: CleanupSummary) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Clean copy results")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            Text(resultsLine(summary))
                .monospacedDigit()
                .foregroundStyle(.secondary)
            if !summary.kept.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(summary.kept) { item in
                        Divider()
                        VStack(alignment: .leading, spacing: 3) {
                            Text("\(item.song.title) — \(item.song.artist)").fontWeight(.medium)
                            Text(item.reason.description).foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 9)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.primary.opacity(0.045), in: .rect(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12).strokeBorder(Color.primary.opacity(0.09))
        }
    }

    private func resultsLine(_ summary: CleanupSummary) -> String {
        [
            summary.removedIDs.isEmpty ? nil : "\(summary.removedIDs.count) removed",
            summary.absentIDs.isEmpty ? nil : "\(summary.absentIDs.count) already absent",
            summary.preservedCount == 0 ? nil : "\(summary.preservedCount) kept",
            summary.needsAttentionCount == 0 ? nil : "\(summary.needsAttentionCount) need attention",
        ].compactMap { $0 }.joined(separator: " · ")
    }
}
