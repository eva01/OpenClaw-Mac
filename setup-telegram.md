<!-- setup-telegram.md — OpenClaw Telegram channel setup (cross-platform) -->
<!-- Human summary: Connects OpenClaw to a Telegram bot. Validates the bot token against
     the Telegram API, merges the channel config into ~/.openclaw/openclaw.json, and
     restarts the gateway. Handles dmPolicy, groupPolicy, allowFrom, and exec approvals.
     Cross-platform: macOS (bash) and Windows (PowerShell). -->

CONTEXT: AI agent executing this file. Configure OpenClaw to accept messages via a Telegram bot.
Prereq: OpenClaw must already be installed and the gateway running before starting.
Run only the block matching your OS. Config: ~/.openclaw/openclaw.json.

CONSTRAINTS:
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
5. **If you want the bot to receive group messages without being mentioned:**
   - Send `/setprivacy` to @BotFather
   - Select your bot
   - Choose **Disable** — this allows the bot to see all group messages, not just `/commands`
   - (If you only want the bot to respond when @mentioned in groups, you can skip this)

---

## STEP 2 — VALIDATE TOKEN + WRITE CONFIG

Before running this step, confirm OpenClaw is installed and the gateway is running:
```bash
command -v openclaw &>/dev/null || { echo "FAIL: openclaw not installed — complete ilmu-ai-setup first"; exit 1; }
openclaw gateway status 2>&1 | grep -qi "running" || { echo "FAIL: gateway not running — run: openclaw gateway restart"; exit 1; }
```

PAUSE: Ask the user for the following, then substitute into the block below before running:

1. **BOT_TOKEN** — the bot token from @BotFather (format: `123456789:ABCdef...`)
2. **DM_POLICY** — how to handle direct messages:
   - `pairing` (default) — each new user must be approved via a pairing code
   - `open` — any Telegram user can DM the bot without approval
3. **GROUP_POLICY** — how to handle group/channel messages:
   - `open` (default) — accept group messages from anyone (bot must be added to the group)
   - `allowlist` — only accept group messages from user IDs listed in `allowFrom`
   - `disabled` — ignore all group messages

### macOS

```bash
# Set from user input:
BOT_TOKEN="123456789:ABCdef..."    # replace with actual token
DM_POLICY="pairing"               # or "open"
GROUP_POLICY="open"               # or "allowlist" or "disabled"

# Guard: ensure placeholders are replaced
[[ "$BOT_TOKEN" == "123456789:ABCdef..."* ]] && { echo "FAIL: BOT_TOKEN not set — replace the placeholder"; exit 1; }

# Validate token with Telegram API
RESPONSE=$(curl -sf "https://api.telegram.org/bot${BOT_TOKEN}/getMe" || true)
if [[ -z "$RESPONSE" ]]; then
  echo "FAIL: Could not reach Telegram API — check token and internet connection"
  exit 1
fi
BOT_USERNAME=$(echo "$RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin)['result']['username'])" 2>/dev/null || echo "unknown")
BOT_ID=$(echo "$RESPONSE"       | python3 -c "import sys,json; print(json.load(sys.stdin)['result']['id'])"       2>/dev/null || echo "unknown")
echo "PASS: bot verified — @${BOT_USERNAME} (ID: ${BOT_ID})"

# Merge config
mkdir -p ~/.openclaw
[[ -f ~/.openclaw/openclaw.json ]] || echo '{}' > ~/.openclaw/openclaw.json

# Build patch — allowFrom ["*"] is required when dmPolicy is "open"
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

if [[ "$DM_POLICY" == "open" ]]; then
  TG_PATCH=$(echo "$TG_PATCH" | jq '.channels.telegram.allowFrom = ["*"]')
fi

echo "$TG_PATCH" > /tmp/tg-patch.json
jq -s '.[0] * .[1]' ~/.openclaw/openclaw.json /tmp/tg-patch.json > /tmp/openclaw-merged.json \
  && mv /tmp/openclaw-merged.json ~/.openclaw/openclaw.json \
  && echo "PASS: Telegram config written" \
  || { echo "FAIL: config write failed"; exit 1; }
rm -f /tmp/tg-patch.json
```

### Windows

```powershell
# Set from user input:
$BOT_TOKEN    = "123456789:ABCdef..."   # replace with actual token
$DM_POLICY    = "pairing"              # or "open"
$GROUP_POLICY = "open"                 # or "allowlist" or "disabled"

# Guard: ensure placeholder is replaced
if ($BOT_TOKEN -like "123456789:ABCdef*" -or -not $BOT_TOKEN) {
  Write-Host "FAIL: BOT_TOKEN not set — replace the placeholder"; exit 1
}

# Validate token
try {
  $r = Invoke-RestMethod -Uri "https://api.telegram.org/bot${BOT_TOKEN}/getMe" -Method GET
  $BOT_USERNAME = $r.result.username
  $BOT_ID       = $r.result.id
  Write-Host "PASS: bot verified — @${BOT_USERNAME} (ID: ${BOT_ID})"
} catch {
  Write-Host "FAIL: Could not reach Telegram API — check token and internet connection"
  exit 1
}

# Config paths
$configDir  = "$env:USERPROFILE\.openclaw"
$configFile = "$configDir\openclaw.json"
if (-not (Test-Path $configDir))  { New-Item -ItemType Directory $configDir | Out-Null }
if (-not (Test-Path $configFile)) { '{}' | Set-Content -Encoding UTF8 $configFile }

# Static template (no user values — safe for single-quoted here-string)
@'
{
  "channels": {
    "telegram": {
      "enabled": true,
      "groups": { "*": { "requireMention": true } }
    }
  }
}
'@ | Set-Content -Encoding UTF8 "$env:TEMP\tg-static.json"

# Inject user values safely via jq --arg (handles special chars in token)
jq --arg token $BOT_TOKEN --arg dmp $DM_POLICY --arg grp $GROUP_POLICY `
  '.channels.telegram.botToken = $token | .channels.telegram.dmPolicy = $dmp | .channels.telegram.groupPolicy = $grp' `
  "$env:TEMP\tg-static.json" | Set-Content -Encoding UTF8 "$env:TEMP\tg-patch.json"

# If dmPolicy is "open", allowFrom ["*"] is required
if ($DM_POLICY -eq "open") {
  Get-Content "$env:TEMP\tg-patch.json" -Raw | `
    jq '.channels.telegram.allowFrom = ["*"]' | `
    Set-Content -Encoding UTF8 "$env:TEMP\tg-patch.json"
}

# Merge patch into existing config
jq -s '.[0] * .[1]' $configFile "$env:TEMP\tg-patch.json" | Set-Content -Encoding UTF8 "$env:TEMP\openclaw-merged.json"
if ($LASTEXITCODE -eq 0) {
  Move-Item -Force "$env:TEMP\openclaw-merged.json" $configFile
  Write-Host "PASS: Telegram config written"
} else { Write-Host "FAIL: config write failed"; exit 1 }
Remove-Item -EA SilentlyContinue "$env:TEMP\tg-static.json","$env:TEMP\tg-patch.json"
```

---

## STEP 3 — RESTART GATEWAY

### macOS
```bash
openclaw gateway restart && sleep 2
openclaw gateway status 2>&1 | grep -qi "running" \
  && echo "PASS: gateway running" \
  || { echo "FAIL: gateway not running — run: openclaw doctor"; exit 1; }
```

### Windows
```powershell
openclaw gateway restart; Start-Sleep 2
$s = openclaw gateway status 2>&1
if ($s -match "running") { Write-Host "PASS: gateway running" } else { Write-Host "FAIL: not running"; exit 1 }
```

---

## STEP 4 — PAIR AND TEST

PAUSE: Complete pairing in Telegram before testing:

1. Open Telegram → search for **@YourBotUsername** → click **Start**
   - The bot cannot respond to you until you click Start (Telegram restriction)
2. If `dmPolicy` is `pairing`: the bot will reply with a pairing code — note it down
   - Pairing codes expire after **1 hour** — approve promptly

If `dmPolicy` is `pairing`, approve the pairing code:

### macOS / Windows (same CLI)
```bash
openclaw pairing list telegram
openclaw pairing approve telegram <code>
```

Then send a test message to the bot in Telegram. It should respond via OpenClaw.

---

## OPTIONAL — FIND YOUR TELEGRAM USER ID

Required when using `groupPolicy: "allowlist"` or adding specific users to `allowFrom`.
Numeric IDs only — @usernames are silently ignored by OpenClaw.

### Method 1: via OpenClaw logs (no extra setup)

Send any message to your bot in Telegram, then:

```bash
# macOS
openclaw logs --follow 2>&1 | grep -o '"from":{"id":[0-9]*' | head -5
```

```powershell
# Windows
openclaw logs --follow 2>&1 | Select-String -Pattern '"from":\{"id":\d+'
```

Look for `"from":{"id":123456789}` — that number is your Telegram user ID.

### Method 2: via Telegram getUpdates API

```bash
# macOS — send a message to your bot first, then:
curl -s "https://api.telegram.org/bot${BOT_TOKEN}/getUpdates" \
  | python3 -c "import sys,json; updates=json.load(sys.stdin)['result']; [print(u['message']['from']['id'], u['message']['from'].get('username','')) for u in updates if 'message' in u]"
```

```powershell
# Windows
$updates = Invoke-RestMethod -Uri "https://api.telegram.org/bot${BOT_TOKEN}/getUpdates"
$updates.result | Where-Object { $_.message } | ForEach-Object { "$($_.message.from.id)  @$($_.message.from.username)" }
```

### Add user ID to allowlist

After getting the numeric ID, add it to config:

```bash
# macOS
jq '.channels.telegram.allowFrom = ["YOUR_NUMERIC_ID"]' ~/.openclaw/openclaw.json > /tmp/oc-tmp.json \
  && mv /tmp/oc-tmp.json ~/.openclaw/openclaw.json
openclaw gateway restart
```

```powershell
# Windows
jq '.channels.telegram.allowFrom = ["YOUR_NUMERIC_ID"]' "$env:USERPROFILE\.openclaw\openclaw.json" | `
  Set-Content -Encoding UTF8 "$env:TEMP\oc-tmp.json"
Move-Item -Force "$env:TEMP\oc-tmp.json" "$env:USERPROFILE\.openclaw\openclaw.json"
openclaw gateway restart
```

---

## OPTIONAL — EXEC APPROVALS

OpenClaw can send approval requests to Telegram before executing agent actions (e.g., running code, modifying files). Users approve or deny via inline buttons in Telegram.

Enable exec approvals in config:

```json
{
  "channels": {
    "telegram": {
      "execApprovals": {
        "enabled": true,
        "timeoutSeconds": 60
      }
    }
  }
}
```

Apply:

```bash
# macOS
jq '.channels.telegram.execApprovals = {"enabled": true, "timeoutSeconds": 60}' \
  ~/.openclaw/openclaw.json > /tmp/oc-tmp.json \
  && mv /tmp/oc-tmp.json ~/.openclaw/openclaw.json
openclaw gateway restart
```

```powershell
# Windows
jq '.channels.telegram.execApprovals = {"enabled": true, "timeoutSeconds": 60}' `
  "$env:USERPROFILE\.openclaw\openclaw.json" | Set-Content -Encoding UTF8 "$env:TEMP\oc-tmp.json"
Move-Item -Force "$env:TEMP\oc-tmp.json" "$env:USERPROFILE\.openclaw\openclaw.json"
openclaw gateway restart
```

---

## VERIFY

### macOS
```bash
# Telegram config present in file
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

### Windows
```powershell
$configFile = "$env:USERPROFILE\.openclaw\openclaw.json"
$enabled = jq -r '.channels.telegram.enabled // empty' $configFile
if ($enabled -eq "true") { Write-Host "PASS: Telegram enabled in config" } else { Write-Host "FAIL: not configured" }

$grpp = jq -r '.channels.telegram.groupPolicy // empty' $configFile
if ($grpp) { Write-Host "PASS: groupPolicy = $grpp" } else { Write-Host "WARN: groupPolicy not set — group messages will be silently dropped" }

$s = openclaw gateway status 2>&1
if ($s -match "running") { Write-Host "PASS: gateway running" } else { Write-Host "FAIL: gateway not running" }
openclaw pairing list telegram
```

---

## TROUBLESHOOTING

| symptom | cause | fix |
|---------|-------|-----|
| Bot does not respond to DMs | user hasn't sent /start | Open bot in Telegram, tap Start |
| Pairing code never arrives | user hasn't sent /start | Send `/start` to the bot first |
| Pairing code expired | codes last 1 hour | Send `/start` again to get a new code |
| "You are not authorized" error in DMs | dmPolicy is "open" but allowFrom missing | Add `"allowFrom": ["*"]` to telegram config |
| "You are not authorized" error (specific user) | user ID not in allowFrom | Add numeric user ID to `allowFrom` (not @username) |
| Group messages not arriving | groupPolicy missing or wrong | Set `"groupPolicy": "open"` — absence silently drops all group messages |
| Group messages not arriving (bot not mentioned) | BotFather privacy mode on | `/setprivacy` → your bot → Disable; restart gateway |
| Group messages from specific users blocked | groupPolicy is allowlist, user not in allowFrom | Add numeric Telegram user ID to `allowFrom` |
| Config path wrong | channels at wrong key | Must be `channels.telegram`, NOT `plugins.entries.telegram` |
| Approval buttons not appearing | execApprovals not enabled | Add `"execApprovals": {"enabled": true}` to telegram config |

---

## UNINSTALL (remove Telegram only)

### macOS
```bash
jq 'del(.channels.telegram)' ~/.openclaw/openclaw.json > /tmp/no-tg.json \
  && mv /tmp/no-tg.json ~/.openclaw/openclaw.json \
  && echo "PASS: Telegram config removed"
openclaw gateway restart
```

### Windows
```powershell
jq 'del(.channels.telegram)' "$env:USERPROFILE\.openclaw\openclaw.json" | Set-Content -Encoding UTF8 "$env:TEMP\no-tg.json"
Move-Item -Force "$env:TEMP\no-tg.json" "$env:USERPROFILE\.openclaw\openclaw.json"
Write-Host "PASS: Telegram config removed"
openclaw gateway restart
```
