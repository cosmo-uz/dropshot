#!/bin/bash
# End-to-end smoke test of the capture pipeline against a throwaway folder.
# Uses the real `screencapture` tool, so files carry the same metadata as ⌘⇧3/4/5 output,
# but never touches the real com.apple.screencapture preferences.
#
#   scripts/smoke-test.sh [path/to/Dropshot.app]
#
# NOTE: overwrites the clipboard.
set -u
APP="${1:-build/Build/Products/Debug/Dropshot.app}"
ROOT="$(mktemp -d)/Screenshots"
TODAY="$(date +%Y/%m/%d)"
PASS=0; FAIL=0
ok()   { PASS=$((PASS+1)); echo "  ✓ $1"; }
bad()  { FAIL=$((FAIL+1)); echo "  ✗ $1"; }
check(){ if eval "$2"; then ok "$1"; else bad "$1"; fi; }
stamp(){ date +"%Y-%m-%d at %H.%M.%S"; }
logs() { /usr/bin/log show --last "${1:-30s}" --info --style compact \
           --predicate 'subsystem == "app.dropshot.Dropshot"' 2>/dev/null; }

pkill -x Dropshot 2>/dev/null; sleep 0.5
mkdir -p "$ROOT"
open -n "$APP" --args -rootFolderPath "$ROOT" -onboardingCompleted YES \
  -screencaptureDomain app.dropshot.smoketest -previewDuration 2 "${@:2}"
sleep 2
check "app is running" "pgrep -xq Dropshot"

echo "1. Screenshot (written the way macOS does: temp dot-file, then rename)"
NAME="Screenshot $(stamp).png"
STAGE="$(dirname "$ROOT")/stage.png"
screencapture -x "$STAGE"
mv "$STAGE" "$ROOT/.tmp-$NAME"; sleep 0.3
mv "$ROOT/.tmp-$NAME" "$ROOT/$NAME"
sleep 1.5
check "moved into $TODAY/" "[ -f '$ROOT/$TODAY/$NAME' ]"
check "no longer in root" "[ ! -e '$ROOT/$NAME' ]"
INFO="$(osascript -e 'clipboard info' 2>/dev/null)"
check "clipboard has PNG"      "echo '$INFO' | grep -q PNGf"
check "clipboard has TIFF"     "echo '$INFO' | grep -q TIFF"
check "clipboard has file URL" "echo '$INFO' | grep -q furl"
CLIP_PATH="$(osascript -e 'POSIX path of (the clipboard as «class furl»)' 2>/dev/null)"
check "clipboard file URL points at sorted file" "[ '$CLIP_PATH' = '$ROOT/$TODAY/$NAME' ]"
MS="$(logs 10s | grep -o 'Clipboard ready [0-9]* ms' | tail -1 | grep -o '[0-9]*')"
check "clipboard ready in <1000 ms (was ${MS:-?} ms)" "[ -n '${MS:-}' ] && [ '${MS:-9999}' -lt 1000 ]"

echo "2. Burst of 5 captures"
for i in 1 2 3 4 5; do screencapture -x "$ROOT/Screenshot burst $i.png"; done
sleep 2.5
COUNT="$(ls "$ROOT/$TODAY" | grep -c 'burst')"
check "all 5 sorted (got $COUNT)" "[ '$COUNT' = 5 ]"
check "root is empty of captures" "[ -z \"\$(ls '$ROOT' | grep -i png)\" ]"
SORTED="$(logs 15s | grep -c 'Sorted Screenshot burst')"
check "each processed exactly once (log shows $SORTED)" "[ '$SORTED' = 5 ]"

echo "3. Things that must be ignored"
cp "$ROOT/$TODAY/$NAME" "$ROOT/.hidden-temp.png"
echo hello > "$ROOT/notes.txt"
sips -s format png "$ROOT/$TODAY/$NAME" --out "$ROOT/exported-logo.png" >/dev/null 2>&1
xattr -c "$ROOT/exported-logo.png"
sleep 1.5
check "dot-file untouched"            "[ -f '$ROOT/.hidden-temp.png' ]"
check "non-image untouched"           "[ -f '$ROOT/notes.txt' ]"
check "unrelated image left in place" "[ -f '$ROOT/exported-logo.png' ]"
rm -f "$ROOT/.hidden-temp.png" "$ROOT/notes.txt" "$ROOT/exported-logo.png"

echo "4. Slowly written file is not picked up half-finished"
SRC="$ROOT/$TODAY/$NAME"; SLOW="$ROOT/Screenshot slow.png"; SIZE=$(stat -f %z "$SRC")
( head -c $((SIZE/3)) "$SRC" > "$SLOW"; sleep 0.5
  head -c $((SIZE*2/3)) "$SRC" > "$SLOW"; sleep 0.5
  cat "$SRC" > "$SLOW" ) 
sleep 1.5
check "sorted once complete" "[ -f '$ROOT/$TODAY/Screenshot slow.png' ]"
check "sorted copy is the whole file" "[ \"\$(stat -f %z '$ROOT/$TODAY/Screenshot slow.png' 2>/dev/null)\" = '$SIZE' ]"

echo "5. Screen recording (2 s)"
REC="Screen Recording $(stamp).mov"
if screencapture -x -V 2 "$ROOT/$REC" 2>/dev/null && [ -s "$ROOT/$REC" -o -f "$ROOT/$TODAY/$REC" ]; then
  sleep 2.5
  check "recording sorted" "[ -f '$ROOT/$TODAY/$REC' ]"
  INFO="$(osascript -e 'clipboard info' 2>/dev/null)"
  check "clipboard has file URL" "echo '$INFO' | grep -q furl"
  check "clipboard has NO image data" "! echo '$INFO' | grep -Eq 'PNGf|TIFF'"
else
  echo "  - skipped (screencapture could not record here)"
fi

echo "6. Folder deleted while running"
rm -rf "$ROOT"
sleep 2
check "folder recreated" "[ -d '$ROOT' ]"
NAME2="Screenshot after delete.png"
screencapture -x "$ROOT/$NAME2"; sleep 1.5
check "captures still processed" "[ -f '$ROOT/$TODAY/$NAME2' ]"

echo "7. Folder renamed while running"
mv "$ROOT" "$ROOT-renamed"
sleep 2
check "folder recreated" "[ -d '$ROOT' ]"
NAME3="Screenshot after rename.png"
screencapture -x "$ROOT/$NAME3"; sleep 1.5
check "captures still processed" "[ -f '$ROOT/$TODAY/$NAME3' ]"
check "app still running (no crash)" "pgrep -xq Dropshot"

echo "8. Paused app leaves files alone; resume sorts them silently"
pkill -x Dropshot; sleep 0.5
screencapture -x "$ROOT/Screenshot while quit.png"
BEFORE="$(osascript -e 'clipboard info' 2>/dev/null)"
open -n "$APP" --args -rootFolderPath "$ROOT" -onboardingCompleted YES -screencaptureDomain app.dropshot.smoketest
sleep 2.5
check "capture taken while not running is sorted on launch" "[ -f '$ROOT/$TODAY/Screenshot while quit.png' ]"

pkill -x Dropshot
rm -rf "$(dirname "$ROOT")"
echo
echo "passed: $PASS   failed: $FAIL"
[ "$FAIL" = 0 ]
