#!/usr/bin/env bash
# Create or rotate the read-only deploy key that lets CI fetch the private core/ submodule.
# Usage: scripts/setup-core-deploy-key.sh
# The new key replaces any earlier "AquaRestore CI" deploy key on AquaRestore-Core, and its private half
# goes straight into AquaRestore's CORE_DEPLOY_KEY secret. It is never printed or kept on this computer.
# Needs ssh-keygen and GitHub CLI logged in as the owner of both repositories (gh auth login).
set -euo pipefail
core_repo=daocha/AquaRestore-Core
app_repo=daocha/AquaRestore
title='AquaRestore CI'
die() { printf 'error: %s\n' "$*" >&2; exit 1; }
case "${1:-}" in
  '') ;;
  -h|--help) sed -n '2,6p' "$0"; exit 0 ;;
  *) die "Unknown option: $1" ;;
esac
command -v ssh-keygen >/dev/null 2>&1 || die 'ssh-keygen not found.'
command -v gh >/dev/null 2>&1 || die "Install GitHub CLI and run 'gh auth login' first."
gh auth status --hostname github.com >/dev/null 2>&1 || die "Run 'gh auth login --hostname github.com' first."
gh api "repos/$core_repo" --silent || die "Cannot access $core_repo."
gh api "repos/$app_repo" --silent || die "Cannot access $app_repo."

dir="$(mktemp -d)"
trap 'rm -rf "$dir"' EXIT
ssh-keygen -q -t ed25519 -N '' -C "$title: read $core_repo" -f "$dir/key"
old="$(gh repo deploy-key list --repo "$core_repo" --json id,title --jq ".[] | select(.title == \"$title\") | .id")"
# Add the new key and secret first, so a failure never leaves CI without a working key.
gh repo deploy-key add "$dir/key.pub" --repo "$core_repo" --title "$title"
gh secret set CORE_DEPLOY_KEY --repo "$app_repo" < "$dir/key"
for id in $old; do gh repo deploy-key delete "$id" --repo "$core_repo"; done
printf 'Deploy key %s. Re-run a workflow (Actions > Android or iOS > Run workflow) to check it.\n' \
  "$([ -n "$old" ] && printf 'rotated' || printf 'created')"
