# Build Unbleep in Xcode

1. Open `Unbleep.xcodeproj` and select the **Unbleep** target.
2. In **Signing & Capabilities**, select your team and turn on automatic signing. Enable MusicKit for the matching App ID. [Apple’s MusicKit setup guide](https://developer.apple.com/help/account/services/musickit/)
3. Run on **My Mac** and allow Media & Apple Music access when asked. Press **⌘U** to run the tests.

## Review clean tracks

Click **Scan Library**, then use **1** and **2** to play the clean and explicit versions. Press **Return** to swap, **S** to skip, or **⌘Z** to undo. Unbleep saves your place when you close it.

When you’re ready, click **Add Explicit Versions**, then **Check Sync**. Unbleep asks before removing clean copies and keeps favorites, playlist tracks, purchases, and local files. If Apple Music has more than one matching edition, use **Compare** to choose.

## Export a release

In Xcode, choose **Product → Archive**. In Organizer, choose **Distribute App → Direct Distribution** to sign with Developer ID and notarize the app. [Apple’s export guide](https://developer.apple.com/documentation/xcode/creating-distribution-signed-code-for-the-mac)

Try **Scan Library** and **Check Sync** in the exported app. Zip the app and attach it to the matching [GitHub release](https://github.com/Robdel12/unbleep/releases).
