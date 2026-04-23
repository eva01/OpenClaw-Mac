<!-- setup-telegram.md — OpenClaw Telegram channel setup (Apple Silicon Mac) -->
<!-- Human summary: Connects OpenClaw to a Telegram bot on macOS. Validates the bot token against
     the Telegram API, merges the channel config into ~/.openclaw/openclaw.json, and restarts the
     gateway. Handles dmPolicy, groupPolicy, allowFrom, and exec approvals.
     Automated option: TELEGRAM_BOT_TOKEN=... bash setup-telegram.sh -->

CONTEXT: AI agent executing this file. Configure OpenClaw to accept messages via a Telegram bot.
Prereq: OpenClaw must already be installed and the gateway running before starting.
Config: `~/.openclaw/openclaw.json`.

CONSTRAINTS:
- platform: macOS — run all blocks in bash/zsh
- non_interactive: true — run unattended unless marked PAUSE
- pause_policy: PAUSE blocks require the human to act; agent stops and waits for confirmation
- prereq: OpenClaw installed + gateway running (verify with `openclaw gateway status`)

---

## STEP 1 — CREATE TELEGRAM BOT

PAUSE: The bot must be created manually in Telegram. Do the following, then tell the agent to continue:

1. Open Telegram and search for **@BotFather**
2. Send `/newbot`
3. Follow the prompts to choose a name and username
4. Copy the bot token (format: `123456789:ABCdef...`)
5. **If you want the bot to receive group messages without being @mentioned:**
   - Send `/setprivacy` to @BotFather → select your bot → choose **Disable**
   - (Skip this if you only want the bot to respond when @mentioned in groups)

---

## STEP 2 — VALIDATE TOKEN + WRITE CONFIG

Before running this step, confirm OpenClaw is installed and the gateway is running:
```bash
command -v openclaw &>/dev/null || { echo "FAIL: openclaw not installed — complete README.md setup first"; exit 1; }
openclaw gateway status 2>&1 | grep -qi "running" || { echo "FAIL: gateway not running — run: openclaw gateway restart"; exit 1; }
```

PAUSE: Ask the user for the following, then substitute into the block below before running:

1. **BOT_TOKEN** — the bot token from @BotFather (format: `123456789:ABCdef...`)
2. **DM_POLICY** — how to handle direct messages:
   - `pairing` (default) — each new user must be approved via a pairing code
   - `open` — any Telegram user can DM the bot without approval
3. **GROUP_POLICY** — how to handle group/channel messages:
   - `open` (default) — accept group messages from anyone (bot must be added to the group)
   - `allowlist` — only accept group messages from user IDs in `allowFrom`
   - `disabled` — ignore all group messages

### Option A — automated script (recommended)

```bash
TELEGRAM_BOT_TOKEN="123456789:ABCdef..."    # replace with actual token
DM_POLICY="pairing"                         # or "open"
GROUP_POLICY="open"                         # or "allowlist" or "disabled"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TELEGRAM_BOT_TOKEN="$TELEGRAM_BOT_TOKEN" bash "$SCRIPT_DIR/setup-telegram.sh"
```

### Option B — manual config

```bash
BOT_TOKEN="123456789:ABCdef..."    # replace with actual token
DM_POLICY="pairing"               # or "open"
GROUP_POLICY="open"               # or "allowlist" or "disabled"

# Guard: ensure placeholder is replaced and token is not empty
[[ "$BOT_TOKEN" == "123456789:ABCdef..."* || -z "$BOT_TOKEN" ]] && { echo "FAIL: BOT_TOKEN not set — replace the placeholder"; exit 1; }

# Validate token with Telegram API
RESPONSE=$(curl -s "https://api.telegram.org/bot${BOT_TOKEN}/getMe" || true)
if [[ -z "$RESPONSE" ]]; then
  echo "FAIL: could not reach Telegram API — check internet connection"; exit 1
fi
OK=$(echo "$RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin).get('ok', False))" 2>/dev/null || echo "false")
if [[ "$OK" != "True" ]]; then
  DESC=$(echo "$RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin).get('description','unknown error'))" 2>/dev/null || echo "unknown error")
  echo "FAIL: Telegram rejected token — $DESC"; exit 1
fi
BOT_USERNAME=$(echo "$RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin)['result']['username'])" 2>/dev/null || echo "unknown")
BOT_ID=$(echo "$RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin)['result']['id'])" 2>/dev/null || echo "unknown")
echo "PASS: bot verified — @${BOT_USERNAME} (ID: ${BOT_ID})"

# Merge config
mkdir -p ~/.openclaw
[[ -f ~/.openclaw/openclaw.json ]] || echo '{}' > ~/.openclaw/openclaw.json

TG_PATCH=$(jq -n \
  --arg token "$BOT_TOKEN" \
  --arg dmp "$DM_POLICY" \
  --arg grp "$GROUP_POLICY" \
  '{
    "channels": {
      "telegram": {
        "enabled": true,
        "botToken": $token,
        "dmPolicy": $dmp,
        "groupPolicy": $grp,
        "groups": { "*": { "requireMention": true } }
      }
    }
  }')

# allowFrom ["*"] is required when dmPolicy is "open"
[[ "$DM_POLICY" == "open" ]] && TG_PATCH=$(echo "$TG_PATCH" | jq '.channels.telegram.allowFrom = ["*"]')

echo "$TG_PATCH" > /tmp/tg-patch.json
jq -s '.[0] * .[1]' ~/.openclaw/openclaw.json /tmp/tg-patch.json > /tmp/openclaw-merged.json \
  && mv /tmp/openclaw-merged.json ~/.openclaw/openclaw.json \
  && echo "PASS: Telegram config written" \
  || { echo "FAIL: config write failed"; exit 1; }
rm -f /tmp/tg-patch.json
```

---

## STEP 3 — RESTART GATEWAY

```bash
openclaw gateway restart && sleep 2
openclaw gateway status 2>&1 | grep -qi "running" \
  && echo "PASS: gateway running" \
  || { echo "FAIL: gateway not running — run: openclaw doctor"; exit 1; }
```

---

## STEP 4 — PAIR AND TEST

PAUSE: Complete pairing in Telegram before testing:

1. Open Telegram → search for **@YourBotUsername** → click **Start**
   - The bot cannot respond to you until you click Start (Telegram restriction)
2. If `dmPolicy` is `pairing`: the bot will reply with a pairing code — note it down
   - Pairing codes expire after **1 hour** — approve promptly

If `dmPolicy` is `pairing`, approve the pairing code:
```bash
openclaw pairing list telegram
openclaw pairing approve telegram <code>
```

Then send a test message to the bot in Telegram — it should respond via OpenClaw.

---

## OPTIONAL — FIND YOUR TELEGRAM USER ID

Required when using `groupPolicy: "allowlist"` or adding specific users to `allowFrom`.
Numeric IDs only — @usernames are silently ignored by OpenClaw.

### Method 1: via OpenClaw logs (no extra setup)

Send any message to your bot in Telegram, then:
```bash
openclaw logs --follow 2>&1 | grep -o '"from":{"id":[0-9]*' | head -5
```
Look for `"from":{"id":123456789}` — that number is your Telegram user ID.

### Method 2: via Telegram getUpdates API

```bash
# Send a message to your bot first, then:
curl -s "https://api.telegram.org/bot${BOT_TOKEN}/getUpdates" \
  | python3 -c "import sys,json; updates=json.load(sys.stdin)['result']; [print(u['message']['from']['id'], u['message']['from'].get('username','')) for u in updates if 'message' in u]"
```

### Add user ID to allowlist

```bash
jq '.channels.telegram.allowFrom = ["YOUR_NUMERIC_ID"]' ~/.openclaw/openclaw.json > /tmp/oc-tmp.json \
  && mv /tmp/oc-tmp.json ~/.openclaw/openclaw.json
openclaw gateway restart
```

---

## OPTIONAL — EXEC APPROVALS

OpenClaw can send approval requests to Telegram before executing agent actions (e.g., running code, modifying files). Users approve or deny via inline buttons.

```bash
jq '.channels.telegram.execApprovals = {"enabled": true, "timeoutSeconds": 60}' \
  ~/.openclaw/openclaw.json > /tmp/oc-tmp.json \
  && mv /tmp/oc-tmp.json ~/.openclaw/openclaw.json
openclaw gateway restart
```

---

## VERIFY

```bash
# Telegram config present and enabled
ENABLED=$(jq -r '.channels.telegram.enabled // empty' ~/.openclaw/openclaw.json 2>/dev/null)
[[ "$ENABLED" == "true" ]] \
  && echo "PASS: Telegram enabled in config" \
  || echo "FAIL: Telegram not configured (got: '${ENABLED:-empty}')"

# groupPolicy present (absence silently drops all group messages)
GRPP=$(jq -r '.channels.telegram.groupPolicy // empty' ~/.openclaw/openclaw.json 2>/dev/null)
[[ -n "$GRPP" ]] \
  && echo "PASS: groupPolicy = ${GRPP}" \
  || echo "WARN: groupPolicy not set — group messages will be silently dropped"

# Gateway running
openclaw gateway status 2>&1 | grep -qi "running" \
  && echo "PASS: gateway running" \
  || echo "FAIL: gateway not running"

# Pairing list
openclaw pairing list telegram
```

---

## TROUBLESHOOTING

| symptom | cause | fix |
|---------|-------|-----|
| Bot does not respond to DMs | user hasn't sent /start | Open bot in Telegram, tap **Start** |
| Pairing code never arrives | user hasn't sent /start | Send `/start` to the bot first |
| Pairing code expired | codes last 1 hour | Send `/start` again to get a new code |
| "You are not authorized" in DMs | dmPolicy is "open" but allowFrom missing | Add `"allowFrom": ["*"]` to telegram config |
| "You are not authorized" (specific user) | user ID not in allowFrom | Add numeric user ID to `allowFrom` (not @username) |
| Group messages not arriving | groupPolicy missing or wrong | Set `"groupPolicy": "open"` — absence silently drops all group messages |
| Group messages not arriving (no @mention) | BotFather privacy mode on | `/setprivacy` → your bot → Disable; restart gateway |
| Config path wrong | key in wrong location | Must be `channels.telegram`, NOT `plugins.entries.telegram` |
| Approval buttons not appearing | execApprovals not enabled | Add `"execApprovals": {"enabled": true}` to telegram config |

---

## UNINSTALL (remove Telegram only)

```bash
jq 'del(.channels.telegram)' ~/.openclaw/openclaw.json > /tmp/no-tg.json \
  && mv /tmp/no-tg.json ~/.openclaw/openclaw.json \
  && echo "PASS: Telegram config removed"
openclaw gateway restart
```
