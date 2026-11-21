import SwiftUI
import UniformTypeIdentifiers

struct MusicKitSetupView: View {
    @Environment(\.dismiss) private var dismiss
    @State var setup: MusicKitSetup
    let save: (MusicKitSetup) -> Void
    @State private var choosingKey = false
    @State private var fileError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("MusicKit Setup").font(.title2.weight(.semibold))
            Text("MusicKit connects automatically when the app is signed for a MusicKit-enabled App ID. For an ad hoc build, choose your Media Services key here.")
                .foregroundStyle(.secondary)
            Form {
                TextField("Team ID", text: $setup.teamID)
                TextField("Key ID", text: $setup.keyID)
                LabeledContent("Private key") {
                    HStack {
                        if !setup.keyPath.isEmpty {
                            Text(URL(fileURLWithPath: setup.keyPath).lastPathComponent)
                                .lineLimit(1)
                                .foregroundStyle(.secondary)
                        }
                        Button("Choose .p8 File…") { choosingKey = true }
                    }
                }
            }
            if let fileError { Text(fileError).foregroundStyle(.red) }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save") {
                    save(setup)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!setup.isComplete)
            }
        }
        .padding(22)
        .frame(width: 450)
        .fileImporter(isPresented: $choosingKey, allowedContentTypes: [UTType(filenameExtension: "p8") ?? .data]) { result in
            switch result {
            case .success(let url):
                guard url.pathExtension.lowercased() == "p8" else {
                    fileError = "Choose a .p8 Media Services key."
                    return
                }
                fileError = nil
                setup.keyPath = url.path
                let filename = url.deletingPathExtension().lastPathComponent
                if filename.hasPrefix("AuthKey_") { setup.keyID = String(filename.dropFirst("AuthKey_".count)) }
            case .failure(let error):
                fileError = error.localizedDescription
            }
        }
    }
}
