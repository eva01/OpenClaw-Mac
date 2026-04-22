<!-- ilmu-ai-setup-mac.md — Detailed OpenClaw + ilmu.ai setup for macOS -->
<!-- Human summary: Full step-by-step guide for connecting OpenClaw to ilmu.ai on macOS
     (Apple Silicon or Intel). Covers Xcode CLT, Homebrew, Node, jq, OpenClaw install,
     API key stored securely in ~/.openclaw/openclaw.json (env section), gateway setup,
     and end-to-end test. No local model server required — cloud only.
     For cross-platform quick setup, use README.md instead. -->

CONTEXT: AI agent executing this file. Connect OpenClaw to ilmu.ai on macOS.
Run each section in order using bash or zsh. Skip sections whose GUARD check already passes.
Config: ~/.openclaw/openclaw.json. API key is stored in the config file — no shell profile changes needed.
Default shell assumed: zsh (~/.zshrc). Fish users: run bash blocks inside bash.

CONSTRAINTS:
- platform: macOS only (Apple Silicon or Intel)
- shell: zsh / bash
- non_interactive: true — all blocks run without prompts unless marked PAUSE
- pause_policy: PAUSE blocks require human action; agent stops, shows instruction, waits for confirmation
- api_key: stored in openclaw.json under env.ILMU_API_KEY — never in ~/.zshrc or dotfiles
- timeoutSeconds: 600

## MODELS

| id | name | context | max tokens |
|----|------|---------|------------|
| `nemo-super` | ILMU Nemo Super | 256k | 128k |
| `ilmu-nemo-nano` | ILMU Nemo Nano | 256k | 128k |

Default: `nemo-super` — Base URL: `https://api.ilmu.ai/v1`
Staging: set `BASE_URL` under `env` in openclaw.json (Step 5)

---

## STEP 1 — SYSTEM DETECTION

```bash
# macOS guard
[[ "$(uname -s)" == "Darwin" ]] || { echo "FAIL: not macOS — use ilmu-ai-setup-windows.md"; exit 1; }
echo "PASS: macOS $(sw_vers -productVersion) ($(uname -m))"

# Xcode CLT — required by Homebrew (provides git, make, and compiler toolchain)
xcode-select -p &>/dev/null \
  && echo "PASS: Xcode CLT — $(xcode-select -p)" \
  || echo "FAIL: Xcode CLT not installed — see PAUSE below"

# Homebrew
command -v brew &>/dev/null \
  && echo "PASS: brew $(brew --version | head -1)" \
  || echo "FAIL: Homebrew not installed — Step 2 will install"

# Node / npm
command -v node &>/dev/null \
  && echo "PASS: node=$(node --version) npm=$(npm --version)" \
  || echo "FAIL: node not found — Step 2 will install"

# jq
command -v jq &>/dev/null && echo "PASS: jq=$(jq --version)" || echo "FAIL: jq not found — Step 2 will install"

# OpenClaw
command -v openclaw &>/dev/null \
  && echo "PASS: openclaw=$(openclaw --version 2>/dev/null || echo installed)" \
  || echo "FAIL: openclaw not installed — Step 3 will install"

# Gateway
if command -v openclaw &>/dev/null; then
  openclaw gateway status 2>/dev/null | grep -qi "running" \
    && echo "PASS: gateway running" || echo "FAIL: gateway not running — Step 6 will start"
else
  echo "SKIP: gateway check skipped — openclaw not installed"
fi

# Port 18789 — must be free before onboarding
lsof -i :18789 | grep -q LISTEN \
  && echo "WARN: port 18789 in use — kill the process before running openclaw onboard" \
  || echo "PASS: port 18789 free"

# Config
[[ -f ~/.openclaw/openclaw.json ]] \
  && echo "PASS: config exists" || echo "FAIL: config not found — Step 5 will create"
```

If `FAIL: Xcode CLT not installed`:

PAUSE: Run the following in Terminal. A dialog will appear — click Install and wait (~5 min), then tell the agent to continue:
```
xcode-select --install
```

If the dialog does not appear (headless or MDM-managed Mac), use the `softwareupdate` CLI alternative:
```bash
CLT=$(softwareupdate -l 2>&1 | grep -i "command line tools" | awk -F'*' '{print $2}' | xargs)
if [[ -n "$CLT" ]]; then
  softwareupdate -i "$CLT" --verbose --agree-to-license && echo "PASS: Xcode CLT installed"
else
  echo "INFO: not listed in softwareupdate — download manually (Apple ID required):"
  echo "  https://developer.apple.com/download/all/?q=command+line+tools"
fi
```

Manual download (requires Apple ID sign-in): `https://developer.apple.com/download/all/?q=command+line+tools`

---

## STEP 2 — PREREQUISITES

### Homebrew

```bash
if command -v brew &>/dev/null; then
  echo "SKIP: brew already installed"
else
  NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  # Apply to current session
  if [[ -f /opt/homebrew/bin/brew ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  elif [[ -f /usr/local/bin/brew ]]; then
    eval "$(/usr/local/bin/brew shellenv)"
  fi
  command -v brew &>/dev/null && echo "PASS: brew installed" || { echo "FAIL: Homebrew install failed"; exit 1; }
fi
```

Note: Homebrew will install Xcode CLT automatically if not present — this may trigger an interactive dialog.
If that happens, click Install in the dialog and re-run this block after it finishes.

### Node

```bash
if command -v node &>/dev/null; then
  echo "SKIP: node already installed — $(node --version)"
else
  brew install node
  command -v node &>/dev/null || { echo "FAIL: node install failed"; exit 1; }
fi

# Verify version meets minimum requirement (>=22.14)
NODE_MAJOR=$(node --version | sed 's/v//' | cut -d. -f1)
NODE_MINOR=$(node --version | sed 's/v//' | cut -d. -f2)
if [[ $NODE_MAJOR -gt 22 ]] || [[ $NODE_MAJOR -eq 22 && $NODE_MINOR -ge 14 ]]; then
  echo "PASS: node=$(node --version) (meets >=22.14)"
else
  echo "WARN: node=$(node --version) — recommend >=22.14; upgrade: brew upgrade node"
fi
```

### jq

```bash
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
  echo "SKIP: openclaw already installed — $(openclaw --version 2>/dev/null || echo 'version unknown')"
else
  curl -fsSL https://openclaw.ai/install.sh | bash

  # Fallback: sharp build error on some systems
  if ! command -v openclaw &>/dev/null; then
    echo "INFO: retrying with sharp fix..."
    SHARP_IGNORE_GLOBAL_LIBVIPS=1 npm install -g openclaw@latest
  fi

  command -v openclaw &>/dev/null \
    && echo "PASS: openclaw installed — $(openclaw --version 2>/dev/null)" \
    || { echo "FAIL: install failed — check node version (>=22.14 required)"; exit 1; }
fi
```

If `openclaw` is not found after install:
```bash
# Add npm global bin to PATH for this session
export PATH="$(npm prefix -g)/bin:$PATH"
# Add permanently to ~/.zshrc:
echo 'export PATH="$(npm prefix -g)/bin:$PATH"' >> ~/.zshrc
```

---

## STEP 4 — FIRST-TIME ONBOARDING

Skip this step if the gateway is already running (`openclaw gateway status` shows running).

Before onboarding, confirm port 18789 is free:
```bash
lsof -i :18789 | grep -q LISTEN && echo "WARN: port 18789 in use — kill it first: sudo lsof -i :18789" || echo "PASS: port 18789 free"
```

PAUSE: OpenClaw requires an interactive setup wizard on first install. Run in Terminal:
```
openclaw onboard --install-daemon
```
Prompts:
1. Auth — skip cloud API keys for now (ilmu.ai added in Step 5)
2. Gateway port — press Enter for default 18789
3. Gateway bind — choose loopback
4. Install daemon — yes (auto-starts via LaunchAgent on login)

After the wizard:
```bash
openclaw gateway status
# Expected: Runtime: running, Listening: 127.0.0.1:18789
```
Tell the agent to continue once you see "running".

---

## STEP 5 — CONFIGURE ilmu.ai

The API key and base URL are stored in `~/.openclaw/openclaw.json` under `"env"`.
OpenClaw reads them at startup and injects them into the template variables in the provider config.

PAUSE: Ask the user for:
1. Their ilmu.ai API key (starts with `sk-`)
2. Base URL — use `https://api.ilmu.ai/v1` for production, or their staging URL

Use the values as `ILMU_KEY` and `ILMU_BASE` in the block below.

```bash
# Set from user input:
ILMU_KEY="sk-..."
ILMU_BASE="https://api.ilmu.ai/v1"

# Guard: fail if placeholder was not replaced
[[ "$ILMU_KEY" == "sk-..." || -z "$ILMU_KEY" ]] && { echo "FAIL: ILMU_KEY placeholder not replaced — set your actual sk- key"; exit 1; }
[[ "$ILMU_BASE" == "https://api.ilmu.ai/v1" ]] && echo "INFO: using production BASE_URL" || echo "INFO: using custom BASE_URL=$ILMU_BASE"

mkdir -p ~/.openclaw
[[ -f ~/.openclaw/openclaw.json ]] || echo '{}' > ~/.openclaw/openclaw.json

jq --arg key "$ILMU_KEY" --arg base "$ILMU_BASE" '. * {
  "env": {
    "ILMU_API_KEY": $key,
    "BASE_URL": $base
  },
  "agents": {
    "defaults": {
      "model": { "primary": "<ENDPOINT_ID:-custom-api-ilmu-ai>/nemo-super" },
      "models": {
        "<ENDPOINT_ID:-custom-api-ilmu-ai>/nemo-super":     { "alias": "nemo-super",  "streaming": false },
        "<ENDPOINT_ID:-custom-api-ilmu-ai>/ilmu-nemo-nano": { "alias": "nemo-nano",   "streaming": false }
      },
      "timeoutSeconds": 600
    }
  },
  "models": {
    "mode": "merge",
    "providers": {
      "<ENDPOINT_ID:-custom-api-ilmu-ai>": {
        "baseUrl": "<BASE_URL:-https://api.ilmu.ai/v1>",
        "api": "openai-completions",
        "apiKey": "<ILMU_API_KEY:->",
        "models": [
          {
            "id": "nemo-super",
            "name": "ILMU Nemo Super",
            "contextWindow": 256000, "maxTokens": 128000,
            "input": ["text"],
            "cost": {"input":0,"output":0,"cacheRead":0,"cacheWrite":0},
            "reasoning": false
          },
          {
            "id": "ilmu-nemo-nano",
            "name": "ILMU Nemo Nano",
            "contextWindow": 256000, "maxTokens": 128000,
            "input": ["text"],
            "cost": {"input":0,"output":0,"cacheRead":0,"cacheWrite":0},
            "reasoning": false
          }
        ]
      }
    }
  }
}' ~/.openclaw/openclaw.json > /tmp/openclaw-merged.json \
  && mv /tmp/openclaw-merged.json ~/.openclaw/openclaw.json \
  && chmod 600 ~/.openclaw/openclaw.json \
  && echo "PASS: config written (permissions: 600)" \
  || { echo "FAIL: config write failed"; exit 1; }

# Verify
jq -r '.env.ILMU_API_KEY // empty' ~/.openclaw/openclaw.json | grep -q . \
  && echo "PASS: API key present in config" \
  || echo "FAIL: API key missing from config"
```

---

## STEP 6 — RESTART GATEWAY

```bash
openclaw gateway restart && sleep 2

STATUS=$(openclaw gateway status 2>&1)
if echo "$STATUS" | grep -qi "running"; then
  echo "PASS: gateway running"
  echo "$STATUS"
else
  echo "FAIL: gateway not running"
  echo "$STATUS"
  echo "Try: openclaw doctor"
  exit 1
fi
```

---

## STEP 7 — TEST

```bash
# Via OpenClaw (WebSocket — primary path)
openclaw infer model run --model "custom-api-ilmu-ai/nemo-super" --prompt "Say hi."

# All models
for model in nemo-super ilmu-nemo-nano; do
  echo -n "custom-api-ilmu-ai/$model: "
  openclaw infer model run --model "custom-api-ilmu-ai/$model" --prompt "Say hi." 2>&1
  echo
done
```

Direct API test (bypasses OpenClaw — isolates key/URL issues):

```bash
KEY=$(jq -r '.env.ILMU_API_KEY' ~/.openclaw/openclaw.json)
BASE=$(jq -r '.env.BASE_URL // "https://api.ilmu.ai/v1"' ~/.openclaw/openclaw.json)

curl -s -X POST "$BASE/chat/completions" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $KEY" \
  -d '{"model":"nemo-super","messages":[{"role":"user","content":"Say hi."}],"max_tokens":50,"stream":false}' \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['choices'][0]['message']['content'])"
```

---

## API EXAMPLES

### Python (openai SDK)

```python
import json, os
from pathlib import Path
from openai import OpenAI

config = json.loads(Path("~/.openclaw/openclaw.json").expanduser().read_text())
client = OpenAI(
    base_url=config["env"].get("BASE_URL", "https://api.ilmu.ai/v1"),
    api_key=config["env"]["ILMU_API_KEY"],
)

response = client.chat.completions.create(
    model="nemo-super",
    messages=[{"role": "user", "content": "Write a fizzbuzz in Python."}],
    max_tokens=1000,
)
print(response.choices[0].message.content)
```

### Python (stdlib only)

```python
import json, urllib.request
from pathlib import Path

config = json.loads(Path("~/.openclaw/openclaw.json").expanduser().read_text())
BASE = config["env"].get("BASE_URL", "https://api.ilmu.ai/v1")
KEY  = config["env"]["ILMU_API_KEY"]

def chat(model: str, prompt: str, max_tokens: int = 1000) -> str:
    req = urllib.request.Request(
        f"{BASE}/chat/completions",
        data=json.dumps({"model": model, "messages": [{"role": "user", "content": prompt}],
                         "max_tokens": max_tokens, "stream": False}).encode(),
        headers={"Content-Type": "application/json", "Authorization": f"Bearer {KEY}"},
    )
    with urllib.request.urlopen(req, timeout=600) as r:
        return json.load(r)["choices"][0]["message"]["content"]

print(chat("nemo-super", "Write a fizzbuzz in Python."))
```

---

## CHECKLIST

```
prereqs: macOS, Xcode CLT, Homebrew, node>=22.14, jq

[ ] 1.  macOS confirmed — uname -s returns Darwin
[ ] 2.  Xcode CLT installed — xcode-select -p returns a path
[ ] 3.  Homebrew installed — brew --version
[ ] 4.  node installed — node --version (>=22.14)
[ ] 5.  jq installed — jq --version
[ ] 6.  openclaw installed — openclaw --version
[ ] 7.  onboarding wizard completed — openclaw gateway status shows running
[ ] 8.  API key and base URL written to config — jq '.env' ~/.openclaw/openclaw.json
[ ] 9.  config permissions restricted — ls -la ~/.openclaw/openclaw.json (shows -rw-------)
[ ] 10. gateway restarted — openclaw gateway restart
[ ] 11. gateway running — openclaw gateway status
[ ] 12. inference passes — openclaw infer model run --model "custom-api-ilmu-ai/nemo-super" --prompt "Say hi."
```

---

## VERIFY

```bash
command -v openclaw &>/dev/null && echo "PASS: openclaw" || echo "FAIL: openclaw not found"
jq empty ~/.openclaw/openclaw.json 2>/dev/null && echo "PASS: config valid JSON" || echo "FAIL: invalid JSON"
KEY=$(jq -r '.env.ILMU_API_KEY // empty' ~/.openclaw/openclaw.json)
[[ -n "$KEY" ]] && echo "PASS: API key in config" || echo "FAIL: API key missing"
BASE=$(jq -r '.env.BASE_URL // "https://api.ilmu.ai/v1 (default)"' ~/.openclaw/openclaw.json)
echo "INFO: BASE_URL=$BASE"
openclaw gateway status 2>&1 | grep -qi "running" && echo "PASS: gateway running" || echo "FAIL: not running"
RESULT=$(openclaw infer model run --model "custom-api-ilmu-ai/nemo-super" --prompt "Say hi." 2>&1)
if [[ $? -eq 0 ]]; then
  echo "PASS: inference OK — $RESULT"
else
  echo "FAIL: inference failed — $RESULT"
fi
```

---

## UPDATE

OpenClaw provides built-in commands for updates and health checks. Run these before reporting any issue.

```bash
# Check for issues first
openclaw doctor

# Update to latest version
openclaw update

# Fallback if openclaw update is unavailable
npm install -g openclaw@latest

# Restart gateway after update to apply changes
openclaw gateway restart
openclaw gateway status
```

`openclaw doctor` checks: config validity, gateway health, provider connectivity, daemon status, and version currency — run it whenever something is not working before attempting manual fixes.

---

## TROUBLESHOOTING

| symptom | cause | fix |
|---------|-------|-----|
| `openclaw` not found after install | PATH not updated | `export PATH="$(npm prefix -g)/bin:$PATH"` |
| Homebrew install hangs | CLT dialog appeared | Click Install in the system dialog |
| CLT install dialog does not appear | headless / MDM Mac | Use `softwareupdate` CLI or download from `https://developer.apple.com/download/all/?q=command+line+tools` |
| gateway not running | config JSON invalid | `jq . ~/.openclaw/openclaw.json` — fix parse error |
| inference timeout | key wrong or timeout too low | run direct curl test; confirm `timeoutSeconds: 600` at `agents.defaults` level |
| sharp build error | libvips conflict | `SHARP_IGNORE_GLOBAL_LIBVIPS=1 npm install -g openclaw@latest` |
| node version too old | brew installed older LTS | `brew upgrade node` then verify `node --version` >=22.14 |

```bash
openclaw doctor
jq . ~/.openclaw/openclaw.json
openclaw gateway status
```

---

## UNINSTALL

### Remove ilmu.ai only

```bash
jq '
  del(.env.ILMU_API_KEY) | del(.env.BASE_URL) |
  .models.providers  |= with_entries(select(.key | test("ilmu|ENDPOINT_ID") | not)) |
  .agents.defaults.models |= with_entries(select(.key | test("ilmu|ENDPOINT_ID") | not)) |
  if .env == {} then del(.env) else . end
' ~/.openclaw/openclaw.json > /tmp/no-ilmu.json \
  && mv /tmp/no-ilmu.json ~/.openclaw/openclaw.json \
  && echo "PASS: ilmu.ai removed from config"
openclaw gateway restart
```

### Full OpenClaw uninstall

```bash
launchctl bootout gui/$(id -u) ~/Library/LaunchAgents/ai.openclaw.gateway.plist 2>/dev/null || true
rm -f ~/Library/LaunchAgents/ai.openclaw.gateway.plist
npm uninstall -g openclaw && echo "PASS: openclaw removed"
rm -rf ~/.openclaw && echo "PASS: config removed"
```

Verify clean:
```bash
command -v openclaw &>/dev/null && echo "WARN: still in PATH" || echo "PASS: removed"
[[ -d ~/.openclaw ]] && echo "WARN: ~/.openclaw still exists" || echo "PASS: config dir removed"
```
