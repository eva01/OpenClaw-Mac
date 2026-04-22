<!-- ilmu-ai-setup-windows.md — Detailed OpenClaw + ilmu.ai setup for Windows 10/11 -->
<!-- Human summary: Full step-by-step guide for connecting OpenClaw to ilmu.ai on Windows 10 or 11.
     Covers winget, Node, jq, OpenClaw install, API key stored in ~/.openclaw/openclaw.json
     (env section), gateway setup, and end-to-end test. No local model server required — cloud only.
     For cross-platform quick setup, use README.md instead. -->

CONTEXT: AI agent executing this file. Connect OpenClaw to ilmu.ai on Windows 10 or 11.
Run each section in order using PowerShell. Skip sections whose GUARD check already passes.
Config: %USERPROFILE%\.openclaw\openclaw.json. API key stored in the config file — no registry or
environment variable setup needed.

CONSTRAINTS:
- platform: Windows 10 or Windows 11 ONLY
- shell: PowerShell 5.1+ (not cmd)
- non_interactive: true — run without prompts unless marked PAUSE
- pause_policy: PAUSE blocks require human action; agent stops, shows instruction, waits for confirmation
- api_key: stored in openclaw.json under env.ILMU_API_KEY — never in user environment variables
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

```powershell
# Windows 10/11 guard
$v = [System.Environment]::OSVersion.Version
if ($v.Major -lt 10) { Write-Host "FAIL: requires Windows 10 or 11"; exit 1 }
$build = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion").CurrentBuild
$ed = if ([int]$build -ge 22000) { "Windows 11 (Build $build)" } else { "Windows 10 (Build $build)" }
Write-Host "PASS: $ed"

# PowerShell execution policy — must allow remote scripts for openclaw install
$policy = Get-ExecutionPolicy -Scope CurrentUser
if ($policy -in @("Restricted","Undefined")) {
  Write-Host "WARN: execution policy=$policy — Step 2 will fix (required for openclaw install)"
} else {
  Write-Host "PASS: execution policy=$policy"
}

# winget — built in on W10 1709+ and W11
if (Get-Command winget -EA SilentlyContinue) { Write-Host "PASS: winget available" }
else { Write-Host "FAIL: winget not found — install App Installer from Microsoft Store"; exit 1 }

# Node / npm
if (Get-Command node -EA SilentlyContinue) { Write-Host "PASS: node=$(node --version) npm=$(npm --version)" }
else { Write-Host "FAIL: node not found — Step 2 will install" }

# jq
if (Get-Command jq -EA SilentlyContinue) { Write-Host "PASS: jq=$(jq --version)" }
else { Write-Host "FAIL: jq not found — Step 2 will install" }

# OpenClaw
if (Get-Command openclaw -EA SilentlyContinue) { $ov = openclaw --version 2>$null; Write-Host "PASS: openclaw=$(if ($ov) { $ov } else { 'installed' })" }
else { Write-Host "FAIL: openclaw not installed — Step 3 will install" }

# Gateway
$s = openclaw gateway status 2>&1
if ($s -match "running") { Write-Host "PASS: gateway running" } else { Write-Host "FAIL: gateway not running — Step 6 will start" }

# Port 18789 — must be free before onboarding
$port = Get-NetTCPConnection -LocalPort 18789 -State Listen -EA SilentlyContinue
if ($port) { Write-Host "WARN: port 18789 in use (PID $($port.OwningProcess)) — kill before openclaw onboard" }
else { Write-Host "PASS: port 18789 free" }

# Config
if (Test-Path "$env:USERPROFILE\.openclaw\openclaw.json") { Write-Host "PASS: config exists" }
else { Write-Host "FAIL: config not found — Step 5 will create" }
```

---

## STEP 2 — PREREQUISITES

### Execution policy

```powershell
$policy = Get-ExecutionPolicy -Scope CurrentUser
if ($policy -in @("Restricted","Undefined")) {
  Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force
  Write-Host "PASS: execution policy set to RemoteSigned (current user only)"
} else {
  Write-Host "SKIP: execution policy already allows scripts ($policy)"
}
```

### Node

```powershell
if (Get-Command node -EA SilentlyContinue) {
  Write-Host "SKIP: node already installed — $(node --version)"
} else {
  winget install --id OpenJS.NodeJS.LTS --accept-source-agreements --accept-package-agreements
  $env:PATH = [System.Environment]::GetEnvironmentVariable("PATH","Machine") + ";" +
               [System.Environment]::GetEnvironmentVariable("PATH","User")
  if (Get-Command node -EA SilentlyContinue) { Write-Host "PASS: node=$(node --version)" }
  else { Write-Host "FAIL: node not found after install — restart PowerShell and re-run"; exit 1 }
}

# Verify version meets minimum requirement (>=22.14)
$nodeParts = (node --version).TrimStart('v').Split('.')
$nodeMajor = [int]$nodeParts[0]; $nodeMinor = [int]$nodeParts[1]
if ($nodeMajor -gt 22 -or ($nodeMajor -eq 22 -and $nodeMinor -ge 14)) {
  Write-Host "PASS: node=$(node --version) (meets >=22.14)"
} else {
  Write-Host "WARN: node=$(node --version) — recommend >=22.14; upgrade: winget upgrade OpenJS.NodeJS.LTS"
}
```

### jq

```powershell
if (Get-Command jq -EA SilentlyContinue) {
  Write-Host "SKIP: jq already installed — $(jq --version)"
} else {
  winget install --id jqlang.jq --accept-source-agreements --accept-package-agreements
  $env:PATH = [System.Environment]::GetEnvironmentVariable("PATH","Machine") + ";" +
               [System.Environment]::GetEnvironmentVariable("PATH","User")
  if (Get-Command jq -EA SilentlyContinue) { Write-Host "PASS: jq=$(jq --version)" }
  else { Write-Host "FAIL: jq not found after install — restart PowerShell and re-run"; exit 1 }
}
```

---

## STEP 3 — INSTALL OPENCLAW

```powershell
if (Get-Command openclaw -EA SilentlyContinue) {
  Write-Host "SKIP: openclaw already installed"
} else {
  iwr -useb https://openclaw.ai/install.ps1 | iex
  $env:PATH = [System.Environment]::GetEnvironmentVariable("PATH","Machine") + ";" +
               [System.Environment]::GetEnvironmentVariable("PATH","User")
  if (-not (Get-Command openclaw -EA SilentlyContinue)) {
    # Fallback via npm
    npm install -g openclaw@latest
    $env:PATH = [System.Environment]::GetEnvironmentVariable("PATH","Machine") + ";" +
                 [System.Environment]::GetEnvironmentVariable("PATH","User")
  }
  if (Get-Command openclaw -EA SilentlyContinue) { Write-Host "PASS: openclaw installed" }
  else { Write-Host "FAIL: install failed — check node version (>=22.14 required)"; exit 1 }
}
```

If `openclaw` is not found after install:
```powershell
# Add npm global bin to PATH for this session
$npmBin = "$(npm prefix -g)\bin"
$env:PATH = "$npmBin;$env:PATH"
```

---

## STEP 4 — FIRST-TIME ONBOARDING

Skip this step if the gateway is already running (`openclaw gateway status` shows running).

Before onboarding, confirm port 18789 is free:
```powershell
$p = Get-NetTCPConnection -LocalPort 18789 -State Listen -EA SilentlyContinue
if ($p) { Write-Host "WARN: port 18789 in use (PID $($p.OwningProcess)) — kill it first" }
else { Write-Host "PASS: port 18789 free" }
```

PAUSE: OpenClaw requires an interactive setup wizard on first install. Run in PowerShell:
```
openclaw onboard --install-daemon
```
Prompts:
1. Auth — skip cloud API keys for now (ilmu.ai added in Step 5)
2. Gateway port — press Enter for default 18789
3. Gateway bind — choose loopback
4. Install daemon — yes (registers a Scheduled Task to auto-start on login)

After the wizard:
```powershell
openclaw gateway status
# Expected: Runtime: running, Listening: 127.0.0.1:18789
```
Tell the agent to continue once you see "running".

---

## STEP 5 — CONFIGURE ilmu.ai

The API key and base URL are stored in `%USERPROFILE%\.openclaw\openclaw.json` under `"env"`.
OpenClaw reads them at startup — no environment variables or registry changes needed.

PAUSE: Ask the user for:
1. Their ilmu.ai API key (starts with `sk-`)
2. Base URL — use `https://api.ilmu.ai/v1` for production, or their staging URL

Use the values as `$ILMU_KEY` and `$ILMU_BASE` in the block below.

```powershell
# Set from user input:
$ILMU_KEY  = "sk-..."
$ILMU_BASE = "https://api.ilmu.ai/v1"

# Guard: fail if placeholder was not replaced
if ($ILMU_KEY -eq "sk-..." -or -not $ILMU_KEY) { Write-Host "FAIL: ILMU_KEY placeholder not replaced — set your actual sk- key"; exit 1 }
Write-Host "INFO: BASE_URL=$ILMU_BASE"

$configDir  = "$env:USERPROFILE\.openclaw"
$configFile = "$configDir\openclaw.json"
if (-not (Test-Path $configDir))  { New-Item -ItemType Directory $configDir | Out-Null }
if (-not (Test-Path $configFile)) { '{}' | Set-Content -Encoding UTF8 $configFile }

# Step 1: write static config (single-quoted — no variable expansion, safe for template vars)
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

# Step 2: inject API key and base URL safely via jq --arg (handles $, ", \ in key values)
# Capture output before writing so $LASTEXITCODE reflects jq, not Set-Content
$patchJson = jq --arg key "$ILMU_KEY" --arg base "$ILMU_BASE" '. + {"env": {"ILMU_API_KEY": $key, "BASE_URL": $base}}' `
  "$env:TEMP\ilmu-static.json"
if ($LASTEXITCODE -ne 0) { Write-Host "FAIL: jq patch failed"; exit 1 }
$patchJson | Set-Content -Encoding UTF8 "$env:TEMP\ilmu-patch.json"

# Step 3: merge patch into existing config
$mergedJson = jq -s '.[0] * .[1]' $configFile "$env:TEMP\ilmu-patch.json"

if ($LASTEXITCODE -eq 0) {
  $mergedJson | Set-Content -Encoding UTF8 $configFile
  # Restrict permissions: current user only
  icacls $configFile /inheritance:r /grant:r "${env:USERNAME}:(R,W)" | Out-Null
  Write-Host "PASS: config written and permissions restricted"
} else {
  Write-Host "FAIL: jq merge failed — check $configFile is valid JSON"
  exit 1
}
Remove-Item -EA SilentlyContinue "$env:TEMP\ilmu-patch.json","$env:TEMP\ilmu-static.json"

# Verify
$key = jq -r '.env.ILMU_API_KEY // empty' $configFile
if ($key) { Write-Host "PASS: API key present in config" } else { Write-Host "FAIL: API key missing" }
```

---

## STEP 6 — RESTART GATEWAY

```powershell
openclaw gateway restart; Start-Sleep 2
$s = openclaw gateway status 2>&1
if ($s -match "running") { Write-Host "PASS: gateway running"; Write-Host $s }
else { Write-Host "FAIL: gateway not running — run: openclaw doctor"; Write-Host $s; exit 1 }
```

---

## STEP 7 — TEST

```powershell
# Via OpenClaw (WebSocket — primary path)
openclaw infer model run --model "custom-api-ilmu-ai/nemo-super" --prompt "Say hi."

# All models
foreach ($model in @("nemo-super", "ilmu-nemo-nano")) {
  Write-Host -NoNewline "custom-api-ilmu-ai/$model`: "
  openclaw infer model run --model "custom-api-ilmu-ai/$model" --prompt "Say hi." 2>&1
  Write-Host
}
```

Direct API test (bypasses OpenClaw — isolates key/URL issues):

```powershell
$configFile = "$env:USERPROFILE\.openclaw\openclaw.json"
$key  = jq -r '.env.ILMU_API_KEY' $configFile
$base = jq -r '.env.BASE_URL // "https://api.ilmu.ai/v1"' $configFile

Invoke-RestMethod -Uri "$base/chat/completions" `
  -Method POST -ContentType "application/json" `
  -Headers @{ Authorization = "Bearer $key" } `
  -Body '{"model":"nemo-super","messages":[{"role":"user","content":"Say hi."}],"max_tokens":50,"stream":false}' `
  | Select-Object -ExpandProperty choices | Select-Object -First 1 | ForEach-Object { $_.message.content }
```

---

## CHECKLIST

```
prereqs: Windows 10/11, PowerShell 5.1+, winget, node>=22.14, jq

[ ] 1.  Windows 10 or 11 confirmed
[ ] 2.  winget available
[ ] 3.  node installed — node --version (>=22.14)
[ ] 4.  jq installed — jq --version
[ ] 5.  openclaw installed — openclaw --version
[ ] 6.  onboarding wizard completed — openclaw gateway status shows running
[ ] 7.  API key and base URL written to config — jq '.env' %USERPROFILE%\.openclaw\openclaw.json
[ ] 8.  config permissions restricted (user only)
[ ] 9.  gateway restarted and running
[ ] 10. inference passes — openclaw infer model run --model "custom-api-ilmu-ai/nemo-super" --prompt "Say hi."
```

---

## VERIFY

```powershell
$configFile = "$env:USERPROFILE\.openclaw\openclaw.json"

if (Get-Command openclaw -EA SilentlyContinue) { Write-Host "PASS: openclaw" } else { Write-Host "FAIL: openclaw not found" }
$null = jq empty $configFile 2>&1
if ($LASTEXITCODE -eq 0) { Write-Host "PASS: config valid JSON" } else { Write-Host "FAIL: invalid JSON" }
$key = jq -r '.env.ILMU_API_KEY // empty' $configFile
if ($key) { Write-Host "PASS: API key in config" } else { Write-Host "FAIL: API key missing" }
$base = jq -r '.env.BASE_URL // "https://api.ilmu.ai/v1 (default)"' $configFile
Write-Host "INFO: BASE_URL=$base"
$s = openclaw gateway status 2>&1
if ($s -match "running") { Write-Host "PASS: gateway running" } else { Write-Host "FAIL: not running" }
$result = openclaw infer model run --model "custom-api-ilmu-ai/nemo-super" --prompt "Say hi." 2>&1
if ($LASTEXITCODE -eq 0) { Write-Host "PASS: inference OK — $result" }
else { Write-Host "FAIL: inference failed — $result" }
```

---

## TROUBLESHOOTING

| symptom | cause | fix |
|---------|-------|-----|
| `openclaw` not found after install | PATH not updated | Restart PowerShell; or: `$env:PATH = "$(npm prefix -g)\bin;$env:PATH"` |
| winget not found | App Installer missing | Install **App Installer** from Microsoft Store |
| execution policy blocked | default Restricted policy | `Set-ExecutionPolicy RemoteSigned -Scope CurrentUser -Force` |
| gateway not running | config JSON invalid | `jq . "$env:USERPROFILE\.openclaw\openclaw.json"` |
| inference timeout | key wrong or timeout low | Run direct Invoke-RestMethod test; confirm `timeoutSeconds: 600` at `agents.defaults` |
| jq merge failed | existing config invalid JSON | `jq . $configFile` to see parse error, fix then retry |
| node version too old | winget installed older LTS | `winget upgrade OpenJS.NodeJS.LTS` then verify `node --version` >=22.14 |

```powershell
openclaw doctor
jq . "$env:USERPROFILE\.openclaw\openclaw.json"
openclaw gateway status
```

---

## UPDATE

OpenClaw provides built-in commands for updates and health checks. Run these before reporting any issue.

```powershell
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

## UNINSTALL

### Remove ilmu.ai only

```powershell
$configFile = "$env:USERPROFILE\.openclaw\openclaw.json"
jq '
  del(.env.ILMU_API_KEY) | del(.env.BASE_URL) |
  .models.providers  |= with_entries(select(.key | test("ilmu|ENDPOINT_ID") | not)) |
  .agents.defaults.models |= with_entries(select(.key | test("ilmu|ENDPOINT_ID") | not)) |
  if .env == {} then del(.env) else . end
' $configFile | Set-Content -Encoding UTF8 "$env:TEMP\no-ilmu.json"
Move-Item -Force "$env:TEMP\no-ilmu.json" $configFile
Write-Host "PASS: ilmu.ai removed from config"
openclaw gateway restart
```

### Full OpenClaw uninstall

```powershell
# Stop daemon
openclaw daemon stop 2>$null
schtasks /delete /tn "OpenClaw Gateway" /f 2>$null

# Remove package
npm uninstall -g openclaw
Write-Host "PASS: openclaw removed"

# Remove config
Remove-Item -Recurse -Force "$env:USERPROFILE\.openclaw"
Write-Host "PASS: config removed"
```

Verify clean:
```powershell
if (Get-Command openclaw -EA SilentlyContinue) { Write-Host "WARN: still in PATH" } else { Write-Host "PASS: removed" }
if (Test-Path "$env:USERPROFILE\.openclaw") { Write-Host "WARN: config dir still exists" } else { Write-Host "PASS: removed" }
```
