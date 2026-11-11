#!/usr/bin/env bash
# RPS on macOS/Linux: start the game server and open a free Cloudflare quick
# tunnel. Needs: Flutter/Dart on PATH (or DART=...), `brew install cloudflared`.
# Build the web client first:  cd client && dart run tool/sync_assets.dart && flutter build web --release
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DART="${DART:-dart}"
PORT="${PORT:-8090}"

if ! lsof -iTCP:"$PORT" -sTCP:LISTEN >/dev/null 2>&1; then
  (cd "$ROOT/server" && "$DART" run bin/server.dart --port "$PORT") &
  SERVER_PID=$!
  trap 'kill $SERVER_PID 2>/dev/null' EXIT
  sleep 8
fi

echo
echo "==== Copy the https://....trycloudflare.com link below and send it to friends ===="
echo
cloudflared tunnel --no-autoupdate --url "http://localhost:$PORT"
