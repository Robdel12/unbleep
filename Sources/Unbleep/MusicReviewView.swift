import SwiftUI

struct MusicReviewView: View {
    let model: MusicReviewModel
    @State private var showingSetup = false
    @State private var audition = TrackAudition()

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color.night.ignoresSafeArea())
            .overlay(alignment: .topTrailing) {
                // Sits in the hidden title bar, level with the traffic lights.
                HStack(spacing: 2) {
                    if let queue = model.queue, queue.current == nil {
                        ReviewOptionsMenu(queue: queue, model: model)
                    }
                    setupButton
                }
                .frame(height: titleBarHeight)
                .padding(.trailing, 14)
                .ignoresSafeArea(edges: .top)
            }
            .foregroundStyle(.white)
            .tint(.signal)
            .preferredColorScheme(.dark)
            .onChange(of: model.queue?.current?.localID) { audition.stop() }
            .onDisappear { audition.stop() }
            .sheet(isPresented: $showingSetup) {
                MusicKitSetupView(setup: model.setup, save: model.saveSetup)
            }
            .alert("Remove clean copies?", isPresented: Binding(
                get: { model.removalPlan != nil },
                set: { if !$0 { model.cancelRemoval() } }
            ), presenting: model.removalPlan) { plan in
                Button(plan.ready.count == 1 ? "Remove 1 Clean Copy" : "Remove \(plan.ready.count) Clean Copies", role: .destructive) {
                    Task { await model.remove(plan) }
                }
                Button("Cancel", role: .cancel) { model.cancelRemoval() }
            } message: { _ in
                Text("The explicit versions are in your library. Removing the clean copies also removes them from your other devices and can erase their play history.")
            }
    }

    @ViewBuilder
    private var content: some View {
        if let queue = model.queue {
            if let swap = queue.current {
                ReviewScreen(queue: queue, swap: swap, model: model, audition: audition)
            } else {
                ScrollView {
                    ReviewFinishView(queue: queue, model: model)
                        .padding(.horizontal, 40)
                        .padding(.top, 20)
                        .padding(.bottom, 32)
                        .frame(maxWidth: 760, alignment: .leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollIndicators(.never)
            }
        } else {
            IntroScreen(model: model)
        }
    }

    private var setupButton: some View {
        Button { showingSetup = true } label: {
            Image(systemName: "gearshape")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.45))
                .frame(width: 28, height: 28)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .help("MusicKit Setup")
        .accessibilityLabel("MusicKit Setup")
        .disabled(model.isWorking)
    }
}

/// The height of the hidden title bar, where the traffic lights sit.
private let titleBarHeight: CGFloat = 32

// MARK: - Intro

private struct IntroScreen: View {
    let model: MusicReviewModel
    @State private var peeled = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer(minLength: 32)
            headline
            Text("Apple Music quietly swaps clean edits into your library. Unbleep finds them, plays both versions side by side, and brings back the explicit ones you pick.")
                .font(.system(size: 15))
                .foregroundStyle(.white.opacity(0.62))
                .lineSpacing(3)
                .frame(maxWidth: 430, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 22)
            HStack(spacing: 16) {
                Button("Scan Library") { Task { await model.scan() } }
                    .buttonStyle(.signal)
                    .keyboardShortcut(.defaultAction)
                    .disabled(model.isWorking)
                ActivityLine(activity: model.activity)
            }
            .padding(.top, 28)
            Spacer(minLength: 32)
        }
        .padding(.horizontal, 48)
        .onAppear {
            if reduceMotion { peeled = true; return }
            withAnimation(.spring(duration: 0.9, bounce: 0.25).delay(0.35)) { peeled = true }
        }
    }

    /// The headline starts taped over, then the tape peels up to the corner, the way it does on the icon.
    private var headline: some View {
        VStack(alignment: .leading, spacing: -16) {
            Text("Put the")
            Text("explicit")
            Text("back.")
        }
        .font(.poster(76))
        .foregroundStyle(.white)
        .overlay(alignment: .topLeading) {
            // Starts across "explicit", then peels up and off to the corner, the way it does on the icon.
            CensorTape(seed: 3)
                .frame(width: 236, height: 46)
                .rotationEffect(.degrees(peeled ? -14 : -1.5), anchor: .topLeading)
                .offset(x: peeled ? -28 : -10, y: peeled ? -34 : 92)
        }
            .accessibilityAddTraits(.isHeader)
            .accessibilityLabel("Put the explicit back.")
    }
}

// MARK: - Review

private struct ReviewScreen: View {
    let queue: ReviewQueue
    let swap: Swap
    let model: MusicReviewModel
    let audition: TrackAudition

    var body: some View {
        VStack(spacing: 0) {
            progress
                .frame(height: titleBarHeight)
                .padding(.leading, 84)
                .padding(.trailing, 40)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    TrackComparisonView(swap: swap, audition: audition, authorize: model.authorizePlayback)
                        .id(swap.localID)
                        .transition(.asymmetric(
                            insertion: .move(edge: .trailing).combined(with: .opacity),
                            removal: .opacity
                        ))
                    ActivityLine(activity: model.activity)
                }
                .padding(.horizontal, 40)
                .padding(.top, 14)
                .padding(.bottom, 28)
                .frame(maxWidth: 900, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.never)
            .defaultScrollAnchor(.top)
            footer
        }
        .ignoresSafeArea(edges: .top)
        .animation(.snappy(duration: 0.3), value: swap.localID)
    }

    private var progress: some View {
        let total = max(1, queue.review.swaps.count)
        let done = Double(queue.decisions.count) / Double(total)
        return HStack(spacing: 14) {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.08))
                    Capsule().fill(Color.signal)
                        .frame(width: max(4, proxy.size.width * done))
                }
            }
            .frame(height: 3)
            .accessibilityElement()
            .accessibilityLabel("Tracks reviewed")
            .accessibilityValue("\(queue.decisions.count) of \(total)")
            Text("\(queue.decisions.count + 1) of \(total)")
                .font(.system(size: 12, weight: .medium).monospacedDigit())
                .foregroundStyle(.white.opacity(0.5))
                .fixedSize()
        }
        .padding(.trailing, 44)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            if queue.canUndo {
                Button { model.undo() } label: {
                    Label("Undo", systemImage: "arrow.uturn.backward")
                }
                .buttonStyle(.quiet)
                .keyboardShortcut("z", modifiers: .command)
                .help("Undo last decision (⌘Z)")
            }
            Spacer()
            Button { model.decide(.skip) } label: {
                HStack(spacing: 8) { Text("Skip"); KeyHint(key: "S") }
            }
            .buttonStyle(.quiet)
            .keyboardShortcut("s", modifiers: [])
            .accessibilityLabel("Skip")
            .help("Keep the clean version and move on (S)")
            Button { model.decide(.approve) } label: {
                HStack(spacing: 8) {
                    Text(swap.protectedBy.isEmpty ? "Swap" : "Add Explicit")
                    Image(systemName: "return").font(.system(size: 11, weight: .bold)).opacity(0.6)
                }
            }
            .buttonStyle(.signal)
            .keyboardShortcut(.defaultAction)
            .help(swap.protectedBy.isEmpty
                  ? "Replace the clean version with the explicit one (Return)"
                  : "Add the explicit version and keep the clean copy (Return)")
        }
        .disabled(model.isWorking)
        .padding(.horizontal, 40)
        .padding(.vertical, 16)
        .overlay(alignment: .top) { Rectangle().fill(Color.hairline).frame(height: 1) }
    }
}

// MARK: - Activity

/// One quiet line describing what Unbleep is doing, or what just went wrong.
struct ActivityLine: View {
    let activity: MusicReviewModel.Activity

    var body: some View {
        switch activity {
        case .idle, .confirmRemoval:
            EmptyView()
        case .working(let message):
            HStack(spacing: 9) {
                ProgressView().controlSize(.small)
                Text(message)
                    .contentTransition(.numericText())
            }
            .font(.system(size: 13))
            .foregroundStyle(.white.opacity(0.62))
            .animation(.default, value: message)
        case .message(let message):
            Label(message, systemImage: "exclamationmark.circle")
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.75))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

#if DEBUG
#Preview("Intro") {
    MusicReviewView(model: MusicReviewModel(preview: nil))
        .frame(width: 760, height: 480)
}

#Preview("Scanning") {
    MusicReviewView(model: MusicReviewModel(preview: nil, activity: .working("Compared 128 of 412 clean tracks…")))
        .frame(width: 760, height: 480)
}

#Preview("Review") {
    MusicReviewView(model: MusicReviewModel(preview: PreviewFixtures.queue(decided: 0)))
        .frame(width: 760, height: 480)
}

#Preview("Review, protected") {
    MusicReviewView(model: MusicReviewModel(preview: PreviewFixtures.queue(decided: 2)))
        .frame(width: 760, height: 480)
}

#Preview("Finished") {
    MusicReviewView(model: MusicReviewModel(preview: PreviewFixtures.finishedQueue))
        .frame(width: 760, height: 640)
}

#Preview("Cleaned up") {
    MusicReviewView(model: MusicReviewModel(preview: PreviewFixtures.cleanedUpQueue))
        .frame(width: 760, height: 640)
}

#Preview("No matches") {
    MusicReviewView(model: MusicReviewModel(preview: PreviewFixtures.emptyQueue))
        .frame(width: 760, height: 480)
}
#endif
