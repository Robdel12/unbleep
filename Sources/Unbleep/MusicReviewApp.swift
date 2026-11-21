import SwiftUI

@main
struct MusicReviewApp: App {
    @State private var model = MusicReviewModel()

    var body: some Scene {
        Window("Unbleep", id: "review") {
            MusicReviewView(model: model)
                .frame(minWidth: 620, minHeight: 400)
        }
        .defaultSize(width: 760, height: 450)
        .windowResizability(.contentMinSize)
    }
}
