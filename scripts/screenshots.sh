#!/bin/bash
set -euo pipefail

# Marketing screenshots for tidybug.xeve.io, captured from a DEBUG build in
# demo mode (`--demo`): every tab is filled with synthetic data, so no real
# paths, project names, machine name or IP address end up on the website.
#
# Usage: scripts/screenshots.sh            (SKIP_BUILD=1 to reuse the last build)
# Output: site/shots/*.png, site/icon.png, site/og.png

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DD="$ROOT/build/DD-demo"
APP="$DD/Build/Products/Debug/TidyBug.app"
BIN="$APP/Contents/MacOS/TidyBug"
OUT="$ROOT/site/shots"
TMP="$ROOT/build/shots-tmp"
DOMAIN="com.xeve.tidybug"
mkdir -p "$OUT" "$TMP"
cd "$ROOT"

if [ "${SKIP_BUILD:-0}" != 1 ]; then
  echo "▸ Build (Debug, demo)"
  xcodegen generate >/dev/null
  xcodebuild -project TidyBug.xcodeproj -scheme TidyBug -configuration Debug -derivedDataPath "$DD" build 2>&1 \
    | grep -E "error:|BUILD" | sort -u
fi
[ -x "$BIN" ] || { echo "No demo build at $BIN"; exit 1; }

# Run a renamed, ad-hoc-signed copy so `killall TidyBug` / `pkill -x TidyBug`
# from other dev tooling can't take the demo down mid-capture.
DEMO_APP="$TMP/TBDemo.app"
rm -rf "$DEMO_APP"
ditto "$APP" "$DEMO_APP"
mv "$DEMO_APP/Contents/MacOS/TidyBug" "$DEMO_APP/Contents/MacOS/TBDemo"
plutil -replace CFBundleExecutable -string TBDemo "$DEMO_APP/Contents/Info.plist"
codesign --force --deep --sign - "$DEMO_APP" >/dev/null 2>&1
BIN="$DEMO_APP/Contents/MacOS/TBDemo"

# Remember the user's onboarding state and put it back afterwards.
read_default() { defaults read "$DOMAIN" "$1" 2>/dev/null || echo "__unset__"; }
PREV_ONBOARD=$(read_default didOnboard)
PREV_TOUR=$(read_default didTour)
PREV_STEP=$(read_default onboardingStep)
restore_default() {
  if [ "$2" = "__unset__" ]; then defaults delete "$DOMAIN" "$1" 2>/dev/null || true
  else defaults write "$DOMAIN" "$1" -int "$2"; fi
}
PID=""
cleanup() {
  [ -n "$PID" ] && kill "$PID" 2>/dev/null || true
  restore_default didOnboard "$PREV_ONBOARD"
  restore_default didTour "$PREV_TOUR"
  restore_default onboardingStep "$PREV_STEP"
}
trap cleanup EXIT

# Window-id helper: main window (layer 0) or the menu bar popover of one PID;
# "park" moves the cursor to the screen corner so nothing shows a hover state.
cat > "$TMP/win.swift" <<'SWIFT'
import CoreGraphics
import Foundation
let pid = Int(CommandLine.arguments[1])!
let mode = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "main"
if mode == "park" { CGWarpMouseCursorPosition(CGPoint(x: 2, y: 2)); exit(0) }
let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
var best: (id: Int, area: CGFloat)?
for w in list {
    guard (w[kCGWindowOwnerPID as String] as? Int) == pid,
          let id = w[kCGWindowNumber as String] as? Int,
          let b = w[kCGWindowBounds as String] as? [String: CGFloat] else { continue }
    let layer = w[kCGWindowLayer as String] as? Int ?? 0
    let h = b["Height"] ?? 0, area = (b["Width"] ?? 0) * h
    if mode == "main" && layer != 0 { continue }
    if mode == "popover" && (layer == 0 || h < 80) { continue }
    if best == nil || area > best!.area { best = (id, area) }
}
if let best { print(best.id) } else { exit(1) }
SWIFT
swiftc -O "$TMP/win.swift" -o "$TMP/win" 2>/dev/null

proc() { echo "first process whose unix id is $PID"; }
alive() { [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null; }
launch() {
  pkill -f "$BIN" 2>/dev/null || true
  sleep 0.6
  "$BIN" "$@" >/dev/null 2>&1 &
  PID=$!
  # Wait until System Events knows the process (cold launches vary).
  for _ in $(seq 1 40); do
    osascript -e "tell application \"System Events\" to exists ($(proc))" 2>/dev/null | grep -q true && break
    sleep 0.25
  done
  sleep 2
  osascript -e "tell application \"System Events\" to tell ($(proc))" \
            -e "set frontmost to true" \
            -e "set position of window 1 to {20, 45}" \
            -e "set size of window 1 to {1640, 1040}" \
            -e "end tell" >/dev/null 2>&1 || true
  sleep 1.2
}
cmd() { osascript -e "tell application \"System Events\" to tell ($(proc))" -e "set frontmost to true" \
                  -e "keystroke \"$1\" using command down" -e "end tell" >/dev/null 2>&1 || true; }
keycode() { osascript -e "tell application \"System Events\" to tell ($(proc))" -e "set frontmost to true" \
                      -e "key code $1" -e "end tell" >/dev/null 2>&1 || true; }
shot() {
  local name="$1" mode="${2:-main}" id
  alive || return 1
  [ "$mode" = main ] && "$TMP/win" "$PID" park || true
  id=$("$TMP/win" "$PID" "$mode") || return 1
  screencapture -x -o -l"$id" "$TMP/$name.png" || return 1
  if [ "$mode" = "main" ]; then sips -Z 2440 "$TMP/$name.png" --out "$OUT/$name.png" >/dev/null
  else cp "$TMP/$name.png" "$OUT/$name.png"; fi
  echo "  ✓ $name"
}
# Other tools may kill running TidyBug instances; retry a step up to 3 times.
retry() {
  local label="$1"; shift
  for n in 1 2 3; do "$@" && return 0; echo "  … retrying $label ($n)"; done
  echo "  ✗ $label"
}

TABS=(overview clean space projects duplicates large-files apps optimize monitor)
WAITS=(2.2 1.5 2.0 1.5 1.5 1.5 2.0 4.5 8.6)
tab() {
  local i="$1"
  alive || launch --demo
  cmd "$((i + 1))"
  sleep "${WAITS[$i]}"
  shot "${TABS[$i]}"
}
menubar() {
  alive || launch --demo
  osascript -e "tell application \"System Events\" to tell ($(proc)) to click menu bar item 1 of menu bar 2" >/dev/null 2>&1 || true
  sleep 2.5
  shot menubar popover
  local ok=$?
  keycode 53
  return $ok
}
collector() { launch --demo --demo-collector; cmd 2; sleep 1.5; shot collector; }
tour() {
  defaults write "$DOMAIN" didTour -bool NO
  launch --demo
  sleep 0.8
  for _ in 1 2 3; do keycode 124; sleep 0.45; done
  sleep 3.2
  shot tour
}
onboarding() {
  defaults write "$DOMAIN" didOnboard -bool NO
  defaults write "$DOMAIN" onboardingStep -int 0
  launch --demo
  shot onboarding
}

echo "▸ Tabs"
defaults write "$DOMAIN" didOnboard -bool YES
defaults write "$DOMAIN" didTour -bool YES
launch --demo
for i in "${!TABS[@]}"; do retry "${TABS[$i]}" tab "$i"; done

echo "▸ Menu bar popover"
retry menubar menubar

echo "▸ Collector"
retry collector collector

echo "▸ Feature tour (step 4)"
retry tour tour
defaults write "$DOMAIN" didTour -bool YES

echo "▸ Onboarding"
retry onboarding onboarding

kill "$PID" 2>/dev/null || true
PID=""

echo "▸ Icon + social card"
sips -Z 512 "$ROOT/TidyBug/Assets.xcassets/AppIcon.appiconset/icon_512x512@2x.png" --out "$ROOT/site/icon.png" >/dev/null
swift "$ROOT/scripts/make-og.swift" "$OUT/overview.png" "$ROOT/site/icon.png" "$ROOT/site/og.png"

du -sh "$OUT"/*.png "$ROOT/site/icon.png" "$ROOT/site/og.png" | awk '{printf "  %-6s %s\n", $1, $2}'
