<!-- README.md — BytePlus Coding Plan + OpenClaw Setup (cross-platform entry point) -->
<!-- Human summary: Two-step entry point for connecting OpenClaw to BytePlus Coding Plan on macOS or
     Windows 10/11. Step 1 installs OpenClaw and gets the gateway running. Step 2 configures the
     BytePlus provider using the API key. Base URL is fixed — no staging variant.
     Detailed per-OS guides: byteplus-setup-mac.md, byteplus-setup-windows.md. -->

CONTEXT: AI agent executing this file. There are two steps:
- STEP 1: Install OpenClaw and get the gateway running (no API key needed)
- STEP 2: Connect BytePlus Coding Plan using the user's API key

Detect the OS at the start of Step 1, then run only the block labelled with your OS for every subsequent block.
Config: ~/.openclaw/openclaw.json (macOS) or %USERPROFILE%\.openclaw\openclaw.json (Windows).
If you see files other than this README on this branch, you are on the wrong branch.

CONSTRAINTS:
- Supported OS: macOS (Apple Silicon or Intel), Windows 10, Windows 11
- macOS blocks: bash (zsh compatible) — run in Terminal
- Windows blocks: PowerShell 5.1+ — run in PowerShell (not cmd)
- non_interactive: true — all blocks run unattended unless marked PAUSE
- pause_policy: PAUSE blocks require the human to act; agent stops, shows the instruction, waits for confirmation
- api_key: stored in openclaw.json under models.providers.byteplus.apiKey — never in shell profiles
- timeoutSeconds: 600

## MODELS

| id | name |
|----|------|
| `ark-code-latest` | **Default** — routes to model selected in the BytePlus web console |
| `bytedance-seed-code` | ByteDance Seed Code |
| `kimi-k2.5` | Kimi K2.5 |
| `gpt-oss-120b` | GPT OSS 120B |
| `glm-5.1` | GLM 5.1 |
| `glm-4.7` | GLM 4.7 |
| `dola-seed-2.0-code` | Dola Seed 2.0 Code |
| `dola-seed-2.0-pro` | Dola Seed 2.0 Pro |
| `dola-seed-2.0-lite` | Dola Seed 2.0 Lite |

Default: `ark-code-latest` — routes to the model selected in the BytePlus Coding Plan web console.
Base URL: `https://ark.ap-southeast.bytepluses.com/api/coding/v3` (fixed)
Model IDs are confirmed from the API in Step 2.

---

## STEP 1 — INSTALL OPENCLAW

This step installs all prerequisites, installs OpenClaw, and starts the gateway.
No API key needed. Skip any sub-block whose check already passes.

### macOS — check system

```bash
# OS guard
[[ "$(uname -s)" == "Darwin" ]] || { echo "FAIL: not macOS — use the Windows block"; exit 1; }
echo "PASS: macOS $(sw_vers -productVersion) ($(uname -m))"

# Xcode CLT — required by Homebrew
if xcode-select -p &>/dev/null; then
  echo "PASS: Xcode CLT — $(xcode-select -p)"
else
  echo "FAIL: Xcode CLT not installed — see PAUSE below"
fi

# Homebrew
command -v brew &>/dev/null && echo "PASS: brew $(brew --version | head -1)" || echo "INFO: Homebrew not installed — will install"

# Node and jq
command -v node &>/dev/null && echo "PASS: node=$(node --version)" || echo "INFO: node not found — will install"
command -v jq   &>/dev/null && echo "PASS: jq=$(jq --version)"   || echo "INFO: jq not found — will install"

# OpenClaw
command -v openclaw &>/dev/null \
  && echo "PASS: openclaw=$(openclaw --version 2>/dev/null || echo installed)" \
  || echo "INFO: openclaw not installed — will install"

# Gateway
if command -v openclaw &>/dev/null; then
  openclaw gateway status 2>/dev/null | grep -qi "running" \
    && echo "PASS: gateway running" || echo "INFO: gateway not running — will start"
else
  echo "INFO: gateway check skipped — openclaw not installed yet"
fi
```

If `FAIL: Xcode CLT not installed`:

PAUSE: Run the following in Terminal, click Install in the dialog, wait for it to finish (~5 min), then tell the agent to continue:
```
xcode-select --install
```
If no dialog appears (headless Mac): `softwareupdate -l` to find the CLT package name, then `softwareupdate -i "<name>" --agree-to-license`

### macOS — install prerequisites and OpenClaw

```bash
# Homebrew
if ! command -v brew &>/dev/null; then
  NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  eval "$(/opt/homebrew/bin/brew shellenv 2>/dev/null || /usr/local/bin/brew shellenv)"
fi
echo "PASS: brew $(brew --version | head -1)"

# Node and jq
command -v node &>/dev/null || brew install node
echo "PASS: node=$(node --version)"
command -v jq &>/dev/null || brew install jq
echo "PASS: jq=$(jq --version)"

# OpenClaw
if command -v openclaw &>/dev/null; then
  echo "SKIP: openclaw already installed — $(openclaw --version 2>/dev/null || echo version unknown)"
else
  curl -fsSL https://openclaw.ai/install.sh | bash
  command -v openclaw &>/dev/null || SHARP_IGNORE_GLOBAL_LIBVIPS=1 npm install -g openclaw@latest
  command -v openclaw &>/dev/null && echo "PASS: openclaw installed" || { echo "FAIL: install failed — check node version (>=22.14)"; exit 1; }
fi
```

### macOS — first-time onboarding

Skip this block if the gateway is already running (`PASS: gateway running` above).

```bash
openclaw gateway status 2>/dev/null | grep -qi "running" && { echo "SKIP: gateway already running"; exit 0; }
lsof -i :18789 | grep -q LISTEN \
  && { echo "FAIL: port 18789 in use — kill the process first: sudo lsof -i :18789"; exit 1; } \
  || echo "PASS: port 18789 free"
```

PAUSE: Run the onboarding wizard in your terminal:
```
openclaw onboard --install-daemon
```
Prompts: skip cloud API keys → port 18789 (Enter for default) → loopback → yes to daemon.
When done, run `openclaw gateway status` — expect "running". Then tell the agent to continue.

```bash
openclaw gateway status 2>&1 | grep -qi "running" \
  && echo "PASS: gateway running — Step 1 complete" \
  || { echo "FAIL: gateway not running — run: openclaw doctor"; exit 1; }
```

---

### Windows — check system

```powershell
# OS guard
$v = [System.Environment]::OSVersion.Version
if ($v.Major -lt 10) { Write-Host "FAIL: requires Windows 10 or 11"; exit 1 }
$build = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion").CurrentBuild
$ed = if ([int]$build -ge 22000) { "Windows 11 (Build $build)" } else { "Windows 10 (Build $build)" }
Write-Host "PASS: $ed"

# Execution policy
$policy = Get-ExecutionPolicy -Scope CurrentUser
if ($policy -in @("Restricted","Undefined")) { Write-Host "INFO: execution policy=$policy — will fix" }
else { Write-Host "PASS: execution policy=$policy" }

# winget
if (Get-Command winget -EA SilentlyContinue) { Write-Host "PASS: winget available" }
else { Write-Host "FAIL: winget not found — install App Installer from Microsoft Store"; exit 1 }

# Node and jq
if (Get-Command node -EA SilentlyContinue) { Write-Host "PASS: node=$(node --version)" } else { Write-Host "INFO: node not found — will install" }
if (Get-Command jq   -EA SilentlyContinue) { Write-Host "PASS: jq=$(jq --version)"   } else { Write-Host "INFO: jq not found — will install" }

# OpenClaw
if (Get-Command openclaw -EA SilentlyContinue) { $ov = openclaw --version 2>$null; Write-Host "PASS: openclaw=$(if ($ov) { $ov } else { 'installed' })" }
else { Write-Host "INFO: openclaw not installed — will install" }

# Gateway
if (Get-Command openclaw -EA SilentlyContinue) {
  $s = openclaw gateway status 2>&1
  if ($s -match "running") { Write-Host "PASS: gateway running" } else { Write-Host "INFO: gateway not running — will start" }
} else { Write-Host "INFO: gateway check skipped — openclaw not installed yet" }
```

### Windows — install prerequisites and OpenClaw

```powershell
# Execution policy
$policy = Get-ExecutionPolicy -Scope CurrentUser
if ($policy -in @("Restricted","Undefined")) {
  Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force
  Write-Host "PASS: execution policy set to RemoteSigned"
} else { Write-Host "SKIP: execution policy already allows scripts ($policy)" }

# Node
if (-not (Get-Command node -EA SilentlyContinue)) {
  winget install --id OpenJS.NodeJS.LTS --accept-source-agreements --accept-package-agreements
  $env:PATH = [System.Environment]::GetEnvironmentVariable("PATH","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("PATH","User")
}
Write-Host "PASS: node=$(node --version)"

# jq
if (-not (Get-Command jq -EA SilentlyContinue)) {
  winget install --id jqlang.jq --accept-source-agreements --accept-package-agreements
  $env:PATH = [System.Environment]::GetEnvironmentVariable("PATH","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("PATH","User")
}
Write-Host "PASS: jq=$(jq --version)"

# OpenClaw
if (Get-Command openclaw -EA SilentlyContinue) {
  Write-Host "SKIP: openclaw already installed"
} else {
  iwr -useb https://openclaw.ai/install.ps1 | iex
  $env:PATH = [System.Environment]::GetEnvironmentVariable("PATH","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("PATH","User")
  if (-not (Get-Command openclaw -EA SilentlyContinue)) { npm install -g openclaw@latest }
  if (Get-Command openclaw -EA SilentlyContinue) { Write-Host "PASS: openclaw installed" }
  else { Write-Host "FAIL: install failed — check node version (>=22.14)"; exit 1 }
}
```

### Windows — first-time onboarding

Skip this block if the gateway is already running (`PASS: gateway running` above).

```powershell
$s = openclaw gateway status 2>&1
if ($s -match "running") { Write-Host "SKIP: gateway already running"; exit 0 }
$port = Get-NetTCPConnection -LocalPort 18789 -State Listen -EA SilentlyContinue
if ($port) { Write-Host "FAIL: port 18789 in use (PID $($port.OwningProcess)) — kill it first"; exit 1 }
else { Write-Host "PASS: port 18789 free" }
```

PAUSE: Run the onboarding wizard in PowerShell:
```
openclaw onboard --install-daemon
```
Prompts: skip cloud API keys → port 18789 (Enter for default) → loopback → yes to daemon.
When done, run `openclaw gateway status` — expect "running". Then tell the agent to continue.

```powershell
$s = openclaw gateway status 2>&1
if ($s -match "running") { Write-Host "PASS: gateway running — Step 1 complete" }
else { Write-Host "FAIL: gateway not running — run: openclaw doctor"; exit 1 }
```

---

## STEP 2 — CONNECT BYTEPLUS

The API key is written directly into the provider config in `openclaw.json`. The base URL is fixed.

Don't have a BytePlus Coding Plan account yet? First month is $9 USD — sign up with a discount:
https://www.byteplus.com/activity/codingplan?ac=MMAUCIS9NT1S&rc=HJA73DT3

Once signed up, choose your preferred model in the web console (the `ark-code-latest` default routes to it automatically):
https://console.byteplus.com/ark/region:ark+ap-southeast-1/openManagement

PAUSE: Ask the user for their BytePlus Coding Plan API key (from the BytePlus Coding Plan console). Then substitute it into the block for their OS below and run it.

### macOS

```bash
BYTEPLUS_KEY="your-api-key-here"   # replace with actual key
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
  MODEL_DEFAULT="ark-code-latest"
  # Build model array from discovery
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
  echo "WARN: could not query /models (check key) — using hardcoded model list"
  MODEL_DEFAULT="ark-code-latest"
  MODELS_ARRAY='[
    {"id":"bytedance-seed-code", "name":"ByteDance Seed Code","reasoning":false,"input":["text"],"cost":{"input":0,"output":0,"cacheRead":0,"cacheWrite":0},"contextWindow":262144,"maxTokens":131072},
    {"id":"kimi-k2.5",           "name":"Kimi K2.5",          "reasoning":false,"input":["text"],"cost":{"input":0,"output":0,"cacheRead":0,"cacheWrite":0},"contextWindow":262144,"maxTokens":32768},
    {"id":"gpt-oss-120b",        "name":"GPT OSS 120B",       "reasoning":false,"input":["text"],"cost":{"input":0,"output":0,"cacheRead":0,"cacheWrite":0},"contextWindow":131072,"maxTokens":65536},
    {"id":"glm-5.1",             "name":"GLM 5.1",             "reasoning":false,"input":["text"],"cost":{"input":0,"output":0,"cacheRead":0,"cacheWrite":0},"contextWindow":131072,"maxTokens":65536},
    {"id":"glm-4.7",             "name":"GLM 4.7",             "reasoning":false,"input":["text"],"cost":{"input":0,"output":0,"cacheRead":0,"cacheWrite":0},"contextWindow":200000,"maxTokens":131072},
    {"id":"dola-seed-2.0-code",  "name":"Dola Seed 2.0 Code", "reasoning":false,"input":["text"],"cost":{"input":0,"output":0,"cacheRead":0,"cacheWrite":0},"contextWindow":262144,"maxTokens":131072},
    {"id":"dola-seed-2.0-pro",   "name":"Dola Seed 2.0 Pro",  "reasoning":false,"input":["text"],"cost":{"input":0,"output":0,"cacheRead":0,"cacheWrite":0},"contextWindow":262144,"maxTokens":131072},
    {"id":"dola-seed-2.0-lite",  "name":"Dola Seed 2.0 Lite", "reasoning":false,"input":["text"],"cost":{"input":0,"output":0,"cacheRead":0,"cacheWrite":0},"contextWindow":262144,"maxTokens":131072}
  ]'
fi

# Write config — key and URL written directly (template vars don't expand in provider config)
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
  && echo "PASS: config written" \
  || { echo "FAIL: config write failed"; exit 1; }
rm -f /tmp/byteplus-patch.json

# Verify
KEY=$(jq -r '.models.providers.byteplus.apiKey // empty' ~/.openclaw/openclaw.json)
[[ -n "$KEY" ]] && echo "PASS: API key present in provider config" || echo "FAIL: API key missing"

# Restart gateway and test
openclaw gateway restart && sleep 2
openclaw gateway status 2>&1 | grep -qi "running" \
  && echo "PASS: gateway running" \
  || { echo "FAIL: gateway not running — run: openclaw doctor"; exit 1; }

echo "INFO: testing via OpenClaw..."
openclaw infer model run --model "byteplus/$MODEL_DEFAULT" --prompt "Say hi." 2>&1

echo "INFO: testing directly against API..."
curl -s -X POST "$BYTEPLUS_BASE/chat/completions" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $BYTEPLUS_KEY" \
  -d "{\"model\":\"$MODEL_DEFAULT\",\"messages\":[{\"role\":\"user\",\"content\":\"Say hi.\"}],\"max_tokens\":50,\"stream\":false}" \
  | jq -r '.choices[0].message.content // .error.message // .'
```

### Windows

```powershell
$BYTEPLUS_KEY  = "your-api-key-here"
$BYTEPLUS_BASE = "https://ark.ap-southeast.bytepluses.com/api/coding/v3"

# Guard
if ($BYTEPLUS_KEY -eq "your-api-key-here" -or -not $BYTEPLUS_KEY) { Write-Host "FAIL: BYTEPLUS_KEY placeholder not replaced"; exit 1 }

$configDir  = "$env:USERPROFILE\.openclaw"
$configFile = "$configDir\openclaw.json"
if (-not (Test-Path $configDir))  { New-Item -ItemType Directory $configDir | Out-Null }
if (-not (Test-Path $configFile)) { '{}' | Set-Content -Encoding UTF8 $configFile }

# Validate key and discover models
Write-Host "INFO: validating key and discovering models..."
try {
  $mr = Invoke-RestMethod -Uri "$BYTEPLUS_BASE/models" -Headers @{Authorization = "Bearer $BYTEPLUS_KEY"}
  Write-Host "INFO: available models:"; $mr.data.id | ForEach-Object { Write-Host "  $_" }
  $MODEL_DEFAULT = "ark-code-latest"
  $MODELS_ARRAY = $mr.data | ForEach-Object {
    @{ id=$_.id; name=$_.id; reasoning=$false; input=@("text");
       cost=@{input=0;output=0;cacheRead=0;cacheWrite=0};
       contextWindow=if($_.context_length){$_.context_length}else{131072};
       maxTokens=if($_.max_completion_tokens){$_.max_completion_tokens}else{32768} }
  }
  Write-Host "PASS: key valid — default model=$MODEL_DEFAULT"
} catch {
  Write-Host "WARN: could not query /models — using hardcoded model list"
  $MODEL_DEFAULT = "ark-code-latest"
  $MODELS_ARRAY = @(
    @{ id="bytedance-seed-code"; name="ByteDance Seed Code"; reasoning=$false; input=@("text"); cost=@{input=0;output=0;cacheRead=0;cacheWrite=0}; contextWindow=262144; maxTokens=131072 },
    @{ id="kimi-k2.5";           name="Kimi K2.5";           reasoning=$false; input=@("text"); cost=@{input=0;output=0;cacheRead=0;cacheWrite=0}; contextWindow=262144; maxTokens=32768  },
    @{ id="gpt-oss-120b";        name="GPT OSS 120B";        reasoning=$false; input=@("text"); cost=@{input=0;output=0;cacheRead=0;cacheWrite=0}; contextWindow=131072; maxTokens=65536  },
    @{ id="glm-5.1";             name="GLM 5.1";             reasoning=$false; input=@("text"); cost=@{input=0;output=0;cacheRead=0;cacheWrite=0}; contextWindow=131072; maxTokens=65536  },
    @{ id="glm-4.7";             name="GLM 4.7";             reasoning=$false; input=@("text"); cost=@{input=0;output=0;cacheRead=0;cacheWrite=0}; contextWindow=200000; maxTokens=131072 },
    @{ id="dola-seed-2.0-code";  name="Dola Seed 2.0 Code";  reasoning=$false; input=@("text"); cost=@{input=0;output=0;cacheRead=0;cacheWrite=0}; contextWindow=262144; maxTokens=131072 },
    @{ id="dola-seed-2.0-pro";   name="Dola Seed 2.0 Pro";   reasoning=$false; input=@("text"); cost=@{input=0;output=0;cacheRead=0;cacheWrite=0}; contextWindow=262144; maxTokens=131072 },
    @{ id="dola-seed-2.0-lite";  name="Dola Seed 2.0 Lite";  reasoning=$false; input=@("text"); cost=@{input=0;output=0;cacheRead=0;cacheWrite=0}; contextWindow=262144; maxTokens=131072 }
  )
}

# Build patch and merge into config
$patch = @{
  models = @{
    mode = "merge"
    providers = @{
      byteplus = @{
        baseUrl = $BYTEPLUS_BASE
        api     = "openai-completions"
        apiKey  = $BYTEPLUS_KEY
        models  = $MODELS_ARRAY
      }
    }
  }
  agents = @{
    defaults = @{
      model         = @{ primary = "byteplus/$MODEL_DEFAULT" }
      timeoutSeconds = 600
    }
  }
}

$patchJson = $patch | ConvertTo-Json -Depth 10 -Compress
$patchJson | Set-Content -Encoding UTF8 "$env:TEMP\byteplus-patch.json"

$mergedJson = jq -s '.[0] * .[1]' $configFile "$env:TEMP\byteplus-patch.json"
if ($LASTEXITCODE -eq 0) {
  $mergedJson | Set-Content -Encoding UTF8 $configFile
  icacls $configFile /inheritance:r /grant:r "${env:USERNAME}:(R,W)" | Out-Null
  Write-Host "PASS: config written"
} else { Write-Host "FAIL: jq merge failed"; exit 1 }
Remove-Item -EA SilentlyContinue "$env:TEMP\byteplus-patch.json"

# Verify
$kcheck = jq -r '.models.providers.byteplus.apiKey // empty' $configFile
if ($kcheck) { Write-Host "PASS: API key present in provider config" } else { Write-Host "FAIL: API key missing" }

# Restart gateway and test
openclaw gateway restart; Start-Sleep 2
$s = openclaw gateway status 2>&1
if ($s -match "running") { Write-Host "PASS: gateway running" }
else { Write-Host "FAIL: gateway not running — run: openclaw doctor"; exit 1 }

Write-Host "INFO: testing via OpenClaw..."
openclaw infer model run --model "byteplus/$MODEL_DEFAULT" --prompt "Say hi." 2>&1

Write-Host "INFO: testing directly against API..."
Invoke-RestMethod -Uri "$BYTEPLUS_BASE/chat/completions" `
  -Method POST -ContentType "application/json" `
  -Headers @{ Authorization = "Bearer $BYTEPLUS_KEY" } `
  -Body "{`"model`":`"$MODEL_DEFAULT`",`"messages`":[{`"role`":`"user`",`"content`":`"Say hi.`"}],`"max_tokens`":50,`"stream`":false}" `
  | Select-Object -ExpandProperty choices | Select-Object -First 1 | ForEach-Object { $_.message.content }
```

---

## NEXT STEP — TELEGRAM BOT (OPTIONAL)

OpenClaw is now connected to BytePlus Coding Plan. To chat with it and approve agent actions from your phone, set up the Telegram bot next:

```
setup-telegram.md
```

---

## TROUBLESHOOTING

| symptom | fix |
|---------|-----|
| `openclaw` not found after install | macOS: `export PATH="$(npm prefix -g)/bin:$PATH"` — Windows: restart PowerShell |
| 401 Unauthorized from API | API key wrong or expired — regenerate in BytePlus Coding Plan console |
| 403 Forbidden | Region lock — BytePlus `ap-southeast` endpoint may require APAC region or VPN |
| gateway not running | `openclaw doctor` → check `jq . ~/.openclaw/openclaw.json` is valid JSON |
| inference timeout | confirm `timeoutSeconds: 600` at `agents.defaults` level |
| sharp build error (macOS) | `SHARP_IGNORE_GLOBAL_LIBVIPS=1 npm install -g openclaw@latest` |
| winget not found (Windows) | install **App Installer** from Microsoft Store |
| PowerShell scripts blocked | `Set-ExecutionPolicy RemoteSigned -Scope CurrentUser -Force` |
| node too old | macOS: `brew upgrade node` — Windows: `winget upgrade OpenJS.NodeJS.LTS` |
| anything else | `openclaw doctor` |

### Update OpenClaw

```bash
openclaw update
openclaw gateway restart
openclaw doctor
```

---

## DETAILED GUIDES

For Gemini embeddings, Google Workspace (gog skill), benchmarking, and full troubleshooting:

- **macOS**: `byteplus-setup-mac.md`
- **Windows**: `byteplus-setup-windows.md`
- **Telegram bot**: `setup-telegram.md` — connect OpenClaw to a Telegram bot so you can chat with it and approve agent actions from your phone
