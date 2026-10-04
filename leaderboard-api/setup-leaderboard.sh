#!/usr/bin/env bash
# One-time Cloudflare Worker setup for Wave Defence shared leaderboards.
# Run from Git Bash / WSL / macOS / Linux. Do NOT paste your GitHub token into chat.
#
# Usage:
#   cd leaderboard-api
#   bash setup-leaderboard.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

WRANGLER_TOML="wrangler.toml"
ONLINE_CONFIG="../scripts/online_config.gd"

echo "==> Wave Defence leaderboard API setup"
echo "    Working in: $SCRIPT_DIR"
echo

if ! command -v npm >/dev/null 2>&1; then
  echo "ERROR: npm not found. Install Node.js from https://nodejs.org/ then re-run."
  exit 1
fi

echo "==> 1/5 npm install"
npm install

echo
echo "==> 2/5 Cloudflare login (browser will open — approve access)"
npx wrangler login

echo
echo "==> 3/5 Create KV namespace LEADERBOARD_KV (if needed)"
if grep -qE '^\[\[kv_namespaces\]\]' "$WRANGLER_TOML" && grep -qE '^id = "[^"]+"' "$WRANGLER_TOML"; then
  echo "    KV binding already present in wrangler.toml — skipping create."
else
  CREATE_OUT="$(npx wrangler kv namespace create LEADERBOARD_KV 2>&1)" || true
  echo "$CREATE_OUT"
  KV_ID="$(printf '%s\n' "$CREATE_OUT" | sed -n 's/.*"id": "\([^"]*\)".*/\1/p' | head -n1)"
  if [[ -z "$KV_ID" ]]; then
    KV_ID="$(printf '%s\n' "$CREATE_OUT" | sed -n 's/.*id[=: ]["'\'']*\([a-f0-9]\{32\}\)["'\'']*.*/\1/p' | head -n1)"
  fi
  if [[ -z "$KV_ID" ]]; then
    echo
    echo "Could not auto-detect KV id. Paste it from the output above:"
    read -r -p "KV id: " KV_ID
  fi
  if [[ -z "$KV_ID" ]]; then
    echo "ERROR: no KV id — cannot continue."
    exit 1
  fi
  # Strip commented placeholder block, then append a real binding.
  TMP="$(mktemp)"
  sed '/^# \[\[kv_namespaces\]\]/,/^# id = "YOUR_KV_NAMESPACE_ID"/d' "$WRANGLER_TOML" >"$TMP"
  if ! grep -qE '^\[\[kv_namespaces\]\]' "$TMP"; then
    cat >>"$TMP" <<EOF

[[kv_namespaces]]
binding = "LEADERBOARD_KV"
id = "$KV_ID"
EOF
  else
    # Update existing id line if present.
    if grep -qE '^id = "' "$TMP"; then
      sed -i.bak "s/^id = \".*\"/id = \"$KV_ID\"/" "$TMP"
      rm -f "$TMP.bak"
    else
      cat >>"$TMP" <<EOF

[[kv_namespaces]]
binding = "LEADERBOARD_KV"
id = "$KV_ID"
EOF
    fi
  fi
  mv "$TMP" "$WRANGLER_TOML"
  echo "    Wrote KV id into wrangler.toml: $KV_ID"
fi

echo
echo "==> 4/5 Store GitHub token as Worker secret"
echo "    When prompted, paste your PAT and press Enter."
echo "    (Fine-grained Contents: Read and write on WaveDefence, or classic 'repo')"
echo "    The token is sent to Cloudflare only — not printed or saved in this repo."
npx wrangler secret put GITHUB_TOKEN

echo
echo "==> 5/5 Deploy Worker"
DEPLOY_OUT="$(npx wrangler deploy 2>&1)"
echo "$DEPLOY_OUT"

WORKER_URL="$(printf '%s\n' "$DEPLOY_OUT" | sed -n 's|.*\(https://[a-zA-Z0-9._-]*\.workers\.dev\).*|\1|p' | head -n1)"
WORKER_URL="${WORKER_URL%/}"

echo
echo "========================================"
if [[ -n "$WORKER_URL" ]]; then
  echo "Worker URL: $WORKER_URL"
  echo
  echo "Next: put that URL into scripts/online_config.gd:"
  echo "  const API_BASE_URL := \"$WORKER_URL\""
  echo
  if [[ -f "$ONLINE_CONFIG" ]]; then
    read -r -p "Update online_config.gd for you now? [y/N] " ANSWER
    if [[ "${ANSWER:-}" =~ ^[Yy]$ ]]; then
      if grep -q 'const API_BASE_URL :=' "$ONLINE_CONFIG"; then
        sed -i.bak "s|const API_BASE_URL := \".*\"|const API_BASE_URL := \"$WORKER_URL\"|" "$ONLINE_CONFIG"
        rm -f "$ONLINE_CONFIG.bak"
        echo "Updated $ONLINE_CONFIG"
      else
        echo "Could not find API_BASE_URL in $ONLINE_CONFIG — set it manually."
      fi
    fi
  fi
  echo
  echo "Smoke test: open  ${WORKER_URL}/leaderboard"
else
  echo "Deploy finished, but could not parse the workers.dev URL."
  echo "Copy it from the deploy output above into scripts/online_config.gd → API_BASE_URL"
fi
echo
echo "Then rebuild/export the game and push so clients can upload scores."
echo "Done."
