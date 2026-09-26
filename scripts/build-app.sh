#!/bin/bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

configuration="${1:-release}"
case "$configuration" in
    debug|release) ;;
    *) echo "Usage: $0 [debug|release]" >&2; exit 2 ;;
esac

# Prefer the installed Xcode toolchain; an explicit selection always wins.
if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode.app/Contents/Developer ]]; then
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

swift build --configuration "$configuration" --product Cue
binary_directory="$(swift build --configuration "$configuration" --show-bin-path)"
app_directory="$repo_root/.build/Cue.app"
install -d "$app_directory/Contents/MacOS"
install -m 755 "$binary_directory/Cue" "$app_directory/Contents/MacOS/Cue"
install -m 644 Resources/Info.plist "$app_directory/Contents/Info.plist"
printf 'Built %s\n' "$app_directory"
