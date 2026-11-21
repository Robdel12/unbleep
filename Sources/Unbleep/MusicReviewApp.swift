import SwiftUI

@main
struct MusicReviewApp: App {
    @State private var model = MusicReviewModel()

    var body: some Scene {
        Window("Unbleep", id: "review") {
            MusicReviewView(model: model)
                .frame(minWidth: 640, minHeight: 440)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 760, height: 500)
        .windowResizability(.contentMinSize)
    }
}
