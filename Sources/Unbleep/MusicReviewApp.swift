import SwiftUI

#if !SWIFT_PACKAGE
@main
#endif
struct MusicReviewApp: App {
    @State private var model: MusicReviewModel

    init() {
        let arguments = CommandLine.arguments.dropFirst()
        let url = arguments.first == "--gui"
            ? arguments.dropFirst().first.flatMap { $0.hasPrefix("-") ? nil : URL(fileURLWithPath: $0) }
            : nil
        _model = State(initialValue: MusicReviewModel(opening: url))
    }

    var body: some Scene {
        Window("Unbleep", id: "review") {
            MusicReviewView(model: model)
                .frame(minWidth: 620, minHeight: 400)
        }
        .defaultSize(width: 760, height: 450)
        .windowResizability(.contentMinSize)
    }
}
