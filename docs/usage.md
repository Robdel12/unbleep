# Unbleep setup and CLI

A macOS app that finds songs marked Clean in Music, looks up their explicit editions, and puts the two versions side by side.

## Run from Xcode

1. Open `Unbleep.xcodeproj` and select the **Unbleep** target.
2. In **Signing & Capabilities**, select your **Team** and keep **Automatically manage signing** enabled. Use the same bundle identifier here and in your Apple Developer account.
3. In the developer portal, register or open that App ID under **Identifiers** and enable **MusicKit** under **App Services**. [Enable MusicKit for an App ID](https://developer.apple.com/help/account/services/musickit/)
4. Select **My Mac** and press **⌘R**. Allow **Media & Apple Music** when prompted, then click **Scan Library**.

## Review in the app

From this folder, build and open Unbleep:

```sh
./script/build_and_run.sh
```

Allow **Media & Apple Music** access when macOS asks. That permission lets Unbleep read your library. For catalog access, use a provisioned build with automatic MusicKit authentication, or set a Media Services key in **MusicKit Setup**. The app can read the Key ID from a standard `AuthKey_….p8` filename.

1. Click **Scan Library**, or choose **Open Review…** to load an existing CLI review.
2. Press **1** for the clean version or **2** for the explicit version. Switching keeps your place in the song, and clicking the playing version pauses it.
3. Press **Return** to approve, **S** to skip, or **⌘Z** to undo the last decision. The queue saves your place when you close the app.
4. Click **Add Approved Versions**, then **Check Sync**. The app verifies the explicit versions and asks before removing any clean copies. The results list which copies stayed and why.

If Apple Music has multiple matching explicit editions, click **Compare** beside one of them in **Choose an explicit version**. Play both versions and queue the swap if you want that edition. Tracks under **Without a verified swap** stay in your library. Their links let you check Apple Music for another release.

Catalog lookups run in small batches. Repeat scans can reuse catalog responses for 15 minutes while the app is open. Each scan reads the current library, and adding or removing tracks uses fresh Apple Music data.

## Native MusicKit setup from Terminal

MusicKit can issue the developer token automatically for a signed app. In your Apple Developer account, register an explicit App ID for Unbleep and enable **MusicKit** under **App Services**. Download a **Mac App Development** provisioning profile for that App ID, your development certificate, and this Mac. [Enable MusicKit for an App ID](https://developer.apple.com/help/account/services/musickit/) · [Create a development provisioning profile](https://developer.apple.com/help/account/provisioning-profiles/create-a-development-provisioning-profile/)

Set the profile path and the certificate name or SHA-1 shown by `security find-identity -v -p codesigning`. Then build and open the provisioned app.

```sh
export MUSIC_PROVISIONING_PROFILE="$HOME/path/to/Unbleep.provisionprofile"
export MUSIC_SIGNING_IDENTITY="YOUR_APPLE_DEVELOPMENT_CERTIFICATE"
./script/build_and_run.sh
```

The build takes the bundle ID from the profile and creates `.build/provisioned/Unbleep.app`. It uses its own macOS permission and queue preferences. In that build, leave **MusicKit Setup** blank and click **Scan Library**.

## Command-line setup

Use a Mac running macOS 14 or later with Swift 6, an active Apple Music subscription, and Sync Library enabled in Music. Open Terminal in this folder and check that the tool can read your library:

```sh
./script/build_and_run.sh inventory
```

Allow **Media & Apple Music** access if macOS asks. Inventory uses the Mac's local Music library and works without developer credentials.

An ad hoc build can also look up and add tracks with a Media Services key. Set these in the Terminal session where you run the tool. [Create a MusicKit-enabled Media Services key](https://developer.apple.com/help/account/capabilities/create-a-media-identifier-and-private-key/)

```sh
export MUSIC_TEAM_ID="YOUR_TEAM_ID"
export MUSIC_KEY_ID="YOUR_KEY_ID"
export MUSIC_KEY_FILE="$HOME/path/to/AuthKey_YOUR_KEY_ID.p8"
```

The tool signs a short-lived developer token and uses the Music account on this Mac for user authorization. If you already have a developer token without an origin restriction, you can set `MUSIC_DEVELOPER_TOKEN` instead. Keep the private key outside this folder.

## Review and swap

```sh
./script/build_and_run.sh preview
./script/build_and_run.sh add
./script/build_and_run.sh remove
```

1. **Preview** lists each matched pair with Apple Music links and saves `unbleep-review.json`. It also lists clean tracks with missing or ambiguous matches. Pass a filename after the command if you want a new report.
2. **Add** checks the reviewed tracks against your current library, then prompts before adding the missing explicit versions. Open Music and let Sync Library catch up.
3. **Remove** checks that each explicit version is present in your synced library and visible as Explicit on this Mac. It lists the eligible clean versions and prompts before deleting them through Music. Allow **Automation → Music** if macOS asks. You can rerun this command when more songs have synced.

The tool checks Apple’s linked editions of the album first, then searches the catalog. A match requires the same song, artist, album edition, disc, and track number, plus a runtime within three seconds. Title changes or missing catalog metadata can send a track to manual review.

Clean tracks in custom playlists, favorited tracks, purchases, and local downloads stay in place. You can use the report’s links to handle those manually. Removing a clean entry can lose its play history and date added. With Sync Library, deletions propagate to other devices.

Apple Music’s documented library API provides the add operation. The Mac Music app handles removal. [Apple Music API](https://developer.apple.com/documentation/applemusicapi/songs-api) · [Add a resource to a library](https://developer.apple.com/documentation/applemusicapi/add-a-resource-to-a-library) · [Delete songs in Music on Mac](https://support.apple.com/guide/music/delete-songs-and-other-items-mus51db94bb1/mac)

## Cut a Mac release

Use the same MusicKit-enabled App ID and team as the Xcode project. In Xcode, choose **Product → Archive**. In Organizer, choose **Distribute App → Direct Distribution** to sign with Developer ID and notarize the app. [Apple’s export guide](https://developer.apple.com/documentation/xcode/creating-distribution-signed-code-for-the-mac)

Open the exported app with MusicKit Setup blank and try **Scan Library**. Use **Check Sync** on an approved review to check Music automation. Then zip the exported app and attach the ZIP to the matching [GitHub release](https://github.com/Robdel12/unbleep/releases).
