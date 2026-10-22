# Shared Android build/signing utilities. This file is sourced by the entry-point scripts.
# Follows password-vault's local-signing convention (creates the key on first use), without iOS.
#
# Optional environment:
#   AQUARESTORE_KEYSTORE           keystore path         (default: ~/.aquarestore-signing/aquarestore-release.jks)
#   AQUARESTORE_KEY_ALIAS          key alias             (default: release)
#   AQUARESTORE_KEYSTORE_PASSWORD  password; prompted if unset
#   AQUARESTORE_KEY_PASSWORD       key password; defaults to the keystore password (PKCS12 keystores share one)
#   AQUARESTORE_LINEAGE            key-rotation lineage  (default: ~/.aquarestore-signing/lineage.bin)
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
android_root="$root/android"
keystore="${AQUARESTORE_KEYSTORE:-$HOME/.aquarestore-signing/aquarestore-release.jks}"
alias_name="${AQUARESTORE_KEY_ALIAS:-release}"
lineage="${AQUARESTORE_LINEAGE:-$HOME/.aquarestore-signing/lineage.bin}"

die() { printf 'error: %s\n' "$*" >&2; exit 1; }

find_toolchain() {
  if [ -z "${JAVA_HOME:-}" ] && [ -x /usr/libexec/java_home ]; then
    JAVA_HOME="$(/usr/libexec/java_home -v 17 2>/dev/null || true)"
  fi
  if [ -z "${JAVA_HOME:-}" ]; then
    for candidate in '/Applications/Android Studio.app/Contents/jbr/Contents/Home' /opt/android-studio/jbr /usr/lib/jvm/java-17-openjdk-amd64 /usr/lib/jvm/java-17-openjdk-arm64; do
      if [ -x "$candidate/bin/java" ]; then JAVA_HOME="$candidate"; break; fi
    done
  fi
  [ -n "${JAVA_HOME:-}" ] && [ -x "$JAVA_HOME/bin/java" ] && [ -x "$JAVA_HOME/bin/keytool" ] \
    || die 'JDK 17+ not found. Set JAVA_HOME or run scripts/setup-release-env.sh on macOS.'
  if [ -z "${ANDROID_HOME:-}" ]; then
    ANDROID_HOME="${ANDROID_SDK_ROOT:-}"
    if [ -z "$ANDROID_HOME" ]; then
      for candidate in "$HOME/Library/Android/sdk" "$HOME/Android/Sdk"; do
        if [ -d "$candidate" ]; then ANDROID_HOME="$candidate"; break; fi
      done
    fi
  fi
  [ -n "${ANDROID_HOME:-}" ] && [ -d "$ANDROID_HOME" ] \
    || die 'Android SDK not found. Set ANDROID_HOME or run scripts/setup-release-env.sh.'
  export JAVA_HOME ANDROID_HOME
  gradle_args=(--console=plain -Pkotlin.compiler.execution.strategy=in-process)
  if [ -n "${GRADLE_EXTRA_ARGS:-}" ]; then
    # Whitespace-delimited flags only, no eval or shell expansion.
    read -r -a extra_gradle_args <<< "$GRADLE_EXTRA_ARGS"
    gradle_args+=("${extra_gradle_args[@]}")
  fi
}

find_signing_tools() {
  local best_major=-1 best_minor=-1 best_patch=-1 candidate version major minor patch
  apksigner=''; aapt=''
  for candidate in "$ANDROID_HOME"/build-tools/*/apksigner; do
    [ -x "$candidate" ] || continue
    version="$(basename "$(dirname "$candidate")")"
    [[ "$version" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]] || continue
    major="${BASH_REMATCH[1]}"; minor="${BASH_REMATCH[2]}"; patch="${BASH_REMATCH[3]}"
    if (( major > best_major || (major == best_major && minor > best_minor) || (major == best_major && minor == best_minor && patch > best_patch) )); then
      best_major="$major"; best_minor="$minor"; best_patch="$patch"
      apksigner="$candidate"; aapt="$(dirname "$candidate")/aapt"
    fi
  done
  [ -n "$apksigner" ] && [ -x "$aapt" ] || die 'Install stable Android SDK Build-Tools (35.0.0 or newer).'
}

read_version() {
  version="$(sed -n 's/^[[:space:]]*versionName = "\([^"]*\)"[[:space:]]*$/\1/p' "$android_root/app/build.gradle.kts")"
  code="$(sed -n 's/^[[:space:]]*versionCode = \([0-9]*\)[[:space:]]*$/\1/p' "$android_root/app/build.gradle.kts")"
  [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?$ ]] || die 'Cannot read a valid versionName from android/app/build.gradle.kts.'
  [[ "$code" =~ ^[1-9][0-9]*$ ]] || die 'Cannot read versionCode from android/app/build.gradle.kts.'
}

sha256() {
  if command -v shasum >/dev/null 2>&1; then shasum -a 256 "$@"
  elif command -v sha256sum >/dev/null 2>&1; then sha256sum "$@"
  else die 'Install shasum or sha256sum.'; fi
}

# Debug/test processes never receive signing material, even if the caller exported it.
run_unsigned_gradle() (
  unset AQUARESTORE_KEYSTORE_PASSWORD AQUARESTORE_KEY_PASSWORD AQUARESTORE_KEYSTORE_FILE AQUARESTORE_KEY_ALIAS
  cd "$android_root"
  ./gradlew "${gradle_args[@]}" "$@"
)

# Creates the keystore on first use (after asking), then makes sure the alias opens with the password.
ensure_keystore() {
  if [ ! -f "$keystore" ]; then
    [ -t 0 ] || die "No signing keystore at $keystore. Run this in a terminal to create one, or set AQUARESTORE_KEYSTORE."
    printf 'No signing keystore at %s.\n' "$keystore"
    read -r -p 'Create a new AquaRestore signing key now? [y/N] ' yn
    [ "$yn" = y ] || [ "$yn" = Y ] || die 'Aborted. Set AQUARESTORE_KEYSTORE to an existing keystore.'
    # Only a directory created here is made private; an existing one (e.g. $HOME) keeps its permissions.
    [ -d "$(dirname "$keystore")" ] || (umask 077; mkdir -p "$(dirname "$keystore")")
    printf 'keytool will ask for a password (choose a long one) and your name/organisation details.\n'
    # umask 077: the keystore is never readable by other users, not even before the chmod.
    (umask 077; "$JAVA_HOME/bin/keytool" -genkeypair -v -storetype PKCS12 -keystore "$keystore" \
      -alias "$alias_name" -keyalg RSA -keysize 4096 -validity 10000) || die 'Key generation failed; nothing was created.'
    chmod 600 "$keystore"
    cat <<MSG

Keystore created: $keystore (alias: $alias_name)
BACK IT UP NOW (with its password) in at least two places, one offline. Every update to an installed
AquaRestore must be signed with this key; without it, people who installed your APK cannot update.
MSG
  fi
  keystore="$(cd "$(dirname "$keystore")" && pwd)/$(basename "$keystore")"
  if [ -z "${AQUARESTORE_KEYSTORE_PASSWORD:-}" ]; then
    [ -t 0 ] || die 'Set AQUARESTORE_KEYSTORE_PASSWORD when running without a terminal.'
    read -r -s -p 'Keystore password: ' AQUARESTORE_KEYSTORE_PASSWORD; printf '\n'
  fi
  [ -n "$AQUARESTORE_KEYSTORE_PASSWORD" ] || die 'Keystore password cannot be empty.'
  if [ -z "${AQUARESTORE_KEY_PASSWORD:-}" ]; then
    if [ -t 0 ]; then
      read -r -s -p 'Key password [Enter = keystore password]: ' AQUARESTORE_KEY_PASSWORD; printf '\n'
    fi
    AQUARESTORE_KEY_PASSWORD="${AQUARESTORE_KEY_PASSWORD:-$AQUARESTORE_KEYSTORE_PASSWORD}"
  fi
  export AQUARESTORE_KEYSTORE_PASSWORD AQUARESTORE_KEY_PASSWORD
  "$JAVA_HOME/bin/keytool" -list -keystore "$keystore" -alias "$alias_name" \
    -storepass:env AQUARESTORE_KEYSTORE_PASSWORD >/dev/null 2>&1 \
    || die "Cannot open alias '$alias_name' in $keystore. Check the alias and keystore password."
}

verify_release_apk() {
  local artifact="$1" expected_cert actual_cert metadata cert_file
  "$apksigner" verify --verbose --print-certs --min-sdk-version 29 "$artifact"
  actual_cert="$("$apksigner" verify --print-certs "$artifact" | sed -n 's/^Signer #1 certificate SHA-256 digest: //p')"
  cert_file="$(mktemp "${TMPDIR:-/tmp}/aquarestore-cert.XXXXXX")"
  if ! "$JAVA_HOME/bin/keytool" -exportcert -keystore "$keystore" -alias "$alias_name" \
      -storepass:env AQUARESTORE_KEYSTORE_PASSWORD -file "$cert_file" >/dev/null 2>&1; then
    rm -f "$cert_file"; die 'Cannot read the public signing certificate.'
  fi
  expected_cert="$(sha256 "$cert_file" | awk '{print $1}')"
  rm -f "$cert_file"
  [ -n "$actual_cert" ] && [ "$actual_cert" = "$expected_cert" ] || die 'APK signer does not match the requested JKS alias.'
  metadata="$("$aapt" dump badging "$artifact")"
  case "$metadata" in
    "package: name='com.aquarestore.app' versionCode='$code' versionName='$version'"*) ;;
    *) die 'APK package/version does not match this source tree.' ;;
  esac
  case "$metadata" in *application-debuggable*) die 'Refusing to publish a debuggable APK.' ;; esac
}
