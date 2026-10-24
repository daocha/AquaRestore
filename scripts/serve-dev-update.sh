#!/usr/bin/env bash
# Serve android/dist/dev-update (written by every debug build when .env sets AQUARESTORE_DEV_UPDATE_HOST) to debug
# builds on the LAN. Binds to that address only, so nothing listens on other interfaces.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
setting() {
  local value="${!1:-}"
  [ -n "$value" ] || [ ! -f "$root/.env" ] || value="$(sed -n "s/^[[:space:]]*\(export[[:space:]]\{1,\}\)\{0,1\}$1[[:space:]]*=[[:space:]]*//p" "$root/.env" | tail -n 1 | tr -d "\"'")"
  printf '%s' "$value"
}
host="$(setting AQUARESTORE_DEV_UPDATE_HOST)"
port="$(setting AQUARESTORE_DEV_UPDATE_PORT)"; port="${port:-8765}"
[ -n "$host" ] || { echo 'Set AQUARESTORE_DEV_UPDATE_HOST in .env (see .env.example).' >&2; exit 1; }
dir="$root/android/dist/dev-update"
[ -f "$dir/latest.json" ] || { echo "No $dir/latest.json yet: build the debug APK first." >&2; exit 1; }
echo "Serving $dir on port $port (Ctrl-C to stop)"
exec python3 -m http.server --bind "$host" --directory "$dir" "$port"
