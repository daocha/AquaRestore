#!/usr/bin/env bash
# Prepare macOS for Android builds and GitHub releases. No iOS tools; the signing key is created on first release.
# Usage: scripts/setup-release-env.sh
# Installs missing Homebrew packages and Android SDK packages; accepts SDK licenses.
set -euo pipefail
die() { printf 'error: %s\n' "$*" >&2; exit 1; }
case "${1:-}" in -h|--help) sed -n '2,4p' "$0"; exit 0 ;; '') ;; *) die 'Unknown argument.' ;; esac
[ "$(uname)" = Darwin ] || die 'This setup helper is for macOS. On Linux, install JDK 17 and Android SDK 36 and set JAVA_HOME / ANDROID_HOME.'
command -v brew >/dev/null 2>&1 || die 'Install Homebrew from https://brew.sh first.'
if ! /usr/libexec/java_home -v 17 >/dev/null 2>&1; then brew install --cask temurin@17; fi
command -v gh >/dev/null 2>&1 || brew install gh
command -v git >/dev/null 2>&1 || brew install git
if ! command -v sdkmanager >/dev/null 2>&1 && ! brew list --cask android-commandlinetools >/dev/null 2>&1; then
  brew install --cask android-commandlinetools
fi
export JAVA_HOME="$(/usr/libexec/java_home -v 17)"
export ANDROID_HOME="${ANDROID_HOME:-$HOME/Library/Android/sdk}"
sdkmanager="$(command -v sdkmanager || true)"
[ -n "$sdkmanager" ] || sdkmanager="$(brew --prefix)/share/android-commandlinetools/cmdline-tools/latest/bin/sdkmanager"
[ -x "$sdkmanager" ] || die 'sdkmanager not found after installation.'
mkdir -p "$ANDROID_HOME"
# Ignore only yes's expected SIGPIPE, not an sdkmanager failure.
set +o pipefail
yes | "$sdkmanager" --sdk_root="$ANDROID_HOME" --licenses
set -o pipefail
"$sdkmanager" --sdk_root="$ANDROID_HOME" 'platform-tools' 'platforms;android-36' 'build-tools;35.0.0' 'build-tools;36.0.0'
printf '\nReady. JDK: %s\nSDK: %s\n' "$JAVA_HOME" "$ANDROID_HOME"
cat <<'NEXT'
Next:
  gh auth login
  scripts/build-android-debug.sh
  scripts/release-github.sh

The first release offers to create AquaRestore's own signing key at ~/.aquarestore-signing/aquarestore-release.jks
(use a key separate from your other apps). To use an existing key instead, set AQUARESTORE_KEYSTORE and
AQUARESTORE_KEY_ALIAS. To let phones running debug builds update in place, run scripts/rotate-signing-key.sh once.
NEXT
