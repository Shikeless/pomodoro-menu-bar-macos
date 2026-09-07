#!/usr/bin/env bash
# Wraps the SwiftPM executable in Pomodoro.app. A menu bar app needs the bundle:
# LSUIElement lives in Info.plist, and only a bundled app is double-clickable.
#
# Usage: ./build.sh [debug|release] [--install]
#   --install  also replaces /Applications/Pomodoro.app and relaunches it, so
#              the copy you actually click stays in step with the sources.
set -euo pipefail

cd "$(dirname "$0")"
CONFIG="release"
INSTALL="no"
for arg in "$@"; do
  case "$arg" in
    --install) INSTALL="yes" ;;
    debug|release) CONFIG="$arg" ;;
    *) echo "unknown argument: $arg" >&2; exit 1 ;;
  esac
done

swift build -c "$CONFIG"
BIN="$(swift build -c "$CONFIG" --show-bin-path)"
APP="$PWD/Pomodoro.app"

# Guard the path before removing anything: this script only ever replaces the
# bundle it built itself.
case "$APP" in
  */Pomodoro.app) rm -rf "$APP" ;;
  *) echo "refusing to remove $APP" >&2; exit 1 ;;
esac

mkdir -p "$APP/Contents/MacOS"
cp "$BIN/Pomodoro" "$APP/Contents/MacOS/Pomodoro"
cp Resources/Info.plist "$APP/Contents/Info.plist"

# Ad-hoc signature: enough to run on this machine. Handing the app to someone
# else needs a Developer ID certificate and notarization instead.
codesign --force --sign - "$APP"

echo "built $APP"

if [ "$INSTALL" = "yes" ]; then
  DEST="/Applications/Pomodoro.app"
  # A running instance keeps its old binary, so it has to go first.
  pkill -f "Pomodoro.app/Contents/MacOS/Pomodoro" 2>/dev/null || true
  sleep 1
  case "$DEST" in
    /Applications/Pomodoro.app) rm -rf "$DEST" ;;
    *) echo "refusing to remove $DEST" >&2; exit 1 ;;
  esac
  cp -R "$APP" "$DEST"
  open "$DEST"
  echo "installed $DEST and relaunched"
fi
