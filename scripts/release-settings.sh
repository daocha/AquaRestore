# AquaRestore's settings for the shared Android build/release scripts (sourced by _signing-common.sh).
# Every other release script is the same file in AquaRestore and PassVault; only this one differs between them.

app_name=AquaRestore
app_id=com.aquarestore.app
# Environment variables are named <env_prefix>_KEYSTORE, <env_prefix>_KEY_ALIAS and so on (see _signing-common.sh).
env_prefix=AQUARESTORE
default_keystore="$HOME/.aquarestore-signing/aquarestore-release.jks"
default_key_alias=release
default_lineage="$HOME/.aquarestore-signing/lineage.bin"
# Directories whose untracked files could end up in a release build.
build_dirs=(android core scripts)
# The Play build must not update itself: Play forbids installing APKs from outside Play.
play_forbidden_permissions=(android.permission.REQUEST_INSTALL_PACKAGES)

# The tuned grading is the private core/ submodule; fetch it when a fresh clone lacks it.
# --release also refuses the public stub and any core commit AquaRestore-Core does not have,
# so every published version can be rebuilt from its tag.
ensure_core() {
  if [ ! -d "$root/core/android/main" ] && [ -f "$root/.gitmodules" ]; then
    git -C "$root" submodule update --init core \
      || die 'Cannot fetch the private core/. Without access, debug builds can use scripts/use-core-stub.sh.'
  fi
  [ -d "$root/core/android/main" ] \
    || die 'core/ is empty. Run git submodule update --init, or scripts/use-core-stub.sh without access.'
  [ "${1:-}" = --release ] || return 0
  [ -e "$root/core/.git" ] || die 'core/ holds the public stub. Releases need the private core: git submodule update --init.'
  case "$(git -C "$root" submodule status core)" in
    [+-U]*) die 'core/ is not at the commit this repository records. Commit the core/ update, or run git submodule update.' ;;
  esac
  [ -z "$(git -C "$root/core" status --porcelain)" ] || die 'core/ has uncommitted changes. Commit and push them to AquaRestore-Core first.'
  git -C "$root/core" fetch --quiet origin || die 'Cannot reach AquaRestore-Core to check the core/ commit.'
  [ -n "$(git -C "$root/core" branch -r --contains HEAD)" ] || die 'The core/ commit is not on AquaRestore-Core. Push it there first.'
}

# Checks the sources before a build (--release: before a signed build).
check_sources() { ensure_core "$@"; }

# Release notes for GitHub when --notes-file is not given. Arguments: version, versionCode, source commit.
default_release_notes() {
  cat <<NOTES
AquaRestore $1 ($2) — Android 10+.

- Intelligent underwater color recommendations and one-slider restore intensity.
- Smooth proxy previews, original-color comparison and background exports.
- Original / custom resolution, frame rate and quality.
- Chinese / English and system / light / dark themes.
- HDR10 / HLG preservation requires Android 13+ and compatible HDR hardware. Dolby Vision dynamic metadata is not supported.

Download the signed APK and verify it against the SHA256SUMS file.
Source commit: $3
NOTES
}
