#!/usr/bin/env bash
# Build and verify the Google Play bundle (playRelease) locally, signed with the Play upload key. Does not upload.
# Play re-signs what it delivers with the app signing key (the GitHub release key, registered via Play App Signing).
# Usage: scripts/build-android-play.sh [--skip-tests]
# Upload key: AQUARESTORE_UPLOAD_KEYSTORE (default ~/.aquarestore-signing/aquarestore-upload.jks),
#   AQUARESTORE_UPLOAD_KEY_ALIAS (default upload), AQUARESTORE_UPLOAD_KEYSTORE_PASSWORD / _KEY_PASSWORD.
set +x
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
. "$here/_signing-common.sh"
run_tests=1
for arg in "$@"; do
  case "$arg" in
    --skip-tests) run_tests=0 ;;
    -h|--help) sed -n '2,6p' "$0"; exit 0 ;;
    *) die "Unknown option: $arg" ;;
  esac
done
# The upload key is not the app signing key: never fall back to the release key's settings or passwords.
keystore="${AQUARESTORE_UPLOAD_KEYSTORE:-$HOME/.aquarestore-signing/aquarestore-upload.jks}"
alias_name="${AQUARESTORE_UPLOAD_KEY_ALIAS:-upload}"
AQUARESTORE_KEYSTORE_PASSWORD="${AQUARESTORE_UPLOAD_KEYSTORE_PASSWORD:-}"
AQUARESTORE_KEY_PASSWORD="${AQUARESTORE_UPLOAD_KEY_PASSWORD:-}"
ensure_core --release
find_toolchain
find_signing_tools
read_version
[ -f "$keystore" ] || printf 'Play upload key (signs only what you upload; Play signs what users install).\n'
ensure_keystore
trap 'unset AQUARESTORE_KEYSTORE_PASSWORD AQUARESTORE_KEY_PASSWORD' EXIT
if [ "$run_tests" = 1 ]; then run_unsigned_gradle --no-daemon :app:testDebugUnitTest :app:lintPlayRelease; fi
cd "$android_root"
# The APK of the same variant is built only to check the merged manifest; the bundle is what goes to Play.
AQUARESTORE_KEYSTORE_FILE="$keystore" AQUARESTORE_KEY_ALIAS="$alias_name" \
  ./gradlew "${gradle_args[@]}" --no-daemon :app:bundlePlayRelease :app:assemblePlayRelease
source_aab="$android_root/app/build/outputs/bundle/playRelease/app-playRelease.aab"
check_apk="$android_root/app/build/outputs/apk/playRelease/app-playRelease.apk"
[ -f "$source_aab" ] && [ -f "$check_apk" ] || die 'The playRelease bundle was not produced.'
verify_release_apk "$check_apk"
# Play forbids updating outside Play, so the GitHub updater's install permission must not reach this build.
case "$("$aapt" dump badging "$check_apk")" in
  *REQUEST_INSTALL_PACKAGES*) die 'The Play build requests REQUEST_INSTALL_PACKAGES.' ;;
esac
cert_file="$(mktemp "${TMPDIR:-/tmp}/aquarestore-cert.XXXXXX")"
"$JAVA_HOME/bin/keytool" -exportcert -keystore "$keystore" -alias "$alias_name" \
  -storepass:env AQUARESTORE_KEYSTORE_PASSWORD -file "$cert_file" >/dev/null 2>&1 \
  || { rm -f "$cert_file"; die 'Cannot read the upload certificate.'; }
expected_cert="$(sha256 "$cert_file" | awk '{print $1}')"
rm -f "$cert_file"
actual_cert="$("$JAVA_HOME/bin/keytool" -printcert -jarfile "$source_aab" | sed -n 's/^[[:space:]]*SHA256: //p' | head -n1 | tr -d ':' | tr 'A-F' 'a-f')"
[ -n "$actual_cert" ] && [ "$actual_cert" = "$expected_cert" ] || die 'The bundle is not signed with the upload key.'
mkdir -p "$root/dist"
aab="$root/dist/AquaRestore-$version-$code-play.aab"
cp "$source_aab" "$aab"
# Play Console asks for this certificate when you register the upload key.
"$JAVA_HOME/bin/keytool" -exportcert -rfc -keystore "$keystore" -alias "$alias_name" \
  -storepass:env AQUARESTORE_KEYSTORE_PASSWORD -file "$root/dist/AquaRestore-upload-certificate.pem" >/dev/null 2>&1 \
  || die 'Cannot export the upload certificate.'
printf '\nPlay bundle: %s (upload key %s, SHA-256 %s)\nUpload certificate: %s\n' "$aab" "$alias_name" "$expected_cert" \
  "$root/dist/AquaRestore-upload-certificate.pem"
