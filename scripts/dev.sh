#!/bin/zsh
# Local test loop. Builds "Navi Dev" and runs it in place of the installed Navi.
# Navi Dev has its own permissions, settings, and history, so testing never touches the real Navi.
#
#   scripts/dev.sh          build and run Navi Dev (keeps its permissions and settings)
#   scripts/dev.sh fresh    wipe Navi Dev first (permissions, settings, history) to test first-run setup
#   scripts/dev.sh stop     quit Navi Dev and reopen the installed Navi
set -euo pipefail

root=${0:A:h:h}
cd "$root"
dev_id=com.donovanhiland.navi.dev
app="$root/build.noindex/Build/Products/Debug/Navi Dev.app"
command=${1:-run}

quit() {
  pkill -x "$1" 2>/dev/null || true
  for _ in {1..40}; do pgrep -x "$1" >/dev/null || return 0; sleep 0.25; done
}

case $command in
  stop)
    quit "Navi Dev"
    open -a /Applications/Navi.app 2>/dev/null || true
    echo "Navi Dev quit. Navi is back."
    exit 0 ;;
  run | fresh) ;;
  *) echo "Usage: scripts/dev.sh [fresh | stop]" >&2; exit 2 ;;
esac

echo "› Building Navi Dev"
xcodegen generate >/dev/null
xcodebuild -project Navi.xcodeproj -scheme Navi -configuration Debug -derivedDataPath build.noindex -quiet build

# Both apps use the same shortcuts, so only one runs at a time.
quit Navi
quit "Navi Dev"

if [[ $command == fresh ]]; then
  tccutil reset All $dev_id >/dev/null
  defaults delete $dev_id 2>/dev/null || true
  rm -rf "$HOME/Library/Application Support/Navi Dev"
  echo "› Wiped Navi Dev: permissions, settings, and history"
fi

open "$app"
echo "Navi Dev is running. Run scripts/dev.sh stop to go back to Navi."
