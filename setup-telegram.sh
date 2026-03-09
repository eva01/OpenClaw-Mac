#!/usr/bin/env bash
# setup-telegram.sh — Automate OpenClaw Telegram channel configuration
#
# Usage:
#   TELEGRAM_BOT_TOKEN="123:abc" bash setup-telegram.sh
#
# Or pass flags:
#   bash setup-telegram.sh --token "123:abc" [--dm-policy open] [--require-mention false]

set -euo pipefail

# ── Defaults ──────────────────────────────────────────────────────────────────
DM_POLICY="pairing"
REQUIRE_MENTION="true"
CONFIG_FILE="${OPENCLAW_CONFIG:-$HOME/.openclaw/openclaw.json}"

# ── Parse flags ───────────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --token)         TELEGRAM_BOT_TOKEN="$2"; shift 2 ;;
    --dm-policy)     DM_POLICY="$2";          shift 2 ;;
    --require-mention) REQUIRE_MENTION="$2";  shift 2 ;;
    --config)        CONFIG_FILE="$2";        shift 2 ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

# ── Validate ──────────────────────────────────────────────────────────────────
if [[ -z "${TELEGRAM_BOT_TOKEN:-}" ]]; then
  echo "Error: TELEGRAM_BOT_TOKEN is not set."
  echo "Usage: TELEGRAM_BOT_TOKEN='123:abc' bash setup-telegram.sh"
  exit 1
fi

if [[ ! "$TELEGRAM_BOT_TOKEN" =~ ^[0-9]+:.+ ]]; then
  echo "Warning: Token format looks unusual (expected: 123456789:ABCdef...)"
fi

# ── Verify bot token with Telegram API ────────────────────────────────────────
echo "Verifying bot token with Telegram..."
RESPONSE=$(curl -sf "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/getMe" || true)
if [[ -z "$RESPONSE" ]]; then
  echo "Error: Could not reach Telegram API. Check your token and internet connection."
  exit 1
fi

BOT_USERNAME=$(echo "$RESPONSE" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['result']['username'])" 2>/dev/null || echo "unknown")
BOT_ID=$(echo "$RESPONSE"       | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['result']['id'])"       2>/dev/null || echo "unknown")

echo "Bot verified: @${BOT_USERNAME} (ID: ${BOT_ID})"

# ── Merge config ──────────────────────────────────────────────────────────────
echo "Updating ${CONFIG_FILE}..."

python3 - <<EOF
import json, os, sys

config_file = "${CONFIG_FILE}"
token       = "${TELEGRAM_BOT_TOKEN}"
dm_policy   = "${DM_POLICY}"
require_mention = "${REQUIRE_MENTION}" == "true"

# Load existing config or start fresh
if os.path.exists(config_file):
    with open(config_file) as f:
        config = json.load(f)
else:
    os.makedirs(os.path.dirname(config_file), exist_ok=True)
    config = {}

# Deep-merge telegram section
config.setdefault("channels", {})
config["channels"]["telegram"] = {
    "enabled": True,
    "botToken": token,
    "dmPolicy": dm_policy,
    "groups": {
        "*": {
            "requireMention": require_mention
        }
    }
}

with open(config_file, "w") as f:
    json.dump(config, f, indent=2)
    f.write("\n")

print(f"Config written to {config_file}")
EOF

# ── Restart gateway ───────────────────────────────────────────────────────────
if command -v openclaw &>/dev/null; then
  echo "Restarting OpenClaw gateway..."
  openclaw gateway restart
  echo ""
  openclaw gateway status
else
  echo "openclaw CLI not found — skipping gateway restart."
  echo "Run 'openclaw gateway restart' manually to apply changes."
fi

echo ""
echo "Done. Next steps:"
echo "  1. Open Telegram and start a DM with @${BOT_USERNAME}"
echo "  2. Click Start (or send /start)"
if [[ "$DM_POLICY" == "pairing" ]]; then
echo "  3. Send the pairing code shown in the chat"
echo "  4. Approve it: openclaw pairing list telegram"
echo "              openclaw pairing approve telegram <code>"
else
echo "  3. Start chatting — dm-policy is 'open', no pairing required"
fi
