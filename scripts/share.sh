#!/bin/zsh
# Builds a Navi that opens on any Mac: Release archive, Developer ID signature,
# Apple notarization, stapled ticket. Output: dist/Navi.zip. Send that file.
#
# Needs: Xcode signed in to the Apple account for team 77SAW76597
# (Xcode → Settings → Accounts). Xcode makes the Developer ID certificate the
# first time and sends the app to Apple with that account. No passwords here.
set -euo pipefail

root=${0:A:h:h}
cd "$root"
team=77SAW76597
work="$root/build/share"
archive="$work/Navi.xcarchive"
dist="$root/dist"

rm -rf "$work" "$dist"
mkdir -p "$work" "$dist"

echo "› Archiving Release"
xcodegen generate >/dev/null
xcodebuild -project Navi.xcodeproj -scheme Navi -configuration Release \
  -archivePath "$archive" -quiet archive

cat > "$work/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key><string>developer-id</string>
  <key>teamID</key><string>$team</string>
  <key>signingStyle</key><string>automatic</string>
  <key>destination</key><string>upload</string>
</dict>
</plist>
PLIST

echo "› Signing with Developer ID and sending to Apple to notarize"
xcodebuild -exportArchive -archivePath "$archive" -exportOptionsPlist "$work/ExportOptions.plist" \
  -exportPath "$work/upload" -allowProvisioningUpdates

echo "› Waiting for Apple (usually 2–10 minutes)"
for attempt in {1..60}; do
  if xcodebuild -exportNotarizedApp -archivePath "$archive" -exportPath "$work/notarized" >"$work/notarized.log" 2>&1; then
    break
  fi
  if (( attempt == 60 )); then
    echo "Apple did not finish in 30 minutes. Last answer:" >&2
    cat "$work/notarized.log" >&2
    exit 1
  fi
  sleep 30
done
app="$work/notarized/Navi.app"

echo "› Checking"
codesign --verify --deep --strict "$app"
xcrun stapler validate "$app"
spctl --assess --type execute --verbose=2 "$app"

ditto -c -k --keepParent "$app" "$dist/Navi.zip"
echo "Done: $dist/Navi.zip"
