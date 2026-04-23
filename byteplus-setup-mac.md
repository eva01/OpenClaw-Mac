<!-- byteplus-setup-mac.md — Detailed BytePlus Coding Plan + OpenClaw setup for macOS -->
<!-- Human summary: Full step-by-step macOS guide. Covers Xcode CLT, Homebrew, Node, jq, OpenClaw
     install, BytePlus provider config, gateway setup, and optional Gemini embeddings, gog skill,
     and model benchmarking. For cross-platform quick setup, use README.md instead. -->

CONTEXT: AI agent executing this file. Connect OpenClaw to BytePlus Coding Plan on macOS.
Run each section in order using bash or zsh. Skip sections whose GUARD check already passes.
Config: ~/.openclaw/openclaw.json. API key is written directly into provider config — no shell profile changes needed.

CONSTRAINTS:
- platform: macOS only (Apple Silicon or Intel)
- shell: zsh / bash
- non_interactive: true — all blocks run without prompts unless marked PAUSE
- pause_policy: PAUSE blocks require human action; agent stops, shows instruction, waits for confirmation
- timeoutSeconds: 600

## MODELS

| id | name | context | max tokens |
|----|------|---------|------------|
| `Kimi-K2.5` | Kimi K2.5 | 256k | 32k |
| `glm-4.7` | GLM 4.7 | 200k | 128k |
| `dola-seed-2.0-pro` | Dola Seed 2.0 Pro | 256k | 128k |
| `dola-seed-2.0-lite` | Dola Seed 2.0 Lite | 256k | 128k |

Default: `Kimi-K2.5` — Base URL: `https://ark.ap-southeast.bytepluses.com/api/coding/v3` (fixed)

---

## STEP 1 — SYSTEM DETECTION

```bash
[[ "$(uname -s)" == "Darwin" ]] || { echo "FAIL: not macOS — use byteplus-setup-windows.md"; exit 1; }
echo "PASS: macOS $(sw_vers -productVersion) ($(uname -m))"

# Xcode CLT
xcode-select -p &>/dev/null \
  && echo "PASS: Xcode CLT — $(xcode-select -p)" \
  || echo "FAIL: Xcode CLT not installed — see PAUSE below"

# Homebrew
command -v brew &>/dev/null \
  && echo "PASS: brew $(brew --version | head -1)" \
  || echo "INFO: Homebrew not installed — Step 2 will install"

# Node
command -v node &>/dev/null \
  && echo "PASS: node=$(node --version)" \
  || echo "INFO: node not found — Step 2 will install"

# jq
command -v jq &>/dev/null && echo "PASS: jq=$(jq --version)" || echo "INFO: jq not found — Step 2 will install"

# OpenClaw
command -v openclaw &>/dev/null \
  && echo "PASS: openclaw=$(openclaw --version 2>/dev/null || echo installed)" \
  || echo "INFO: openclaw not installed — Step 3 will install"

# Gateway (guard: only check if openclaw is present)
if command -v openclaw &>/dev/null; then
  openclaw gateway status 2>/dev/null | grep -qi "running" \
    && echo "PASS: gateway running" || echo "INFO: gateway not running — Step 4 will start"
else
  echo "INFO: gateway check skipped — openclaw not installed yet"
fi

# Port
lsof -i :18789 | grep -q LISTEN \
  && echo "WARN: port 18789 in use — kill before openclaw onboard" \
  || echo "PASS: port 18789 free"

# Config
[[ -f ~/.openclaw/openclaw.json ]] && echo "PASS: config exists" || echo "INFO: config not found — Step 5 will create"
```

If `FAIL: Xcode CLT not installed`:

PAUSE: Run the following in Terminal, click Install in the dialog, wait (~5 min), then tell the agent to continue:
```
xcode-select --install
```

If no dialog appears (headless / MDM Mac):
```bash
CLT=$(softwareupdate -l 2>&1 | grep -i "command line tools" | awk -F'*' '{print $2}' | xargs)
[[ -n "$CLT" ]] \
  && softwareupdate -i "$CLT" --verbose --agree-to-license && echo "PASS: Xcode CLT installed" \
  || echo "INFO: download manually (Apple ID required): https://developer.apple.com/download/all/?q=command+line+tools"
```

---

## STEP 2 — PREREQUISITES

```bash
# Homebrew
if command -v brew &>/dev/null; then
  echo "SKIP: brew already installed"
else
  NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  if [[ -f /opt/homebrew/bin/brew ]]; then eval "$(/opt/homebrew/bin/brew shellenv)"
  elif [[ -f /usr/local/bin/brew ]]; then eval "$(/usr/local/bin/brew shellenv)"; fi
  command -v brew &>/dev/null && echo "PASS: brew installed" || { echo "FAIL: Homebrew install failed"; exit 1; }
fi

# Node
if command -v node &>/dev/null; then
  echo "SKIP: node already installed — $(node --version)"
else
  brew install node
  command -v node &>/dev/null || { echo "FAIL: node install failed"; exit 1; }
fi
NODE_MAJOR=$(node --version | sed 's/v//' | cut -d. -f1)
[[ $NODE_MAJOR -ge 22 ]] && echo "PASS: node=$(node --version)" || echo "WARN: node=$(node --version) — recommend >=22.14; upgrade: brew upgrade node"

# jq
if command -v jq &>/dev/null; then
  echo "SKIP: jq already installed — $(jq --version)"
else
  brew install jq
  command -v jq &>/dev/null && echo "PASS: jq=$(jq --version)" || { echo "FAIL: jq install failed"; exit 1; }
fi
```

---

## STEP 3 — INSTALL OPENCLAW

```bash
if command -v openclaw &>/dev/null; then
  echo "SKIP: openclaw already installed — $(openclaw --version 2>/dev/null || echo version unknown)"
else
  curl -fsSL https://openclaw.ai/install.sh | bash
  if ! command -v openclaw &>/dev/null; then
    echo "INFO: retrying with sharp fix..."
    SHARP_IGNORE_GLOBAL_LIBVIPS=1 npm install -g openclaw@latest
  fi
  command -v openclaw &>/dev/null \
    && echo "PASS: openclaw installed — $(openclaw --version 2>/dev/null)" \
    || { echo "FAIL: install failed — check node version (>=22.14 required)"; exit 1; }
fi
```

If `openclaw` not found after install:
```bash
export PATH="$(npm prefix -g)/bin:$PATH"
echo 'export PATH="$(npm prefix -g)/bin:$PATH"' >> ~/.zshrc
```

---

## STEP 4 — FIRST-TIME ONBOARDING

Skip this step if the gateway is already running.

```bash
openclaw gateway status 2>/dev/null | grep -qi "running" && { echo "SKIP: gateway already running"; exit 0; }
lsof -i :18789 | grep -q LISTEN \
  && { echo "FAIL: port 18789 in use — kill it first: sudo lsof -i :18789"; exit 1; } \
  || echo "PASS: port 18789 free"
```

PAUSE: Run the onboarding wizard in Terminal:
```
openclaw onboard --install-daemon
```
Prompts:
1. Auth — skip cloud API keys (BytePlus added in Step 5)
2. Gateway port — press Enter for default 18789
3. Gateway bind — choose loopback
4. Install daemon — yes (LaunchAgent, auto-starts on login)

```bash
openclaw gateway status 2>&1 | grep -qi "running" \
  && echo "PASS: gateway running" \
  || { echo "FAIL: gateway not running — run: openclaw doctor"; exit 1; }
```

---

## STEP 5 — CONFIGURE BYTEPLUS

PAUSE: Ask the user for their BytePlus Coding Plan API key (from the BytePlus Coding Plan console). Then substitute it below as `BYTEPLUS_KEY` and run the block.

```bash
BYTEPLUS_KEY="your-api-key-here"    # replace with actual key
BYTEPLUS_BASE="https://ark.ap-southeast.bytepluses.com/api/coding/v3"

# Guard
[[ "$BYTEPLUS_KEY" == "your-api-key-here" || -z "$BYTEPLUS_KEY" ]] && { echo "FAIL: BYTEPLUS_KEY placeholder not replaced"; exit 1; }

mkdir -p ~/.openclaw
[[ -f ~/.openclaw/openclaw.json ]] || echo '{}' > ~/.openclaw/openclaw.json

# Validate key and discover models
echo "INFO: validating key and discovering models..."
MODELS_JSON=$(curl -s "$BYTEPLUS_BASE/models" -H "Authorization: Bearer $BYTEPLUS_KEY")
if echo "$MODELS_JSON" | jq -e '.data' &>/dev/null; then
  echo "INFO: available models:"
  echo "$MODELS_JSON" | jq -r '.data[].id' | sed 's/^/  /'
  MODEL_DEFAULT=$(echo "$MODELS_JSON" | jq -r '[.data[].id | select(test("Kimi-K2.5|kimi|K2.5"; "i"))] | first // "Kimi-K2.5"')
  MODELS_ARRAY=$(echo "$MODELS_JSON" | jq '[.data[] | {
    "id": .id,
    "name": .id,
    "reasoning": false,
    "input": ["text"],
    "cost": {"input":0,"output":0,"cacheRead":0,"cacheWrite":0},
    "contextWindow": (.context_length // 131072),
    "maxTokens": (.max_completion_tokens // 32768)
  }]')
  echo "PASS: key valid — default model=$MODEL_DEFAULT"
else
  echo "WARN: could not query /models — using hardcoded list"
  MODEL_DEFAULT="Kimi-K2.5"
  MODELS_ARRAY='[
    {"id":"Kimi-K2.5",         "name":"Kimi K2.5",         "reasoning":false,"input":["text"],        "cost":{"input":0,"output":0,"cacheRead":0,"cacheWrite":0},"contextWindow":262144,"maxTokens":32768},
    {"id":"glm-4.7",           "name":"GLM 4.7",            "reasoning":false,"input":["text"],        "cost":{"input":0,"output":0,"cacheRead":0,"cacheWrite":0},"contextWindow":200000,"maxTokens":131072},
    {"id":"dola-seed-2.0-pro", "name":"Dola Seed 2.0 Pro", "reasoning":false,"input":["text","image"],"cost":{"input":0,"output":0,"cacheRead":0,"cacheWrite":0},"contextWindow":262144,"maxTokens":131072},
    {"id":"dola-seed-2.0-lite","name":"Dola Seed 2.0 Lite","reasoning":false,"input":["text","image"],"cost":{"input":0,"output":0,"cacheRead":0,"cacheWrite":0},"contextWindow":262144,"maxTokens":131072}
  ]'
fi

# Write config — literal key and URL (template vars don't expand in provider config)
PATCH=$(jq -n \
  --arg key "$BYTEPLUS_KEY" \
  --arg base "$BYTEPLUS_BASE" \
  --arg default "byteplus/$MODEL_DEFAULT" \
  --argjson models "$MODELS_ARRAY" \
  '{
    "models": {
      "mode": "merge",
      "providers": {
        "byteplus": {
          "baseUrl": $base,
          "api": "openai-completions",
          "apiKey": $key,
          "models": $models
        }
      }
    },
    "agents": {
      "defaults": {
        "model": { "primary": $default },
        "timeoutSeconds": 600
      }
    }
  }')

echo "$PATCH" > /tmp/byteplus-patch.json
jq -s '.[0] * .[1]' ~/.openclaw/openclaw.json /tmp/byteplus-patch.json > /tmp/openclaw-merged.json \
  && mv /tmp/openclaw-merged.json ~/.openclaw/openclaw.json \
  && chmod 600 ~/.openclaw/openclaw.json \
  && echo "PASS: config written (permissions: 600)" \
  || { echo "FAIL: config write failed"; exit 1; }
rm -f /tmp/byteplus-patch.json

# Verify
jq -r '.models.providers.byteplus.apiKey // empty' ~/.openclaw/openclaw.json | grep -q . \
  && echo "PASS: API key present in provider config" \
  || echo "FAIL: API key missing"
```

---

## STEP 6 — RESTART GATEWAY

```bash
openclaw gateway restart && sleep 2

STATUS=$(openclaw gateway status 2>&1)
if echo "$STATUS" | grep -qi "running"; then
  echo "PASS: gateway running"
else
  echo "FAIL: gateway not running — run: openclaw doctor"
  echo "$STATUS"
  exit 1
fi
```

---

## STEP 7 — TEST

```bash
MP=$(jq -r '.agents.defaults.model.primary' ~/.openclaw/openclaw.json)
echo "INFO: default model = $MP"

# Via OpenClaw
echo "INFO: testing via OpenClaw..."
openclaw infer model run --model "$MP" --prompt "Say hi." 2>&1

# All models via OpenClaw
echo "INFO: testing all models..."
jq -r '.models.providers.byteplus.models[].id' ~/.openclaw/openclaw.json | while read -r model; do
  echo -n "byteplus/$model: "
  openclaw infer model run --model "byteplus/$model" --prompt "Say hi." 2>&1 | tail -1
done

# Direct API test (bypasses OpenClaw — isolates key/URL issues)
echo "INFO: direct API test..."
KEY=$(jq -r '.models.providers.byteplus.apiKey' ~/.openclaw/openclaw.json)
BASE=$(jq -r '.models.providers.byteplus.baseUrl' ~/.openclaw/openclaw.json)
MODEL=$(jq -r '.models.providers.byteplus.models[0].id' ~/.openclaw/openclaw.json)

curl -s -X POST "$BASE/chat/completions" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $KEY" \
  -d "{\"model\":\"$MODEL\",\"messages\":[{\"role\":\"user\",\"content\":\"Say hi.\"}],\"max_tokens\":50,\"stream\":false}" \
  | jq -r '.choices[0].message.content // .error.message // .'
```

---

## OPTIONAL STEP 8 — GEMINI EMBEDDINGS

OpenClaw uses an embedding provider for semantic memory search. Add your Gemini API key to enable it.

PAUSE: Ask the user for their Google Gemini API key (from Google AI Studio: https://aistudio.google.com/apikey). Then substitute below and run.

```bash
GEMINI_KEY="your-gemini-key-here"   # replace with actual key
[[ "$GEMINI_KEY" == "your-gemini-key-here" || -z "$GEMINI_KEY" ]] && { echo "FAIL: GEMINI_KEY placeholder not replaced"; exit 1; }

jq --arg gkey "$GEMINI_KEY" '. * {"env": {"GEMINI_API_KEY": $gkey}}' \
  ~/.openclaw/openclaw.json > /tmp/oc-gemini.json \
  && mv /tmp/oc-gemini.json ~/.openclaw/openclaw.json \
  && echo "PASS: Gemini key written to env section" \
  || { echo "FAIL: config write failed"; exit 1; }

openclaw gateway restart && sleep 2
openclaw memory status --deep 2>&1 \
  && echo "PASS: memory/embeddings ready" \
  || echo "WARN: memory status check failed — run: openclaw doctor"
```

---

## OPTIONAL STEP 9 — GOG SKILL (GOOGLE WORKSPACE)

Gives OpenClaw access to Google Calendar, Drive, Docs, Sheets, and Gmail.

### Install gogcli

```bash
brew install gogcli 2>/dev/null || {
  echo "WARN: gogcli not in default taps — trying direct install"
  brew tap openclaw/tools 2>/dev/null && brew install gogcli \
    || echo "FAIL: gogcli install failed — check https://docs.openclaw.ai/skills/gog for install instructions"
}
command -v gog &>/dev/null && echo "PASS: gog $(gog --version 2>/dev/null)" || echo "FAIL: gog not found after install"
```

### Set up OAuth credentials

PAUSE: Complete the following in Google Cloud Console, then tell the agent to continue:
1. Go to **APIs & Services → Credentials** → Create OAuth 2.0 Client ID (Desktop app type)
2. Enable: Google Calendar, Drive, Docs, Sheets, Gmail APIs
3. Go to **OAuth consent screen → Test users** → add your Google account email
4. Download the credentials JSON file
5. Run: `gog auth credentials set /path/to/client_secret_*.json`

### Authenticate

PAUSE: Run the following, sign in via the browser that opens, then tell the agent to continue:
```
gog auth add your-google-email@gmail.com
```

```bash
# Verify
gog auth list 2>&1 | grep -q "@" && echo "PASS: gog authenticated" || echo "FAIL: gog auth not set up"
gog calendar list 2>&1 | head -3
openclaw skills info gog 2>&1 | grep -i "ready\|error"
```

---

## OPTIONAL STEP 10 — BENCHMARK ALL MODELS

Measures raw API throughput per model (bypasses OpenClaw overhead). Runs in parallel, bounded to 5 concurrent requests to avoid rate limiting.

```bash
KEY=$(jq -r '.models.providers.byteplus.apiKey' ~/.openclaw/openclaw.json)
BASE=$(jq -r '.models.providers.byteplus.baseUrl' ~/.openclaw/openclaw.json)
PROMPT='Write a fizzbuzz function in Python.'

echo "Benchmarking BytePlus models (parallel, max 5 concurrent)..."
echo "---"

jq -r '.models.providers.byteplus.models[].id' ~/.openclaw/openclaw.json | xargs -P 5 -I{} bash -c '
  model="{}"
  t0=$(python3 -c "import time; print(time.time())")
  RESP=$(curl -sf -X POST "$1/chat/completions" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $2" \
    -d "{\"model\":\"$model\",\"messages\":[{\"role\":\"user\",\"content\":\"$3\"}],\"max_tokens\":200,\"stream\":false}" \
    2>/dev/null)
  t1=$(python3 -c "import time; print(time.time())")
  if [[ -n "$RESP" ]]; then
    tokens=$(echo "$RESP" | jq -r ".usage.completion_tokens // 0")
    elapsed=$(python3 -c "print(round(($t1 - $t0)*1000))")
    tps=$(python3 -c "print(round($tokens/($t1-$t0),1)) if $tokens > 0 else \"?\"")
    printf "%-25s | %6sms | %s tokens | %s tok/s\n" "$model" "$elapsed" "$tokens" "$tps"
  else
    printf "%-25s | FAIL\n" "$model"
  fi
' _ "$BASE" "$KEY" "$PROMPT"
```

---

## VERIFY

```bash
command -v openclaw &>/dev/null && echo "PASS: openclaw" || echo "FAIL: openclaw not found"
jq empty ~/.openclaw/openclaw.json 2>/dev/null && echo "PASS: config valid JSON" || echo "FAIL: invalid JSON"
KEY=$(jq -r '.models.providers.byteplus.apiKey // empty' ~/.openclaw/openclaw.json)
[[ -n "$KEY" ]] && echo "PASS: API key in provider config" || echo "FAIL: API key missing"
BASE=$(jq -r '.models.providers.byteplus.baseUrl // empty' ~/.openclaw/openclaw.json)
echo "INFO: baseUrl=$BASE"
openclaw gateway status 2>&1 | grep -qi "running" && echo "PASS: gateway running" || echo "FAIL: not running"
```

---

## UPDATE

```bash
openclaw doctor      # check for issues first
openclaw update      # built-in updater
npm install -g openclaw@latest  # fallback if openclaw update unavailable
openclaw gateway restart
openclaw gateway status
```

---

## TROUBLESHOOTING

| symptom | cause | fix |
|---------|-------|-----|
| `openclaw` not found after install | PATH not updated | `export PATH="$(npm prefix -g)/bin:$PATH"` |
| 401 from API | key wrong or expired | regenerate in BytePlus Coding Plan console |
| 403 from API | region lock | BytePlus `ap-southeast` requires APAC region — try VPN |
| gateway not running | config invalid JSON | `jq . ~/.openclaw/openclaw.json` |
| inference timeout | timeout too low | confirm `timeoutSeconds: 600` at `agents.defaults` |
| sharp build error | libvips conflict | `SHARP_IGNORE_GLOBAL_LIBVIPS=1 npm install -g openclaw@latest` |
| gog not found | tap not available | check `https://docs.openclaw.ai/skills/gog` |
| memory status fails | Gemini key missing | add `GEMINI_API_KEY` to `env` section, restart gateway |

```bash
openclaw doctor
jq . ~/.openclaw/openclaw.json
openclaw gateway status
```

---

## UNINSTALL

### Remove BytePlus provider only

```bash
jq '
  del(.models.providers.byteplus) |
  del(.agents.defaults.model) |
  if .models.providers == {} then del(.models.providers) else . end
' ~/.openclaw/openclaw.json > /tmp/no-byteplus.json \
  && mv /tmp/no-byteplus.json ~/.openclaw/openclaw.json \
  && echo "PASS: BytePlus removed from config"
openclaw gateway restart
```

### Full OpenClaw uninstall

```bash
launchctl bootout gui/$(id -u) ~/Library/LaunchAgents/ai.openclaw.gateway.plist 2>/dev/null || true
rm -f ~/Library/LaunchAgents/ai.openclaw.gateway.plist
npm uninstall -g openclaw && echo "PASS: openclaw removed"
rm -rf ~/.openclaw && echo "PASS: config removed"
```
