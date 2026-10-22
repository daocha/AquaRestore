#!/usr/bin/env bash
# Build and verify a signed APK locally. Does not publish. Creates the signing key on first run (after asking).
# If scripts/rotate-signing-key.sh created a key-rotation lineage, it is attached so older installs update in place.
# Usage: scripts/build-android-release.sh [--skip-tests]
# Signing configuration (keystore, alias, passwords, lineage): see _signing-common.sh.
set +x
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
. "$here/_signing-common.sh"
run_tests=1
for arg in "$@"; do
  case "$arg" in
    --skip-tests) run_tests=0 ;;
    -h|--help) sed -n '2,5p' "$0"; exit 0 ;;
    *) die "Unknown option: $arg" ;;
  esac
done
find_toolchain
find_signing_tools
read_version
# Open (or create) the key before the expensive build, so a wrong password fails fast.
ensure_keystore
trap 'unset AQUARESTORE_KEYSTORE_PASSWORD AQUARESTORE_KEY_PASSWORD' EXIT
# A lineage backup without a lineage means a rotation was lost: shipping without it would break in-place updates.
if [ ! -f "$lineage" ] && ls "$lineage".bak-* >/dev/null 2>&1; then
  die "Found $lineage.bak-* but no $lineage. Restore it or re-run scripts/rotate-signing-key.sh."
fi
# Tests run in a separate Gradle process that never receives the signing secrets.
if [ "$run_tests" = 1 ]; then run_unsigned_gradle --no-daemon :app:testDebugUnitTest :app:lintRelease; fi
cd "$android_root"
# A single-use Gradle process and in-process Kotlin compilation limit secret lifetime.
AQUARESTORE_KEYSTORE_FILE="$keystore" AQUARESTORE_KEY_ALIAS="$alias_name" \
  ./gradlew "${gradle_args[@]}" --no-daemon :app:assembleRelease
source_apk="$android_root/app/build/outputs/apk/release/app-release.apk"
[ -f "$source_apk" ] || die 'Signed release APK was not produced.'
if [ -f "$lineage" ]; then
  # Re-sign with the lineage (APK Signature Scheme v3 only; every supported Android version verifies it).
  rotated="$android_root/app/build/outputs/apk/release/app-release-rotated.apk"
  "$apksigner" sign --ks "$keystore" --ks-key-alias "$alias_name" \
    --ks-pass env:AQUARESTORE_KEYSTORE_PASSWORD --key-pass env:AQUARESTORE_KEY_PASSWORD --lineage "$lineage" \
    --min-sdk-version 29 --rotation-min-sdk-version 29 \
    --v1-signing-enabled false --v2-signing-enabled false --v3-signing-enabled true \
    --out "$rotated" "$source_apk" \
    || die "Signing with the lineage failed. Does $lineage end with the key in $keystore? (Re-run scripts/rotate-signing-key.sh --force.)"
  rm -f "$rotated.idsig"
  source_apk="$rotated"
  printf 'Key-rotation lineage attached: %s\n' "$lineage"
fi
verify_release_apk "$source_apk"
mkdir -p "$root/dist"
apk="$root/dist/AquaRestore-$version-$code.apk"
cp "$source_apk" "$apk"
(cd "$root/dist" && sha256 "$(basename "$apk")" > "AquaRestore-$version-$code.SHA256SUMS")
printf '\nSigned APK: %s%s\nChecksums: %s\n' "$apk" "$([ -f "$lineage" ] && printf ' (with key-rotation lineage)')" \
  "$root/dist/AquaRestore-$version-$code.SHA256SUMS"
