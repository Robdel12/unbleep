#if SWIFT_PACKAGE
import Darwin
import Foundation

@main
enum Unbleep {
    static let help = """
    Unbleep

    Run from this directory:
      ./script/build_and_run.sh gui [review.json]
      ./script/build_and_run.sh inventory
      ./script/build_and_run.sh preview [review.json]
      ./script/build_and_run.sh add [review.json]
      ./script/build_and_run.sh remove [review.json]

    With no arguments, the script opens the review window. The default CLI review file is
    unbleep-review.json. MusicKit handles authentication for builds signed
    for a MusicKit-enabled App ID. See docs/usage.md for signing and key setup.
    """

    @MainActor
    static func main() {
        let arguments = Array(CommandLine.arguments.dropFirst())
        if arguments.isEmpty || arguments.first == "--gui" {
            MusicReviewApp.main()
            return
        }
        Task { @MainActor in
            do {
                try await run(arguments)
                exit(EXIT_SUCCESS)
            } catch {
                let message = "Unbleep: \(error.localizedDescription)\n"
                FileHandle.standardError.write(Data(message.utf8))
                exit(EXIT_FAILURE)
            }
        }
        dispatchMain()
    }

    @MainActor
    static func run(_ arguments: [String]) async throws {
        let command = arguments.first ?? "inventory"
        if command == "--help" || command == "-h" {
            print(help)
            return
        }
        guard ["inventory", "preview", "add", "remove"].contains(command),
              arguments.count <= (command == "inventory" ? 1 : 2) else {
            throw ToolError(help)
        }
        let reviewURL = URL(fileURLWithPath: arguments.dropFirst().first ?? "unbleep-review.json")
        try await authorizeLibrary()

        if command == "inventory" {
            let songs = try readMacLibrary()
            let clean = songs.filter(\.isClean)
            print("Mac Music library: \(songs.count) songs, \(clean.count) marked Clean, \(songs.filter(\.isExplicit).count) marked Explicit.")
            print("\(clean.filter { !$0.protections.isEmpty }.count) clean tracks are in a playlist, purchased, or stored on disk.")
            return
        }

        if command == "preview" {
            let local = try readMacLibrary()
            let api = try await AppleMusic.connect(catalogCache: CatalogResponseCache())
            let review = try await preview(using: api, local: local)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            do {
                try encoder.encode(review).write(to: reviewURL, options: [.withoutOverwriting])
            } catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileWriteFileExistsError {
                throw ToolError("A review already exists at \(reviewURL.path). Choose a new filename.")
            }
            printReview(review)
            print("\nSaved review to \(reviewURL.path).")
            return
        }

        let review = try JSONDecoder().decode(Review.self, from: Data(contentsOf: reviewURL))
        try review.validate()
        guard !review.swaps.isEmpty else {
            print("This review contains no swaps.")
            return
        }
        let api = try await AppleMusic.connect()
        let verified = try await verify(review, using: api, onSkip: { swap in
            print("Skipped \(swap.clean.info.description) — the reviewed versions couldn't be verified in the current library.")
        })
        if command == "add" {
            let missing = verified.filter { !$0.explicitIsInCloud }
            let ids = Set(missing.map { $0.swap.explicit.id })
            guard !ids.isEmpty else {
                print("No explicit tracks need to be added.")
                return
            }
            for item in missing { print("Add \(item.swap.explicit.info.description)") }
            guard confirm("ADD", "Submit \(ids.count) explicit tracks to Apple Music?") else { return }
            try await api.add(ids)
            print("Apple Music accepted the add request. Run remove after the explicit tracks appear in Music on this Mac.")
            return
        }

        var ready: [VerifiedSwap] = []
        for item in verified {
            if let blocker = item.removalBlocker {
                print("Kept \(item.swap.clean.info.description) — \(blocker).")
            } else {
                ready.append(item)
                print("Remove \(item.swap.clean.info.description)")
            }
        }
        guard !ready.isEmpty else {
            print("No clean tracks are ready to remove.")
            return
        }
        print("Music can remove play history attached to these entries. With Sync Library, removal also reaches your other devices.")
        guard confirm("REMOVE", "Remove these \(ready.count) clean tracks from your Music library?") else { return }
        let currentLibrary = try readMacLibrary()
        var removed = 0
        for item in ready {
            let status = try removeIfCurrent(item, in: currentLibrary)
            if status == .removed { removed += 1 }
            print("\(status.description) — \(item.swap.clean.info.description)")
        }
        print("Removed \(removed) of \(ready.count) clean tracks in Music.")
    }

    private static func confirm(_ word: String, _ question: String) -> Bool {
        guard isatty(STDIN_FILENO) == 1 else {
            print("Run this command in Terminal to confirm the changes.")
            return false
        }
        print("\n\(question) Type \(word) to continue.")
        guard readLine() == word else {
            print("Canceled.")
            return false
        }
        return true
    }

    private static func printReview(_ review: Review) {
        for swap in review.swaps {
            print("\n\(swap.clean.info.description)")
            print("  Clean     \(swap.clean.url?.absoluteString ?? swap.clean.id)")
            print("  Explicit  \(swap.explicit.url?.absoluteString ?? swap.explicit.id) (\(swap.match))")
            if swap.alreadyInLibrary { print("  Explicit version already in library.") }
            for protection in swap.protectedBy { print("  Keep clean copy — \(protection)") }
        }
        for song in review.unmatched {
            print("\n\(song.song.description) — \(song.reason)")
            for candidate in song.candidates { print("  \(candidate.url?.absoluteString ?? candidate.id)") }
        }
        print("\n\(review.scanned) clean tracks scanned, \(review.swaps.count) matched, \(review.unmatched.count) need review.")
    }
}
#endif
