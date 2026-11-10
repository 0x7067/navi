#!/bin/zsh
# Publishes a new Navi version on GitHub Releases. Friends' copies update through Sparkle.
#
#   scripts/release.sh 0.2.0 "What changed, in a sentence or two."
#
# It sets the version in project.yml (and adds 1 to the build number), runs scripts/share.sh
# (build, Developer ID, notarize), signs the update with the Sparkle key in your keychain,
# writes appcast.xml, and makes the GitHub release vX.Y.Z with Navi.zip and appcast.xml.
#
# Links that always point at the newest version:
#   https://github.com/donovanhiland/navi/releases/latest/download/Navi.zip   (send this to friends)
#   https://github.com/donovanhiland/navi/releases/latest/download/appcast.xml (Navi checks this)
set -euo pipefail

version=${1:?Usage: scripts/release.sh <version> [notes]}
notes=${2:-"Navi $version"}
root=${0:A:h:h}
cd "$root"
repo=donovanhiland/navi
tag="v$version"

if gh release view "$tag" --repo "$repo" >/dev/null 2>&1; then
  echo "Release $tag already exists." >&2
  exit 1
fi

build=$(sed -n 's/^ *CURRENT_PROJECT_VERSION: "\{0,1\}\([0-9]*\)"\{0,1\}$/\1/p' project.yml)
next=$((build + 1))
sed -i '' -E "s/^( *MARKETING_VERSION: ).*/\1\"$version\"/; s/^( *CURRENT_PROJECT_VERSION: ).*/\1\"$next\"/" project.yml
echo "› Version $version (build $next)"

scripts/share.sh

echo "› Signing the update and writing appcast.xml"
out="$root/dist/release"
rm -rf "$out"
mkdir -p "$out"
cp dist/Navi.zip "$out/Navi.zip"
print -r -- "<p>$notes</p>" > "$out/Navi.html"   # generate_appcast uses this as the release notes
xcodegen generate >/dev/null
xcodebuild -resolvePackageDependencies -project Navi.xcodeproj -scheme Navi -derivedDataPath build -quiet
build/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_appcast \
  --download-url-prefix "https://github.com/$repo/releases/download/$tag/" \
  --embed-release-notes "$out"

echo "› Publishing $tag"
gh release create "$tag" "$out/Navi.zip" "$out/appcast.xml" --repo "$repo" \
  --title "Navi $version" --notes "$notes

Download: https://github.com/$repo/releases/latest/download/Navi.zip
Unzip, move Navi to Applications, and open it. After that, Navi updates itself."

echo "Done: https://github.com/$repo/releases/tag/$tag"
