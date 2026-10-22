#!/usr/bin/env bash
# Remove what scripts/setup-release-env.sh and scripts/build-android-debug.sh installed on macOS.
# Usage: scripts/uninstall-build-env.sh [--yes]
# Asks before each item unless --yes is given. dist/AquaRestore-debug.apk is never touched.
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/.." && pwd)"
assume_yes=0
case "${1:-}" in
  --yes) assume_yes=1 ;;
  -h|--help) sed -n '2,4p' "$0"; exit 0 ;;
  '') ;;
  *) printf 'error: Unknown argument.\n' >&2; exit 1 ;;
esac

ask() {
  [ "$assume_yes" = 1 ] && return 0
  local reply
  read -r -p "$1 [y/N] " reply
  [[ "$reply" =~ ^[Yy]$ ]]
}

have_brew() { command -v brew >/dev/null 2>&1; }

remove_cask() {
  have_brew && brew list --cask "$1" >/dev/null 2>&1 || return 0
  if ask "Uninstall Homebrew cask '$1' ($2)?"; then brew uninstall --cask "$1"; fi
}

remove_formula() {
  have_brew && brew list --formula "$1" >/dev/null 2>&1 || return 0
  if ask "Uninstall Homebrew formula '$1' ($2)?"; then brew uninstall "$1"; fi
}

remove_dir() {
  [ -e "$1" ] || return 0
  if ask "Delete $1 ($(du -sh "$1" 2>/dev/null | cut -f1), $2)?"; then rm -rf "$1"; fi
}

remove_cask temurin@17 'JDK 17 from setup-release-env.sh; asks for your admin password'
remove_formula openjdk@17 'JDK 17 used for the latest build'
remove_cask android-commandlinetools 'Android sdkmanager'
remove_dir "${ANDROID_HOME:-$HOME/Library/Android/sdk}" 'Android SDK platform, build-tools and platform-tools'
remove_dir "$HOME/.gradle" 'Gradle downloads and caches; other Gradle projects re-download on their next build'
remove_dir /private/tmp/aquarestore-tools 'JDK, SDK, emulator and Gradle home from an earlier automated build'
# gh is only installed when missing, so it may predate the setup script.
remove_formula gh 'GitHub CLI; keep it if you used it before'
remove_dir "$root/android/app/build" 'this project build output'
remove_dir "$root/android/.gradle" 'this project Gradle state'
remove_dir "$root/android/.kotlin" 'this project Kotlin compiler state'

if have_brew && ask 'Run "brew autoremove" to drop dependencies nothing else needs?'; then brew autoremove; fi
printf '\nDone. Your APK is still at %s\n' "$root/dist/AquaRestore-debug.apk"
