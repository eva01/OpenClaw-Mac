<!-- README.md — ilmu.ai OpenClaw Setup (cross-platform entry point) -->
<!-- Human summary: Single entry point for connecting OpenClaw to ilmu.ai on macOS or Windows 10/11.
     AI agent detects OS in Step 1 then runs only the matching blocks. API key stored securely
     in ~/.openclaw/openclaw.json (env section) — not in shell profiles or dotfiles.
     Detailed per-OS guides: ilmu-ai-setup-mac.md, ilmu-ai-setup-windows.md.
     Telegram setup: setup-telegram.md -->

CONTEXT: AI agent executing this file. Connect OpenClaw to ilmu.ai as a cloud LLM provider.
Detect the OS in Step 1, then for every subsequent step run only the block labelled with your OS.
Config: ~/.openclaw/openclaw.json (macOS/Linux) or %USERPROFILE%\.openclaw\openclaw.json (Windows).
The API key is written into the config file — no shell profile changes required.

CONSTRAINTS:
- Supported OS: macOS (Apple Silicon or Intel), Windows 10, Windows 11
- macOS blocks: bash — run in Terminal or zsh
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
Staging override: set `BASE_URL` in the `env` section of openclaw.json (see Step 4)

---

## STEP 1 — DETECT SYSTEM

### macOS
```bash
# Fail fast if not macOS
[[ "$(uname -s)" == "Darwin" ]] || { echo "FAIL: not macOS — use the Windows block"; exit 1; }
echo "PASS: macOS $(sw_vers -productVersion) ($(uname -m))"

# Xcode CLT — required by Homebrew (covers git, make, curl extras)
if xcode-select -p &>/dev/null; then
  echo "PASS: Xcode CLT — $(xcode-select -p)"
else
  echo "FAIL: Xcode CLT not installed — see PAUSE below"
fi

# Homebrew
command -v brew &>/dev/null && echo "PASS: brew $(brew --version | head -1)" || echo "FAIL: Homebrew not installed — Step 2 will install"

# Node / npm
command -v node &>/dev/null && echo "PASS: node=$(node --version) npm=$(npm --version)" || echo "FAIL: node not found — Step 2 will install"

# jq
command -v jq &>/dev/null && echo "PASS: jq=$(jq --version)" || echo "FAIL: jq not found — Step 2 will install"

# OpenClaw
command -v openclaw &>/dev/null \
  && echo "PASS: openclaw=$(openclaw --version 2>/dev/null || echo installed)" \
  || echo "FAIL: openclaw not installed — Step 3 will install"

# Gateway
if command -v openclaw &>/dev/null; then
  openclaw gateway status 2>/dev/null | grep -qi "running" \
    && echo "PASS: gateway running" || echo "FAIL: gateway not running — Step 5 will start"
else
  echo "SKIP: gateway check skipped — openclaw not installed"
fi
```

If `FAIL: Xcode CLT not installed`:

PAUSE: Run the following in Terminal, click Install in the dialog that appears, wait for it to finish (~5 min), then tell the agent to continue:
```
xcode-select --install
```

### Windows
```powershell
# Fail fast if not Windows 10/11
$v = [System.Environment]::OSVersion.Version
if ($v.Major -lt 10) { Write-Host "FAIL: requires Windows 10 or 11"; exit 1 }
$build = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion").CurrentBuild
$ed = if ([int]$build -ge 22000) { "Windows 11 (Build $build)" } else { "Windows 10 (Build $build)" }
Write-Host "PASS: $ed"

# winget
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
if ($s -match "running") { Write-Host "PASS: gateway running" } else { Write-Host "FAIL: gateway not running — Step 5 will start" }
```

---

## STEP 2 — PREREQUISITES

### macOS

```bash
# Homebrew
if ! command -v brew &>/dev/null; then
  NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  eval "$(/opt/homebrew/bin/brew shellenv 2>/dev/null || /usr/local/bin/brew shellenv)"
fi
echo "PASS: brew $(brew --version | head -1)"

# Node
command -v node &>/dev/null || brew install node
echo "PASS: node=$(node --version)"

# jq
command -v jq &>/dev/null || brew install jq
echo "PASS: jq=$(jq --version)"
```

### Windows

```powershell
# Execution policy — required for openclaw install script to run
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
```

---

## STEP 3 — INSTALL OPENCLAW

### macOS

```bash
if command -v openclaw &>/dev/null; then
  echo "SKIP: openclaw already installed"
else
  curl -fsSL https://openclaw.ai/install.sh | bash
  # Fallback: sharp build error fix
  command -v openclaw &>/dev/null || SHARP_IGNORE_GLOBAL_LIBVIPS=1 npm install -g openclaw@latest
  command -v openclaw &>/dev/null && echo "PASS: openclaw installed" || { echo "FAIL: install failed"; exit 1; }
fi
```

### Windows

```powershell
if (-not (Get-Command openclaw -EA SilentlyContinue)) {
  iwr -useb https://openclaw.ai/install.ps1 | iex
  $env:PATH = [System.Environment]::GetEnvironmentVariable("PATH","Machine") + ";" +
               [System.Environment]::GetEnvironmentVariable("PATH","User")
  if (-not (Get-Command openclaw -EA SilentlyContinue)) {
    npm install -g openclaw@latest
  }
}
$ov = openclaw --version 2>$null; Write-Host "PASS: openclaw=$(if ($ov) { $ov } else { 'installed' })"
```

### First-time onboarding

PAUSE: OpenClaw requires an interactive setup wizard on first install. Run in your terminal:
```
openclaw onboard --install-daemon
```
Prompts: skip cloud API keys → port 18789 → loopback → yes to daemon.
Confirm with `openclaw gateway status` (expect: running), then tell the agent to continue.

---

## STEP 4 — CONFIGURE ilmu.ai

The API key and optional staging URL are stored inside `~/.openclaw/openclaw.json` under the `env` section — no shell profile changes needed.

PAUSE: Ask the user for their ilmu.ai API key (starts with `sk-`). Use that value as `ILMU_KEY` in the block below. For staging, also ask for the base URL (default: `https://api.ilmu.ai/v1`).

### macOS

```bash
# Set these from what the user provided:
ILMU_KEY="sk-..."                          # replace with actual key
ILMU_BASE="https://api.ilmu.ai/v1"         # replace with staging URL if needed

# Guard: fail if placeholder not replaced
[[ "$ILMU_KEY" == "sk-..." || -z "$ILMU_KEY" ]] && { echo "FAIL: ILMU_KEY placeholder not replaced"; exit 1; }

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
        "<ENDPOINT_ID:-custom-api-ilmu-ai>/nemo-super":    { "alias": "nemo-super",  "streaming": false },
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
  && echo "PASS: config written and permissions set (600)" \
  || { echo "FAIL: config write failed"; exit 1; }
```

### Windows

```powershell
# Set these from what the user provided:
$ILMU_KEY  = "sk-..."                       # replace with actual key
$ILMU_BASE = "https://api.ilmu.ai/v1"      # replace with staging URL if needed

$configDir  = "$env:USERPROFILE\.openclaw"
$configFile = "$configDir\openclaw.json"
if (-not (Test-Path $configDir))  { New-Item -ItemType Directory $configDir | Out-Null }
if (-not (Test-Path $configFile)) { '{}' | Set-Content -Encoding UTF8 $configFile }

# Guard: fail if placeholder not replaced
if ($ILMU_KEY -eq "sk-..." -or -not $ILMU_KEY) { Write-Host "FAIL: ILMU_KEY placeholder not replaced"; exit 1 }

# Static config (single-quoted — safe for template vars and special chars)
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
          { "id": "nemo-super",      "name": "ILMU Nemo Super", "contextWindow": 256000, "maxTokens": 128000, "input": ["text"], "cost": {"input":0,"output":0,"cacheRead":0,"cacheWrite":0}, "reasoning": false },
          { "id": "ilmu-nemo-nano",  "name": "ILMU Nemo Nano",  "contextWindow": 256000, "maxTokens": 128000, "input": ["text"], "cost": {"input":0,"output":0,"cacheRead":0,"cacheWrite":0}, "reasoning": false }
        ]
      }
    }
  }
}
'@ | Set-Content -Encoding UTF8 "$env:TEMP\ilmu-static.json"

# Inject key and base URL safely via jq --arg (handles $, ", \ in values)
# Capture output before writing so $LASTEXITCODE reflects jq, not Set-Content
$patchJson = jq --arg key "$ILMU_KEY" --arg base "$ILMU_BASE" '. + {"env": {"ILMU_API_KEY": $key, "BASE_URL": $base}}' `
  "$env:TEMP\ilmu-static.json"
if ($LASTEXITCODE -ne 0) { Write-Host "FAIL: jq patch failed"; exit 1 }
$patchJson | Set-Content -Encoding UTF8 "$env:TEMP\ilmu-patch.json"

$mergedJson = jq -s '.[0] * .[1]' $configFile "$env:TEMP\ilmu-patch.json"
if ($LASTEXITCODE -eq 0) {
  $mergedJson | Set-Content -Encoding UTF8 $configFile
  icacls $configFile /inheritance:r /grant:r "${env:USERNAME}:(R,W)" | Out-Null
  Write-Host "PASS: config written and permissions restricted"
} else { Write-Host "FAIL: jq merge failed"; exit 1 }
Remove-Item -EA SilentlyContinue "$env:TEMP\ilmu-patch.json","$env:TEMP\ilmu-static.json"
```

---

## STEP 5 — RESTART GATEWAY

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
if ($s -match "running") { Write-Host "PASS: gateway running" }
else { Write-Host "FAIL: gateway not running — run: openclaw doctor"; exit 1 }
```

---

## STEP 6 — TEST

Same command on both OS (OpenClaw CLI is cross-platform):

```bash
# macOS / Windows (bash or PowerShell)
openclaw infer model run --model "custom-api-ilmu-ai/nemo-super" --prompt "Say hi."
```

Direct API test (bypasses OpenClaw — useful for verifying the key independently):

### macOS
```bash
curl -s -X POST "https://api.ilmu.ai/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $(jq -r '.env.ILMU_API_KEY' ~/.openclaw/openclaw.json)" \
  -d '{"model":"nemo-super","messages":[{"role":"user","content":"Say hi."}],"max_tokens":50,"stream":false}' \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['choices'][0]['message']['content'])"
```

### Windows
```powershell
$key = jq -r '.env.ILMU_API_KEY' "$env:USERPROFILE\.openclaw\openclaw.json"
Invoke-RestMethod -Uri "https://api.ilmu.ai/v1/chat/completions" `
  -Method POST -ContentType "application/json" `
  -Headers @{ Authorization = "Bearer $key" } `
  -Body '{"model":"nemo-super","messages":[{"role":"user","content":"Say hi."}],"max_tokens":50,"stream":false}' `
  | Select-Object -ExpandProperty choices | Select-Object -First 1 | ForEach-Object { $_.message.content }
```

---

## VERIFY

### macOS
```bash
command -v openclaw &>/dev/null && echo "PASS: openclaw" || echo "FAIL: openclaw not found"
jq empty ~/.openclaw/openclaw.json 2>/dev/null && echo "PASS: config valid JSON" || echo "FAIL: config invalid"
KEY=$(jq -r '.env.ILMU_API_KEY // empty' ~/.openclaw/openclaw.json)
[[ -n "$KEY" ]] && echo "PASS: API key present in config" || echo "FAIL: API key missing"
openclaw gateway status 2>&1 | grep -qi "running" && echo "PASS: gateway running" || echo "FAIL: gateway not running"
```

### Windows
```powershell
if (Get-Command openclaw -EA SilentlyContinue) { Write-Host "PASS: openclaw" } else { Write-Host "FAIL: openclaw not found" }
$null = jq empty "$env:USERPROFILE\.openclaw\openclaw.json" 2>&1
if ($LASTEXITCODE -eq 0) { Write-Host "PASS: config valid JSON" } else { Write-Host "FAIL: config invalid" }
$key = jq -r '.env.ILMU_API_KEY // empty' "$env:USERPROFILE\.openclaw\openclaw.json"
if ($key) { Write-Host "PASS: API key present in config" } else { Write-Host "FAIL: API key missing" }
$s = openclaw gateway status 2>&1
if ($s -match "running") { Write-Host "PASS: gateway running" } else { Write-Host "FAIL: gateway not running" }
```

---

## TROUBLESHOOTING

| symptom | fix |
|---------|-----|
| `openclaw` not found after install | macOS: `export PATH="$(npm prefix -g)/bin:$PATH"` — Windows: restart PowerShell |
| gateway not running after restart | `openclaw doctor` → `jq . ~/.openclaw/openclaw.json` (check JSON is valid) |
| inference timeout | confirm `timeoutSeconds: 600` is at `agents.defaults` level in config |
| API key not working | run direct curl/Invoke-RestMethod test in Step 6 to isolate to key vs OpenClaw |
| sharp build error (macOS) | `SHARP_IGNORE_GLOBAL_LIBVIPS=1 npm install -g openclaw@latest` |
| winget not found (Windows) | install **App Installer** from Microsoft Store |
| Xcode CLT dialog does not appear (macOS) | use `softwareupdate` CLI or download from `https://developer.apple.com/download/all/?q=command+line+tools` |
| PowerShell scripts blocked (Windows) | `Set-ExecutionPolicy RemoteSigned -Scope CurrentUser -Force` |
| node version too old | macOS: `brew upgrade node` — Windows: `winget upgrade OpenJS.NodeJS.LTS` |
| anything else | `openclaw doctor` — checks config, gateway, providers, and daemon in one command |

### Update OpenClaw

```bash
openclaw update          # built-in updater (both OS, same command)
openclaw gateway restart # apply after update
openclaw doctor          # confirm everything healthy
```

---

## DETAILED GUIDES

For a step-by-step walkthrough with full troubleshooting per OS, point your AI agent at the raw file:

- **macOS**: `https://raw.githubusercontent.com/eva01/OpenClaw-Mac/ilmu-ai-setup/ilmu-ai-setup-mac.md`
- **Windows**: `https://raw.githubusercontent.com/eva01/OpenClaw-Mac/ilmu-ai-setup/ilmu-ai-setup-windows.md`
- **Telegram**: `https://raw.githubusercontent.com/eva01/OpenClaw-Mac/ilmu-ai-setup/setup-telegram.md`
