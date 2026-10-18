#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="CTX"
BUNDLE_ID="dev.eliasafa.CTX"
LATEST_TAG=$(git describe --tags --abbrev=0 2>/dev/null || echo "0.2.0")
APP_VERSION="${CTX_RELEASE_VERSION:-$LATEST_TAG}"
APP_VERSION="${APP_VERSION#v}"
APP_BUILD="${GITHUB_RUN_NUMBER:-1}"
if [[ "$MODE" == "preview" ]]; then
  APP_BUILD="${CTX_PREVIEW_BUILD:-$(date +%Y%m%d%H%M%S)}"
fi
MIN_SYSTEM_VERSION="14.0"

SWIFT_SANDBOX_FLAGS=()
if [[ "${CTX_DISABLE_SWIFTPM_SANDBOX:-0}" == "1" ]]; then
  SWIFT_SANDBOX_FLAGS+=(--disable-sandbox)
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_BINARY="$APP_MACOS/$APP_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"
RESOURCES_DIR="$APP_CONTENTS/Resources"
ICON_SVG="$ROOT_DIR/Resources/CTXIcon.svg"
ICONSET_DIR="$DIST_DIR/CTX.iconset"
ICON_FILE="$RESOURCES_DIR/CTX.icns"
# iconutil validates the directory extension as well as its contents.
# Keep the temporary directory hidden, but make sure it still ends in `.iconset`.
ICON_WORK_DIR="$DIST_DIR/.CTX.tmp.iconset"

cd "$ROOT_DIR"
if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode.app/Contents/Developer ]]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

killall "$APP_NAME" >/dev/null 2>&1 || true

BUILD_CONFIG="debug"
if [[ "$MODE" == "release" || "$MODE" == "preview" ]]; then
  BUILD_CONFIG="release"
  swift run ${SWIFT_SANDBOX_FLAGS[@]+"${SWIFT_SANDBOX_FLAGS[@]}"} CTXCoreTests
fi

swift build ${SWIFT_SANDBOX_FLAGS[@]+"${SWIFT_SANDBOX_FLAGS[@]}"} -c "$BUILD_CONFIG" --product "$APP_NAME"
BUILD_DIR="$(swift build ${SWIFT_SANDBOX_FLAGS[@]+"${SWIFT_SANDBOX_FLAGS[@]}"} -c "$BUILD_CONFIG" --show-bin-path)"
BUILD_BINARY="$BUILD_DIR/$APP_NAME"

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_MACOS" "$RESOURCES_DIR"
cp "$BUILD_BINARY" "$APP_BINARY"
chmod +x "$APP_BINARY"

if [[ -d "$BUILD_DIR/${APP_NAME}_${APP_NAME}.bundle" ]]; then
  cp -R "$BUILD_DIR/${APP_NAME}_${APP_NAME}.bundle" "$RESOURCES_DIR/"
fi

if [[ -f "$ICON_SVG" ]]; then
  rm -rf "$ICON_WORK_DIR"
  mkdir -p "$ICON_WORK_DIR"
  ICON_GENERATION_OK=1
  for size in 16 32 128 256 512; do
    if ! qlmanage -t -s "$size" -o "$ICON_WORK_DIR" "$ICON_SVG" >/dev/null 2>&1; then
      ICON_GENERATION_OK=0
      break
    fi
    mv "$ICON_WORK_DIR/CTXIcon.svg.png" "$ICON_WORK_DIR/icon_${size}x${size}.png"
    if ! qlmanage -t -s "$((size * 2))" -o "$ICON_WORK_DIR" "$ICON_SVG" >/dev/null 2>&1; then
      ICON_GENERATION_OK=0
      break
    fi
    mv "$ICON_WORK_DIR/CTXIcon.svg.png" "$ICON_WORK_DIR/icon_${size}x${size}@2x.png"
  done
  if [[ "$ICON_GENERATION_OK" == "1" ]] && iconutil -c icns "$ICON_WORK_DIR" -o "$ICON_FILE"; then
    rm -rf "$ICONSET_DIR"
    mv "$ICON_WORK_DIR" "$ICONSET_DIR"
  else
    rm -rf "$ICON_WORK_DIR"
    echo "warning: app icon generation is unavailable; continuing without CTX.icns" >&2
  fi
fi

ICON_PLIST_ENTRY=""
if [[ -f "$ICON_FILE" ]]; then
  ICON_PLIST_ENTRY=$'  <key>CFBundleIconFile</key>\n  <string>CTX</string>'
fi

cat >"$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundleShortVersionString</key>
  <string>$APP_VERSION</string>
  <key>CFBundleVersion</key>
  <string>$APP_BUILD</string>
$ICON_PLIST_ENTRY
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
  <key>NSHumanReadableCopyright</key>
  <string>Copyright © 2026 Eliasaf Abargel</string>
</dict>
</plist>
PLIST

codesign --force --deep --sign - "$APP_BUNDLE" >/dev/null
echo "App built and signed: $APP_BUNDLE"

open_app() {
  killall "$APP_NAME" >/dev/null 2>&1 || true
  local launch_bundle="$APP_BUNDLE"
  if [ -w /Applications ]; then
    rm -rf "/Applications/$APP_NAME.app"
    cp -R "$APP_BUNDLE" "/Applications/"
    xattr -rd com.apple.quarantine "/Applications/$APP_NAME.app" >/dev/null 2>&1 || true
    # Launch Services indexes every .app under $HOME, so a staging bundle left in
    # dist/ shows up alongside the installed copy as a second, stale app.
    rm -rf "$APP_BUNDLE"
    launch_bundle="/Applications/$APP_NAME.app"
  fi
  if ! /usr/bin/open "$launch_bundle"; then
    echo "warning: Launch Services could not open CTX; starting its executable directly" >&2
    ("$launch_bundle/Contents/MacOS/$APP_NAME" >/dev/null 2>&1 &)
  else
    echo "App opened: $launch_bundle"
  fi
}

case "$MODE" in
  run)
    open_app
    ;;
  release)
    cd "$DIST_DIR"
    zip -qy -r "$APP_NAME.app.zip" "$APP_NAME.app"
    echo "Release packaged: $DIST_DIR/$APP_NAME.app.zip"
    ;;
  preview)
    open_app
    echo "Preview build opened: $APP_BUNDLE"
    echo "Version: $APP_VERSION ($APP_BUILD)"
    ;;
  --debug|debug)
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    open_app
    sleep 1
    pgrep -x "$APP_NAME" >/dev/null
    ;;
  *)
    echo "usage: $0 [run|preview|release|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac
