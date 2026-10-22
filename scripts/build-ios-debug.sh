#!/usr/bin/env bash
# Build the iOS debug app; the core unit tests run by default.
# Usage: scripts/build-ios-debug.sh [--skip-tests] [--device] [--run]
# Needs Xcode (not only the command line tools) and XcodeGen (installed through Homebrew when missing).
# --device builds for a connected iPhone and needs a signing team: set DEVELOPMENT_TEAM=<team id>.
# --run installs and launches on the booted simulator (default: the first available iPhone).
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/.." && pwd)"
die() { printf 'error: %s\n' "$*" >&2; exit 1; }
run_tests=1; device=0; run=0
for arg in "$@"; do
  case "$arg" in
    --skip-tests) run_tests=0 ;;
    --device) device=1 ;;
    --run) run=1 ;;
    -h|--help) sed -n '2,7p' "$0"; exit 0 ;;
    *) die "Unknown option: $arg" ;;
  esac
done
[ "$(uname)" = Darwin ] || die 'iOS builds need macOS.'
xcodebuild -version >/dev/null 2>&1 || die 'Install Xcode and run: sudo xcode-select -s /Applications/Xcode.app'
if ! command -v xcodegen >/dev/null 2>&1; then
  command -v brew >/dev/null 2>&1 || die 'Install XcodeGen: brew install xcodegen'
  brew install xcodegen
fi
cd "$root/ios"
xcodegen generate --quiet
derived="$root/ios/build"
if [ "$device" = 1 ]; then
  [ -n "${DEVELOPMENT_TEAM:-}" ] || die 'Set DEVELOPMENT_TEAM=<your Apple team id> to build for a device.'
  destination='generic/platform=iOS'
  extra=(DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM" -allowProvisioningUpdates)
else
  sim="$(xcrun simctl list devices available | grep -m1 'iPhone' | sed -E 's/^ *(.*) \(([0-9A-F-]{36})\).*/\2/')"
  [ -n "$sim" ] || die 'No iPhone simulator found. Install one in Xcode > Settings > Platforms.'
  destination="platform=iOS Simulator,id=$sim"
  extra=(CODE_SIGNING_ALLOWED=NO)
fi
if [ "$run_tests" = 1 ] && [ "$device" = 0 ]; then
  xcodebuild test -project AquaRestore.xcodeproj -scheme AquaRestore -destination "$destination" -derivedDataPath "$derived" "${extra[@]}"
fi
xcodebuild build -project AquaRestore.xcodeproj -scheme AquaRestore -configuration Debug -destination "$destination" -derivedDataPath "$derived" "${extra[@]}"
if [ "$device" = 1 ]; then
  app="$derived/Build/Products/Debug-iphoneos/AquaRestore.app"
else
  app="$derived/Build/Products/Debug-iphonesimulator/AquaRestore.app"
fi
[ -d "$app" ] || die 'xcodebuild finished without creating the app.'
mkdir -p "$root/dist"
rm -rf "$root/dist/AquaRestore-debug.app"
cp -R "$app" "$root/dist/AquaRestore-debug.app"
if [ "$run" = 1 ] && [ "$device" = 0 ]; then
  xcrun simctl boot "$sim" 2>/dev/null || true
  open -a Simulator
  xcrun simctl install "$sim" "$app"
  xcrun simctl launch "$sim" com.aquarestore.app.debug
fi
printf '\nDebug app: %s\n' "$root/dist/AquaRestore-debug.app"
