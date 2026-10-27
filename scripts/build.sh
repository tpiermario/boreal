#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
[[ "$(uname -s)" == Darwin && "$(uname -m)" == x86_64 ]] || { echo 'Richiede un Mac Intel con Command Line Tools.' >&2; exit 1; }
bash scripts/test.sh
swift build -c release --arch x86_64
binary_dir="$(swift build -c release --arch x86_64 --show-bin-path)"
mkdir -p dist
stage="$(mktemp -d "${TMPDIR:-/tmp}/boreal-build.XXXXXX")"
trap 'rm -rf "$stage"' EXIT
app="$stage/Boreal.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$binary_dir/Boreal" "$app/Contents/MacOS/Boreal"
strip -S -x "$app/Contents/MacOS/Boreal"
cp Resources/Boreal.icns "$app/Contents/Resources/"
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>Boreal</string>
<key>CFBundleIdentifier</key><string>it.boreal.fans</string>
<key>CFBundleName</key><string>Boreal</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.2.5</string>
<key>CFBundleVersion</key><string>7</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>CFBundleIconFile</key><string>Boreal</string>
</dict></plist>
PLIST
flags=(-arch x86_64 -mmacosx-version-min=13.0 -std=c11 -Os -Wall -Wextra -Werror -I Sources/CSMC/include)
xcrun clang "${flags[@]}" Helper/main.c Sources/CSMC/smc.c Sources/CSMC/policy.c -framework IOKit -framework CoreFoundation -o "$stage/boreal-helper"
xcrun clang "${flags[@]}" Tools/cli.c Sources/CSMC/smc.c Sources/CSMC/policy.c -framework IOKit -o "$stage/borealctl"
xattr -cr "$stage"
for item in "$app" "$stage/boreal-helper" "$stage/borealctl"; do
    codesign --force --sign - "$item"
    codesign --verify --strict "$item"
done
plutil -lint "$app/Contents/Info.plist"
# Build into a fresh bundle: no stale resources from earlier builds.
if [[ -e dist/Boreal.app ]]; then mv dist/Boreal.app "$stage/previous.app"; fi
ditto --norsrc "$app" dist/Boreal.app
cp "$stage/boreal-helper" "$stage/borealctl" dist/
printf 'Build completata: %s/dist/Boreal.app\n' "$PWD"
