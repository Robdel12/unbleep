#!/bin/bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

mode="${1:-gui}"
if [[ "$mode" == "run" ]]; then
    shift
    mode="${1:-gui}"
fi

export CLANG_MODULE_CACHE_PATH="$root/.build/module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$CLANG_MODULE_CACHE_PATH"
mkdir -p "$CLANG_MODULE_CACHE_PATH"

profile="${MUSIC_PROVISIONING_PROFILE:-}"
identity="${MUSIC_SIGNING_IDENTITY:-}"
bundle_directory="$root/.build"
bundle_id=local.explicit-music
if [[ -n "$profile" || -n "$identity" ]]; then
    if [[ ! -f "$profile" || -z "$identity" || "$identity" == "-" ]]; then
        echo 'Set MUSIC_PROVISIONING_PROFILE to a Mac App Development profile and MUSIC_SIGNING_IDENTITY to its signing certificate.' >&2
        exit 1
    fi
    bundle_directory="$bundle_directory/provisioned"
    mkdir -p "$bundle_directory"
    decoded_profile="$bundle_directory/profile.plist"
    /usr/bin/security cms -D -i "$profile" -o "$decoded_profile"
    application_id="$(/usr/libexec/PlistBuddy -c 'Print :Entitlements:com.apple.application-identifier' "$decoded_profile")"
    team_id="$(/usr/libexec/PlistBuddy -c 'Print :Entitlements:com.apple.developer.team-identifier' "$decoded_profile")"
    bundle_id="${application_id#*.}"
    if [[ "$bundle_id" == "$application_id" || ! "$bundle_id" =~ ^[a-zA-Z0-9.-]+$ ]]; then
        echo 'Use a Mac App Development profile for a specific MusicKit-enabled App ID.' >&2
        exit 1
    fi
    entitlements="$bundle_directory/entitlements.plist"
    /usr/bin/plutil -create xml1 "$entitlements"
    /usr/libexec/PlistBuddy -c "Add :com.apple.application-identifier string $application_id" \
        -c "Add :com.apple.developer.team-identifier string $team_id" "$entitlements"
fi
source_plist="$bundle_directory/Info.plist"
cp script/Info.plist "$source_plist"
/usr/bin/plutil -replace CFBundleIdentifier -string "$bundle_id" "$source_plist"

swift build --disable-sandbox --product Unbleep >&2
build_directory="$(swift build --disable-sandbox --show-bin-path)"
bundle="$bundle_directory/Unbleep.app"
binary="$bundle/Contents/MacOS/Unbleep"
plist="$bundle/Contents/Info.plist"
icon="$bundle/Contents/Resources/Unbleep.icns"
embedded_profile="$bundle/Contents/embedded.provisionprofile"
signed_identity="$bundle_directory/.signing-identity"
mkdir -p "$bundle/Contents/MacOS" "$bundle/Contents/Resources"
if [[ ! -x "$binary" || "$build_directory/Unbleep" -nt "$binary" ]] ||
    ! cmp -s "$source_plist" "$plist" || ! cmp -s script/Unbleep.icns "$icon" ||
    ! /usr/bin/codesign --verify "$bundle" >/dev/null 2>&1 ||
    { [[ -n "$profile" ]] && { ! cmp -s "$profile" "$embedded_profile" ||
        [[ ! -f "$signed_identity" || "$identity" != "$(<"$signed_identity")" ]]; }; }; then
    cp "$build_directory/Unbleep" "$binary"
    cp "$source_plist" "$plist"
    cp script/Unbleep.icns "$icon"
    if [[ -n "$profile" ]]; then
        cp "$profile" "$embedded_profile"
        /usr/bin/codesign --force --sign "$identity" --entitlements "$entitlements" --timestamp=none "$bundle" >&2
        printf '%s\n' "$identity" > "$signed_identity"
    else
        /usr/bin/codesign --force --sign - "$bundle" >&2
    fi
fi

case "$mode" in
    gui)
        if [[ -n "${2:-}" ]]; then
            review="$2"
            [[ "$review" == /* ]] || review="$root/$review"
            exec /usr/bin/open "$bundle" --args --gui "$review"
        fi
        exec /usr/bin/open "$bundle"
        ;;
    --debug) exec lldb -- "$binary" "${@:2}" ;;
    --logs|--telemetry)
        "$binary" "${@:2}" &
        exec /usr/bin/log stream --info --style compact --predicate 'process == "Unbleep"'
        ;;
    --verify) exec "$binary" --help ;;
    *) exec "$binary" "$@" ;;
esac
