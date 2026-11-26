#!/usr/bin/env bash
# Builds ESP Flasher and wraps it in a double-clickable .app bundle.
#
#   ./scripts/build_app.sh              # native architecture
#   UNIVERSAL=1 ./scripts/build_app.sh  # arm64 + x86_64
#   INSTALL=1 ./scripts/build_app.sh    # also copy to /Applications
set -euo pipefail

cd "$(dirname "$0")/.."

APP_NAME="ESP Flasher"
APP="build/${APP_NAME}.app"

ARCH_FLAGS=()
if [[ "${UNIVERSAL:-0}" == "1" ]]; then
  ARCH_FLAGS=(--arch arm64 --arch x86_64)
fi

echo "▸ Building (release)…"
swift build -c release ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"}
BIN_DIR="$(swift build -c release ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"} --show-bin-path)"

echo "▸ Assembling ${APP}…"
rm -rf "${APP}"
mkdir -p "${APP}/Contents/MacOS" "${APP}/Contents/Resources"
cp "${BIN_DIR}/ESPFlasher" "${APP}/Contents/MacOS/ESPFlasher"
cp Resources/Info.plist "${APP}/Contents/Info.plist"
if [[ -f Resources/AppIcon.icns ]]; then
  cp Resources/AppIcon.icns "${APP}/Contents/Resources/AppIcon.icns"
fi

echo "▸ Ad-hoc signing…"
codesign --force --deep --sign - "${APP}"

echo "✓ Built ${APP}"

if [[ "${INSTALL:-0}" == "1" ]]; then
  echo "▸ Installing to /Applications…"
  rm -rf "/Applications/${APP_NAME}.app"
  cp -R "${APP}" "/Applications/"
  echo "✓ Installed /Applications/${APP_NAME}.app"
else
  echo "  Run it with:  open \"${APP}\""
fi
