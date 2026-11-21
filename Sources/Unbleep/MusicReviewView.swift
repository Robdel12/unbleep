import SwiftUI

struct MusicReviewView: View {
    let model: MusicReviewModel
    @State private var showingSetup = false
    @State private var audition = TrackAudition()

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let queue = model.queue {
                        if let swap = queue.current {
                            progress(queue)
                            TrackComparisonView(swap: swap, audition: audition, authorize: model.authorizePlayback)
                                .id(swap.localID)
                            ReviewActivityStatus(activity: model.activity)
                        } else {
                            ReviewFinishView(queue: queue, model: model)
                        }
                    } else {
                        intro
                        ReviewActivityStatus(activity: model.activity)
                    }
                }
                .frame(maxWidth: 900)
                .padding(24)
                .frame(maxWidth: .infinity)
            }
            .defaultScrollAnchor(.top)
            if let queue = model.queue, let swap = queue.current {
                Divider()
                footer(queue, swap: swap)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 14)
            }
        }
        .onChange(of: model.queue?.current?.localID) { audition.stop() }
        .onDisappear { audition.stop() }
        .toolbar {
            ToolbarItem {
                Button { showingSetup = true } label: {
                    Label("MusicKit Setup", systemImage: "gearshape")
                }
                .help("MusicKit Setup")
                .disabled(model.isWorking)
            }
        }
        .sheet(isPresented: $showingSetup) {
            MusicKitSetupView(setup: model.setup, save: model.saveSetup)
        }
        .alert("Remove clean tracks?", isPresented: Binding(
            get: { model.removalPlan != nil },
            set: { if !$0 { model.cancelRemoval() } }
        ), presenting: model.removalPlan) { plan in
            Button("Remove \(plan.ready.count) Clean Tracks", role: .destructive) {
                Task { await model.remove(plan) }
            }
            Button("Cancel", role: .cancel) { model.cancelRemoval() }
        } message: { plan in
            Text("The explicit versions are in your library. Removing the clean copies also removes them from synced devices and can erase their play history.")
        }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Review clean tracks")
                .font(.system(size: 28, weight: .semibold))
                .tracking(-0.75)
            Text("Scan your Music library to compare each clean track with its explicit match.")
                .foregroundStyle(.secondary)
            Button("Scan Library") { Task { await model.scan() } }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .controlSize(.large)
                .padding(.top, 8)
                .disabled(model.isWorking)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func progress(_ queue: ReviewQueue) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Review queue")
                    .font(.system(size: 28, weight: .semibold))
                    .tracking(-0.75)
                Spacer()
                Text("\(queue.decisions.count + 1) of \(queue.review.swaps.count)")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: Double(queue.decisions.count), total: Double(queue.review.swaps.count))
                .accessibilityLabel("Tracks reviewed")
        }
    }

    private func footer(_ queue: ReviewQueue, swap: Swap) -> some View {
        HStack(spacing: 10) {
            if queue.canUndo {
                Button("Undo Last", systemImage: "arrow.uturn.backward") { model.undo() }
                    .keyboardShortcut("z", modifiers: .command)
                    .help("Undo last decision (⌘Z)")
            }
            Spacer()
            Button("Skip  S") { model.decide(.skip) }
                .keyboardShortcut("s", modifiers: [])
                .accessibilityLabel("Skip")
                .help("Skip this track (S)")
            Button(swap.protectedBy.isEmpty ? "Queue Swap  ↵" : "Queue Addition  ↵") {
                model.decide(.approve)
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .help("Save this approval and advance (Return)")
        }
        .controlSize(.large)
        .disabled(model.isWorking)
    }
}

struct ReviewActivityStatus: View {
    let activity: MusicReviewModel.Activity

    var body: some View {
        switch activity {
        case .idle, .confirmRemoval:
            EmptyView()
        case .working(let message):
            HStack(spacing: 9) {
                ProgressView().controlSize(.small)
                Text(message).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .message(let message):
            Text(message)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
    }
}
