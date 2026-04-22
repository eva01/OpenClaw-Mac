<!-- README.md — ilmu.ai OpenClaw Setup (cross-platform entry point) -->
<!-- Human summary: Two-step entry point for connecting OpenClaw to ilmu.ai on macOS or Windows 10/11.
     Step 1 installs OpenClaw and gets the gateway running. Step 2 adds the ilmu.ai API key.
     AI agent detects OS from Step 1 output and runs only matching blocks thereafter.
     API key stored securely in ~/.openclaw/openclaw.json (env section) — not in shell profiles.
     Detailed per-OS guides: ilmu-ai-setup-mac.md, ilmu-ai-setup-windows.md.
     Telegram setup: setup-telegram.md -->

CONTEXT: AI agent executing this file. There are two steps:
- STEP 1: Install OpenClaw and get the gateway running (no API key needed)
- STEP 2: Connect ilmu.ai using the user's API key

Detect the OS at the start of Step 1, then run only the block labelled with your OS for every subsequent block.
Config: ~/.openclaw/openclaw.json (macOS) or %USERPROFILE%\.openclaw\openclaw.json (Windows).

CONSTRAINTS:
- Supported OS: macOS (Apple Silicon or Intel), Windows 10, Windows 11
- macOS blocks: bash (zsh compatible) — run in Terminal
- Windows blocks: PowerShell 5.1+ — run in PowerShell (not cmd)
- non_interactive: true — all blocks run unattended unless marked PAUSE
- pause_policy: PAUSE blocks require the human to act; agent stops, shows the instruction, waits for confirmation
- api_key: stored in openclaw.json under "env.ILMU_API_KEY" — never in shell profiles or dotfiles
- timeoutSeconds: 600

## MODELS

| id | name | context | max tokens |
|----|------|---------|------------|
| `nemo-super` | ILMU Nemo Super | 256k | 128k |
| `ilmu-nemo-nano` | ILMU Nemo Nano | 256k | 128k |

Default: `nemo-super` — Base URL: `https://api.ilmu.ai/v1`
Staging override: set `BASE_URL` in the `env` section of openclaw.json (Step 2)

---

## STEP 1 — INSTALL OPENCLAW

This step installs all prerequisites, installs OpenClaw, and starts the gateway.
No API key is needed. Skip any sub-block whose check already passes.

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

# Node
command -v node &>/dev/null && echo "PASS: node=$(node --version)" || echo "INFO: node not found — will install"

# jq
command -v jq &>/dev/null && echo "PASS: jq=$(jq --version)" || echo "INFO: jq not found — will install"

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
If no dialog appears (headless Mac), run: `softwareupdate -l` to find the CLT package name, then `softwareupdate -i "<package name>" --agree-to-license`

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

Skip this block if the gateway is already running (shown as `PASS: gateway running` above).

```bash
# Check gateway — skip onboarding if already running
openclaw gateway status 2>/dev/null | grep -qi "running" && { echo "SKIP: gateway already running"; exit 0; }

# Confirm port 18789 is free
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
# Verify gateway is up after onboarding
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

# Node
if (Get-Command node -EA SilentlyContinue) { Write-Host "PASS: node=$(node --version)" }
else { Write-Host "INFO: node not found — will install" }

# jq
if (Get-Command jq -EA SilentlyContinue) { Write-Host "PASS: jq=$(jq --version)" }
else { Write-Host "INFO: jq not found — will install" }

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
} else {
  Write-Host "SKIP: execution policy already allows scripts ($policy)"
}

# Node
if (-not (Get-Command node -EA SilentlyContinue)) {
  winget install --id OpenJS.NodeJS.LTS --accept-source-agreements --accept-package-agreements
  $env:PATH = [System.Environment]::GetEnvironmentVariable("PATH","Machine") + ";" +
               [System.Environment]::GetEnvironmentVariable("PATH","User")
}
Write-Host "PASS: node=$(node --version)"

# jq
if (-not (Get-Command jq -EA SilentlyContinue)) {
  winget install --id jqlang.jq --accept-source-agreements --accept-package-agreements
  $env:PATH = [System.Environment]::GetEnvironmentVariable("PATH","Machine") + ";" +
               [System.Environment]::GetEnvironmentVariable("PATH","User")
}
Write-Host "PASS: jq=$(jq --version)"

# OpenClaw
if (Get-Command openclaw -EA SilentlyContinue) {
  Write-Host "SKIP: openclaw already installed"
} else {
  iwr -useb https://openclaw.ai/install.ps1 | iex
  $env:PATH = [System.Environment]::GetEnvironmentVariable("PATH","Machine") + ";" +
               [System.Environment]::GetEnvironmentVariable("PATH","User")
  if (-not (Get-Command openclaw -EA SilentlyContinue)) { npm install -g openclaw@latest }
  if (Get-Command openclaw -EA SilentlyContinue) { Write-Host "PASS: openclaw installed" }
  else { Write-Host "FAIL: install failed — check node version (>=22.14)"; exit 1 }
}
```

### Windows — first-time onboarding

Skip this block if the gateway is already running (shown as `PASS: gateway running` above).

```powershell
# Check gateway — skip onboarding if already running
$s = openclaw gateway status 2>&1
if ($s -match "running") { Write-Host "SKIP: gateway already running"; exit 0 }

# Confirm port 18789 is free
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
# Verify gateway is up after onboarding
$s = openclaw gateway status 2>&1
if ($s -match "running") { Write-Host "PASS: gateway running — Step 1 complete" }
else { Write-Host "FAIL: gateway not running — run: openclaw doctor"; exit 1 }
```

---

## STEP 2 — CONNECT ilmu.ai

The API key is stored inside `openclaw.json` under `"env"` — OpenClaw injects it at runtime via template variables. No shell profile changes needed.

PAUSE: Ask the user for:
1. Their ilmu.ai API key (starts with `sk-`)
2. Base URL — press Enter for production default (`https://api.ilmu.ai/v1`), or provide staging URL

Then substitute into the block for their OS below and run it.

### macOS

```bash
# Set from user input:
ILMU_KEY="sk-..."                       # replace with actual key
ILMU_BASE="https://api.ilmu.ai/v1"     # replace with staging URL if needed

# Guard
[[ "$ILMU_KEY" == "sk-..." || -z "$ILMU_KEY" ]] && { echo "FAIL: ILMU_KEY placeholder not replaced"; exit 1; }
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
          { "id": "nemo-super",     "name": "ILMU Nemo Super", "contextWindow": 256000, "maxTokens": 128000, "input": ["text"], "cost": {"input":0,"output":0,"cacheRead":0,"cacheWrite":0}, "reasoning": false },
          { "id": "ilmu-nemo-nano", "name": "ILMU Nemo Nano",  "contextWindow": 256000, "maxTokens": 128000, "input": ["text"], "cost": {"input":0,"output":0,"cacheRead":0,"cacheWrite":0}, "reasoning": false }
        ]
      }
    }
  }
}' ~/.openclaw/openclaw.json > /tmp/openclaw-merged.json \
  && mv /tmp/openclaw-merged.json ~/.openclaw/openclaw.json \
  && chmod 600 ~/.openclaw/openclaw.json \
  && echo "PASS: config written" \
  || { echo "FAIL: config write failed"; exit 1; }

# Verify key is in config
KEY=$(jq -r '.env.ILMU_API_KEY // empty' ~/.openclaw/openclaw.json)
[[ -n "$KEY" ]] && echo "PASS: API key present in config" || echo "FAIL: API key missing from config"

# Restart gateway to apply config
openclaw gateway restart && sleep 2
openclaw gateway status 2>&1 | grep -qi "running" \
  && echo "PASS: gateway running" \
  || { echo "FAIL: gateway not running — run: openclaw doctor"; exit 1; }

# Test inference
echo "INFO: running inference test..."
RESULT=$(openclaw infer model run --model "custom-api-ilmu-ai/nemo-super" --prompt "Say hi." 2>&1)
if [[ $? -eq 0 ]]; then
  echo "PASS: inference OK — $RESULT"
else
  echo "FAIL: inference failed — $RESULT"
  echo "INFO: run direct API test below to isolate key vs OpenClaw issue"
fi
```

Direct API test (bypasses OpenClaw — use this if inference fails):
```bash
curl -s -X POST "$(jq -r '.env.BASE_URL // "https://api.ilmu.ai/v1"' ~/.openclaw/openclaw.json)/chat/completions" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $(jq -r '.env.ILMU_API_KEY' ~/.openclaw/openclaw.json)" \
  -d '{"model":"nemo-super","messages":[{"role":"user","content":"Say hi."}],"max_tokens":50,"stream":false}' \
  | jq -r '.choices[0].message.content'
```

### Windows

```powershell
# Set from user input:
$ILMU_KEY  = "sk-..."                   # replace with actual key
$ILMU_BASE = "https://api.ilmu.ai/v1"  # replace with staging URL if needed

# Guard
if ($ILMU_KEY -eq "sk-..." -or -not $ILMU_KEY) { Write-Host "FAIL: ILMU_KEY placeholder not replaced"; exit 1 }
Write-Host "INFO: BASE_URL=$ILMU_BASE"

$configDir  = "$env:USERPROFILE\.openclaw"
$configFile = "$configDir\openclaw.json"
if (-not (Test-Path $configDir))  { New-Item -ItemType Directory $configDir | Out-Null }
if (-not (Test-Path $configFile)) { '{}' | Set-Content -Encoding UTF8 $configFile }

# Write static config (single-quoted here-string — safe for template variables)
@'
{
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
          { "id": "nemo-super",     "name": "ILMU Nemo Super", "contextWindow": 256000, "maxTokens": 128000, "input": ["text"], "cost": {"input":0,"output":0,"cacheRead":0,"cacheWrite":0}, "reasoning": false },
          { "id": "ilmu-nemo-nano", "name": "ILMU Nemo Nano",  "contextWindow": 256000, "maxTokens": 128000, "input": ["text"], "cost": {"input":0,"output":0,"cacheRead":0,"cacheWrite":0}, "reasoning": false }
        ]
      }
    }
  }
}
'@ | Set-Content -Encoding UTF8 "$env:TEMP\ilmu-static.json"

# Inject key and base URL via jq --arg — capture output before writing so exit code is reliable
$patchJson = jq --arg key "$ILMU_KEY" --arg base "$ILMU_BASE" '. + {"env": {"ILMU_API_KEY": $key, "BASE_URL": $base}}' `
  "$env:TEMP\ilmu-static.json"
if ($LASTEXITCODE -ne 0) { Write-Host "FAIL: jq patch failed"; exit 1 }
$patchJson | Set-Content -Encoding UTF8 "$env:TEMP\ilmu-patch.json"

$mergedJson = jq -s '.[0] * .[1]' $configFile "$env:TEMP\ilmu-patch.json"
if ($LASTEXITCODE -eq 0) {
  $mergedJson | Set-Content -Encoding UTF8 $configFile
  icacls $configFile /inheritance:r /grant:r "${env:USERNAME}:(R,W)" | Out-Null
  Write-Host "PASS: config written"
} else { Write-Host "FAIL: jq merge failed"; exit 1 }
Remove-Item -EA SilentlyContinue "$env:TEMP\ilmu-patch.json","$env:TEMP\ilmu-static.json"

# Verify key is in config
$key = jq -r '.env.ILMU_API_KEY // empty' $configFile
if ($key) { Write-Host "PASS: API key present in config" } else { Write-Host "FAIL: API key missing" }

# Restart gateway to apply config
openclaw gateway restart; Start-Sleep 2
$s = openclaw gateway status 2>&1
if ($s -match "running") { Write-Host "PASS: gateway running" }
else { Write-Host "FAIL: gateway not running — run: openclaw doctor"; exit 1 }

# Test inference
Write-Host "INFO: running inference test..."
$result = openclaw infer model run --model "custom-api-ilmu-ai/nemo-super" --prompt "Say hi." 2>&1
if ($LASTEXITCODE -eq 0) { Write-Host "PASS: inference OK — $result" }
else { Write-Host "FAIL: inference failed — $result"; Write-Host "INFO: run direct API test below to isolate key vs OpenClaw issue" }
```

Direct API test (bypasses OpenClaw — use this if inference fails):
```powershell
$key  = jq -r '.env.ILMU_API_KEY' "$env:USERPROFILE\.openclaw\openclaw.json"
$base = jq -r '.env.BASE_URL // "https://api.ilmu.ai/v1"' "$env:USERPROFILE\.openclaw\openclaw.json"
Invoke-RestMethod -Uri "$base/chat/completions" `
  -Method POST -ContentType "application/json" `
  -Headers @{ Authorization = "Bearer $key" } `
  -Body '{"model":"nemo-super","messages":[{"role":"user","content":"Say hi."}],"max_tokens":50,"stream":false}' `
  | Select-Object -ExpandProperty choices | Select-Object -First 1 | ForEach-Object { $_.message.content }
```

---

## TROUBLESHOOTING

| symptom | fix |
|---------|-----|
| `openclaw` not found after install | macOS: `export PATH="$(npm prefix -g)/bin:$PATH"` — Windows: restart PowerShell |
| gateway not running after restart | `openclaw doctor` → `jq . ~/.openclaw/openclaw.json` (check JSON is valid) |
| inference timeout | confirm `timeoutSeconds: 600` is at `agents.defaults` level in config |
| API key not working | run the direct API test block above to isolate key vs OpenClaw |
| sharp build error (macOS) | `SHARP_IGNORE_GLOBAL_LIBVIPS=1 npm install -g openclaw@latest` |
| winget not found (Windows) | install **App Installer** from Microsoft Store |
| Xcode CLT dialog does not appear (macOS) | `softwareupdate -l` to find package name, then `softwareupdate -i "<name>" --agree-to-license` |
| PowerShell scripts blocked (Windows) | `Set-ExecutionPolicy RemoteSigned -Scope CurrentUser -Force` |
| node version too old | macOS: `brew upgrade node` — Windows: `winget upgrade OpenJS.NodeJS.LTS` |
| anything else | `openclaw doctor` — checks config, gateway, providers, and daemon in one command |

### Update OpenClaw

```bash
openclaw update          # built-in updater (both OS, same command)
openclaw gateway restart
openclaw doctor
```

---

## DETAILED GUIDES

For a step-by-step walkthrough with full troubleshooting per OS:

- **macOS**: `ilmu-ai-setup-mac.md`
- **Windows**: `ilmu-ai-setup-windows.md`
- **Telegram**: `setup-telegram.md`
