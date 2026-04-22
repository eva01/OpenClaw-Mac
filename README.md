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
| `ilmu-nemo-super` | ILMU Nemo Super | 256k | 128k |
| `ilmu-nemo-nano` | ILMU Nemo Nano | 256k | 128k |

Default primary: `ilmu-nemo-super` — Base URL: `https://api.ilmu.ai/v1`
Model IDs are discovered from the API in Step 2 — they may differ between environments.

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

The API key and base URL are written directly into the provider config in `openclaw.json`.

PAUSE: Ask the user for their ilmu.ai API key (starts with `sk-`). Ask separately for their base URL — production default is `https://api.ilmu.ai/v1`, or they can provide a staging URL. Substitute both into the block for their OS below, then run it.

### macOS

```bash
# Set from user input — ask for these separately:
ILMU_KEY="sk-..."                       # replace with actual key
ILMU_BASE="https://api.ilmu.ai/v1"     # replace with staging URL if needed

# Guard
[[ "$ILMU_KEY" == "sk-..." || -z "$ILMU_KEY" ]] && { echo "FAIL: ILMU_KEY placeholder not replaced"; exit 1; }
[[ "$ILMU_BASE" == "https://api.ilmu.ai/v1" ]] && echo "INFO: using production BASE_URL" || echo "INFO: using custom BASE_URL=$ILMU_BASE"

mkdir -p ~/.openclaw
[[ -f ~/.openclaw/openclaw.json ]] || echo '{}' > ~/.openclaw/openclaw.json

# Discover available model IDs from the API
MODELS_JSON=$(curl -s "$ILMU_BASE/models" -H "Authorization: Bearer $ILMU_KEY")
if echo "$MODELS_JSON" | jq -e '.data' &>/dev/null; then
  echo "INFO: available models:"
  echo "$MODELS_JSON" | jq -r '.data[].id' | sed 's/^/  /'
  MODEL_PRIMARY=$(echo "$MODELS_JSON" | jq -r '[.data[].id | select(test("nemo-super|super"))] | first // "ilmu-nemo-super"')
  MODEL_NANO=$(echo "$MODELS_JSON"    | jq -r '[.data[].id | select(test("nemo-nano|nano"))]  | first // "ilmu-nemo-nano"')
  echo "PASS: models selected — primary=$MODEL_PRIMARY nano=$MODEL_NANO"
else
  echo "WARN: could not query /models — using defaults (verify key and URL if inference fails)"
  MODEL_PRIMARY="ilmu-nemo-super"
  MODEL_NANO="ilmu-nemo-nano"
fi

# Write config — key and URL written directly into provider (template vars don't expand there)
jq --arg key "$ILMU_KEY" --arg base "$ILMU_BASE" \
   --arg mp "$MODEL_PRIMARY" --arg mn "$MODEL_NANO" '. * {
  "env": { "ILMU_API_KEY": $key, "BASE_URL": $base },
  "agents": {
    "defaults": {
      "model": { "primary": ("custom-api-ilmu-ai/" + $mp) },
      "models": {
        ("custom-api-ilmu-ai/" + $mp): { "alias": "nemo-super", "streaming": false },
        ("custom-api-ilmu-ai/" + $mn): { "alias": "nemo-nano",  "streaming": false }
      },
      "timeoutSeconds": 600
    }
  },
  "models": {
    "mode": "merge",
    "providers": {
      "custom-api-ilmu-ai": {
        "baseUrl": $base,
        "api": "openai-completions",
        "apiKey": $key,
        "models": [
          { "id": $mp, "name": "ILMU Nemo Super", "contextWindow": 256000, "maxTokens": 128000, "input": ["text"], "cost": {"input":0,"output":0,"cacheRead":0,"cacheWrite":0}, "reasoning": false },
          { "id": $mn, "name": "ILMU Nemo Nano",  "contextWindow": 256000, "maxTokens": 128000, "input": ["text"], "cost": {"input":0,"output":0,"cacheRead":0,"cacheWrite":0}, "reasoning": false }
        ]
      }
    }
  }
}' ~/.openclaw/openclaw.json > /tmp/openclaw-merged.json \
  && mv /tmp/openclaw-merged.json ~/.openclaw/openclaw.json \
  && chmod 600 ~/.openclaw/openclaw.json \
  && echo "PASS: config written" \
  || { echo "FAIL: config write failed"; exit 1; }

KEY=$(jq -r '.models.providers["custom-api-ilmu-ai"].apiKey // empty' ~/.openclaw/openclaw.json)
[[ -n "$KEY" ]] && echo "PASS: API key present in provider config" || echo "FAIL: API key missing from provider config"

# Restart gateway and test
openclaw gateway restart && sleep 2
openclaw gateway status 2>&1 | grep -qi "running" \
  && echo "PASS: gateway running" \
  || { echo "FAIL: gateway not running — run: openclaw doctor"; exit 1; }

echo "INFO: testing via OpenClaw..."
openclaw infer model run --model "custom-api-ilmu-ai/$MODEL_PRIMARY" --prompt "Say hi." 2>&1

echo "INFO: testing directly against API (bypasses OpenClaw)..."
curl -s -X POST "$ILMU_BASE/chat/completions" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $ILMU_KEY" \
  -d "{\"model\":\"$MODEL_PRIMARY\",\"messages\":[{\"role\":\"user\",\"content\":\"Say hi.\"}],\"max_tokens\":50,\"stream\":false}" \
  | jq -r '.choices[0].message.content // .error.message // .'
```

### Windows

```powershell
# Set from user input — ask for these separately:
$ILMU_KEY  = "sk-..."                   # replace with actual key
$ILMU_BASE = "https://api.ilmu.ai/v1"  # replace with staging URL if needed

# Guard
if ($ILMU_KEY -eq "sk-..." -or -not $ILMU_KEY) { Write-Host "FAIL: ILMU_KEY placeholder not replaced"; exit 1 }
Write-Host "INFO: BASE_URL=$ILMU_BASE"

$configDir  = "$env:USERPROFILE\.openclaw"
$configFile = "$configDir\openclaw.json"
if (-not (Test-Path $configDir))  { New-Item -ItemType Directory $configDir | Out-Null }
if (-not (Test-Path $configFile)) { '{}' | Set-Content -Encoding UTF8 $configFile }

# Discover available model IDs from the API
try {
  $mr = Invoke-RestMethod -Uri "$ILMU_BASE/models" -Headers @{Authorization = "Bearer $ILMU_KEY"}
  $MODEL_PRIMARY = ($mr.data | Where-Object { $_.id -match "nemo-super|super" } | Select-Object -First 1).id
  $MODEL_NANO    = ($mr.data | Where-Object { $_.id -match "nemo-nano|nano" }   | Select-Object -First 1).id
  if (-not $MODEL_PRIMARY) { $MODEL_PRIMARY = "ilmu-nemo-super" }
  if (-not $MODEL_NANO)    { $MODEL_NANO    = "ilmu-nemo-nano"  }
  Write-Host "PASS: models discovered — primary=$MODEL_PRIMARY nano=$MODEL_NANO"
  Write-Host "INFO: available models:"; $mr.data.id | ForEach-Object { Write-Host "  $_" }
} catch {
  $MODEL_PRIMARY = "ilmu-nemo-super"; $MODEL_NANO = "ilmu-nemo-nano"
  Write-Host "WARN: could not query /models — using defaults"
}

# Write config — key and URL written directly into provider (template vars don't expand there)
$mergedJson = jq --arg key "$ILMU_KEY" --arg base "$ILMU_BASE" `
  --arg mp "$MODEL_PRIMARY" --arg mn "$MODEL_NANO" `
  '{ "env": { "ILMU_API_KEY": $key, "BASE_URL": $base },
     "agents": { "defaults": {
       "model": { "primary": ("custom-api-ilmu-ai/" + $mp) },
       "models": {
         ("custom-api-ilmu-ai/" + $mp): { "alias": "nemo-super", "streaming": false },
         ("custom-api-ilmu-ai/" + $mn): { "alias": "nemo-nano",  "streaming": false }
       }, "timeoutSeconds": 600 } },
     "models": { "mode": "merge", "providers": { "custom-api-ilmu-ai": {
       "baseUrl": $base, "api": "openai-completions", "apiKey": $key,
       "models": [
         { "id": $mp, "name": "ILMU Nemo Super", "contextWindow": 256000, "maxTokens": 128000, "input": ["text"], "cost": {"input":0,"output":0,"cacheRead":0,"cacheWrite":0}, "reasoning": false },
         { "id": $mn, "name": "ILMU Nemo Nano",  "contextWindow": 256000, "maxTokens": 128000, "input": ["text"], "cost": {"input":0,"output":0,"cacheRead":0,"cacheWrite":0}, "reasoning": false }
       ] } } } }' $configFile
if ($LASTEXITCODE -ne 0) { Write-Host "FAIL: jq failed"; exit 1 }

# Merge patch into existing config
$patchFile = "$env:TEMP\ilmu-patch.json"
$mergedJson | Set-Content -Encoding UTF8 $patchFile
$finalJson = jq -s '.[0] * .[1]' $configFile $patchFile
if ($LASTEXITCODE -eq 0) {
  $finalJson | Set-Content -Encoding UTF8 $configFile
  icacls $configFile /inheritance:r /grant:r "${env:USERNAME}:(R,W)" | Out-Null
  Write-Host "PASS: config written"
} else { Write-Host "FAIL: jq merge failed"; exit 1 }
Remove-Item -EA SilentlyContinue $patchFile

$kcheck = jq -r '.models.providers["custom-api-ilmu-ai"].apiKey // empty' $configFile
if ($kcheck) { Write-Host "PASS: API key present in provider config" } else { Write-Host "FAIL: API key missing" }

# Restart gateway and test
openclaw gateway restart; Start-Sleep 2
$s = openclaw gateway status 2>&1
if ($s -match "running") { Write-Host "PASS: gateway running" }
else { Write-Host "FAIL: gateway not running — run: openclaw doctor"; exit 1 }

Write-Host "INFO: testing via OpenClaw..."
openclaw infer model run --model "custom-api-ilmu-ai/$MODEL_PRIMARY" --prompt "Say hi." 2>&1

Write-Host "INFO: testing directly against API (bypasses OpenClaw)..."
Invoke-RestMethod -Uri "$ILMU_BASE/chat/completions" `
  -Method POST -ContentType "application/json" `
  -Headers @{ Authorization = "Bearer $ILMU_KEY" } `
  -Body "{`"model`":`"$MODEL_PRIMARY`",`"messages`":[{`"role`":`"user`",`"content`":`"Say hi.`"}],`"max_tokens`":50,`"stream`":false}" `
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
