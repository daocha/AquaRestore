#!/usr/bin/env bash
# Build, sign, tag, push and publish an Android APK + SHA256SUMS to GitHub.
# Usage: scripts/release-github.sh [--version 1.0.1] [--version-code 2]
#        [--draft] [--prerelease] [--notes-file FILE] [--skip-tests] [--dry-run]
# --dry-run builds/verifies locally only; no commits, tags, pushes or GitHub writes.
# Uses the current branch and origin GitHub repository. Requires a clean tree to publish.
# New version names automatically increment versionCode unless explicitly provided.
# Signing uses AQUARESTORE_KEYSTORE / AQUARESTORE_KEY_ALIAS and hidden password prompts.
set +x
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
. "$here/_signing-common.sh"
draft=0; prerelease=0; dry_run=0; skip_tests=0
requested_version=''; requested_code=''; notes_file=''
while [ "$#" -gt 0 ]; do
  case "$1" in
    --version|--version-code|--notes-file)
      [ "$#" -ge 2 ] || die "Missing value for $1"
      case "$1" in
        --version) requested_version="${2#v}" ;;
        --version-code) requested_code="$2" ;;
        --notes-file) notes_file="$2" ;;
      esac
      shift 2 ;;
    --draft) draft=1; shift ;;
    --prerelease) prerelease=1; shift ;;
    --dry-run) dry_run=1; shift ;;
    --skip-tests) skip_tests=1; shift ;;
    -h|--help) sed -n '2,8p' "$0"; exit 0 ;;
    *) die "Unknown option: $1" ;;
  esac
done
if [ -n "$notes_file" ]; then
  [ -f "$notes_file" ] || die "Release notes file not found: $notes_file"
  notes_file="$(cd "$(dirname "$notes_file")" && pwd)/$(basename "$notes_file")"
fi
cd "$root"
read_version
current_version="$version"; current_code="$code"
if [ "$dry_run" = 0 ]; then
  command -v gh >/dev/null 2>&1 || die "Install GitHub CLI and run 'gh auth login' first."
  gh auth status --hostname github.com >/dev/null 2>&1 || die "Run 'gh auth login --hostname github.com' first."
  [ -z "$(git status --porcelain)" ] || die 'Commit your changes first so the release corresponds to committed source.'
  branch="$(git symbolic-ref --quiet --short HEAD)" || die 'Check out a branch before publishing.'
  origin="$(git remote get-url origin)"
  case "$origin" in
    git@github.com:*) repo="${origin#git@github.com:}" ;;
    https://github.com/*) repo="${origin#https://github.com/}" ;;
    ssh://git@github.com/*) repo="${origin#ssh://git@github.com/}" ;;
    *) die 'origin must point to a github.com repository via SSH or HTTPS.' ;;
  esac
  repo="${repo%.git}"
  [[ "$repo" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || die 'Cannot parse the origin repository.'
  gh api "repos/$repo" --silent || die "Cannot access $repo."
fi
if [ -z "$requested_version" ] && [ -t 0 ] && [ "$dry_run" = 0 ]; then
  read -r -p "Version to release [current: $version, code $code]: " requested_version
  requested_version="${requested_version#v}"
fi
version="${requested_version:-$current_version}"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?$ ]] || die 'Version must look like 1.0.0 or 1.0.0-beta.1.'
if [ -n "$requested_code" ]; then
  [[ "$requested_code" =~ ^[1-9][0-9]*$ ]] || die 'versionCode must be a positive integer.'
  [ "${#requested_code}" -le 10 ] || die 'versionCode is too large.'
  code="$requested_code"
elif [ "$version" != "$current_version" ]; then code=$((current_code + 1)); fi
[ "$code" -le 2100000000 ] || die 'versionCode must be at most 2100000000.'
[ "$code" -ge "$current_code" ] || die 'versionCode cannot decrease.'
if [ "$version" != "$current_version" ] && [ "$code" -le "$current_code" ]; then die 'A new version needs a higher versionCode.'; fi
tag="v$version"
git check-ref-format "refs/tags/$tag" >/dev/null || die "Invalid version tag: $tag"
if [ "$dry_run" = 0 ]; then
  if git show-ref --verify --quiet "refs/tags/$tag"; then die "Local tag $tag already exists. Choose a new version."; fi
  remote_refs="$(gh api "repos/$repo/git/matching-refs/tags/$tag" --jq '.[].ref')"
  while IFS= read -r ref; do
    [ "$ref" != "refs/tags/$tag" ] || die "Remote tag $tag already exists. Existing releases are never overwritten."
  done <<< "$remote_refs"
fi
# Version metadata is part of the tagged source; no unrecorded -P overrides.
if [ "$version" != "$current_version" ] || [ "$code" != "$current_code" ]; then
  temp_gradle="$(mktemp "$android_root/app/.release-version.XXXXXX")"
  awk -v version="$version" -v code="$code" '
    /^[[:space:]]*versionName = "/ { $0 = "        versionName = \"" version "\"" }
    /^[[:space:]]*versionCode = [0-9]/ { $0 = "        versionCode = " code }
    { print }
  ' "$android_root/app/build.gradle.kts" > "$temp_gradle"
  mv "$temp_gradle" "$android_root/app/build.gradle.kts"
fi
built_head="$(git rev-parse HEAD)"
expected_diff="$(git diff --binary HEAD -- | sha256 | awk '{print $1}')"
printf 'Building AquaRestore %s (%s)%s\n' "$version" "$code" "$([ "$dry_run" = 1 ] && printf ' — local dry run' || true)"
if [ "$skip_tests" = 1 ]; then "$here/build-android-release.sh" --skip-tests
else "$here/build-android-release.sh"; fi
apk="$root/dist/AquaRestore-$version-$code.apk"
sums="$root/dist/AquaRestore-$version-$code.SHA256SUMS"
[ -f "$apk" ] && [ -f "$sums" ] || die 'Missing release artifacts.'
if [ "$dry_run" = 1 ]; then
  printf '\nDry run complete. No Git/GitHub writes. Version edits, if any, remain for review.\n'
  exit 0
fi
[ "$(git rev-parse HEAD)" = "$built_head" ] && \
  [ "$(git diff --binary HEAD -- | sha256 | awk '{print $1}')" = "$expected_diff" ] && \
  [ -z "$(git ls-files --others --exclude-standard)" ] || die 'Source changed during the build. Nothing was published; build again.'
if ! git diff --quiet HEAD -- android/app/build.gradle.kts; then
  git add android/app/build.gradle.kts
  git commit -m "Release $version"
fi
commit="$(git rev-parse HEAD)"
git tag -a "$tag" -m "AquaRestore $version"
if ! git push --atomic origin "HEAD:refs/heads/$branch" "refs/tags/$tag"; then
  die "Push failed; the local $tag tag remains. Inspect git state before retrying. No GitHub release was created."
fi
if [ -z "$notes_file" ]; then
  notes_file="$root/dist/AquaRestore-$version-notes.md"
  cat > "$notes_file" <<NOTES
AquaRestore $version ($code) — Android 10+.

- Intelligent underwater color recommendations and one-slider restore intensity.
- Smooth proxy previews, original-color comparison and background exports.
- Original / custom resolution, frame rate and quality.
- Chinese / English and system / light / dark themes.
- HDR10 / HLG preservation requires Android 13+ and compatible HDR hardware. Dolby Vision dynamic metadata is not supported.

Download the signed APK and verify it against the SHA256SUMS file.
Source commit: $commit
NOTES
fi
release_args=(release create "$tag" "$apk" "$sums" --repo "$repo" --verify-tag --draft
  --title "AquaRestore $version" --notes-file "$notes_file")
[ "$prerelease" = 0 ] || release_args+=(--prerelease)
# Upload into a draft first. A failed upload must not expose an incomplete public release.
if ! gh "${release_args[@]}"; then
  die "Tag was pushed; upload failed. Inspect 'gh release view $tag --repo $repo' for a draft before retrying."
fi
if [ "$draft" = 0 ]; then
  gh release edit "$tag" --repo "$repo" --draft=false || die 'Assets uploaded, but publishing failed. The release remains a draft.'
fi
printf '\nRelease: %s\n' "$(gh release view "$tag" --repo "$repo" --json url --jq .url)"
