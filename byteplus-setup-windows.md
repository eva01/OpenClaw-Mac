<!-- byteplus-setup-windows.md — Detailed BytePlus Coding Plan + OpenClaw setup for Windows 10/11 -->
<!-- Human summary: Full step-by-step Windows guide. Covers execution policy, winget prereqs, Node,
     jq, OpenClaw install, BytePlus provider config, gateway setup, and optional Gemini embeddings
     and model benchmarking. gog skill is Mac-only (WSL fallback noted). For cross-platform quick
     setup, use README.md instead. -->

CONTEXT: AI agent executing this file. Connect OpenClaw to BytePlus Coding Plan on Windows.
Run each section in PowerShell 7+ (pwsh.exe) as a regular user — do NOT run as Administrator unless noted.
Config: $env:USERPROFILE\.openclaw\openclaw.json. API key is written directly into provider config — no environment variable changes needed.

CONSTRAINTS:
- platform: Windows 10/11 only (x64)
- shell: PowerShell 7+ (pwsh.exe) — NOT Windows PowerShell 5.x
- non_interactive: true — all blocks run without prompts unless marked PAUSE
- pause_policy: PAUSE blocks require human action; agent stops, shows instruction, waits for confirmation
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

---

## STEP 1 — EXECUTION POLICY AND SHELL CHECK

```powershell
# Confirm we are on Windows in PowerShell 7+
if ($IsWindows -ne $true) { Write-Error "FAIL: not Windows — use byteplus-setup-mac.md"; exit 1 }
if ($PSVersionTable.PSVersion.Major -lt 7) {
  Write-Error "FAIL: PowerShell 5 detected — reopen in PowerShell 7 (pwsh.exe)"
  exit 1
}
Write-Host "PASS: Windows PowerShell $($PSVersionTable.PSVersion) on $([System.Runtime.InteropServices.RuntimeInformation]::OSDescription)"

# Set execution policy for current user (safe, non-admin)
$pol = Get-ExecutionPolicy -Scope CurrentUser
if ($pol -eq 'Restricted' -or $pol -eq 'Undefined') {
  Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned -Force
  Write-Host "PASS: execution policy set to RemoteSigned (CurrentUser)"
} else {
  Write-Host "SKIP: execution policy already $pol"
}
Get-ExecutionPolicy -Scope CurrentUser
```

---

## STEP 2 — SYSTEM DETECTION

```powershell
# Node
if (Get-Command node -ErrorAction SilentlyContinue) {
  Write-Host "PASS: node=$(node --version)"
} else {
  Write-Host "INFO: node not found — Step 3 will install"
}

# jq
if (Get-Command jq -ErrorAction SilentlyContinue) {
  Write-Host "PASS: jq=$(jq --version)"
} else {
  Write-Host "INFO: jq not found — Step 3 will install"
}

# OpenClaw
if (Get-Command openclaw -ErrorAction SilentlyContinue) {
  $v = (openclaw --version 2>$null) ?? 'installed'
  Write-Host "PASS: openclaw=$v"
} else {
  Write-Host "INFO: openclaw not installed — Step 4 will install"
}

# Gateway (only if openclaw present)
if (Get-Command openclaw -ErrorAction SilentlyContinue) {
  $gs = (openclaw gateway status 2>$null)
  if ($gs -match 'running') { Write-Host "PASS: gateway running" }
  else { Write-Host "INFO: gateway not running — Step 5 will start" }
} else {
  Write-Host "INFO: gateway check skipped — openclaw not installed yet"
}

# Port
$portInUse = Get-NetTCPConnection -LocalPort 18789 -State Listen -ErrorAction SilentlyContinue
if ($portInUse) {
  Write-Host "WARN: port 18789 in use — kill before openclaw onboard"
  $portInUse | Select-Object LocalAddress, LocalPort, OwningProcess
} else {
  Write-Host "PASS: port 18789 free"
}

# Config
$cfgPath = "$env:USERPROFILE\.openclaw\openclaw.json"
if (Test-Path $cfgPath) { Write-Host "PASS: config exists at $cfgPath" }
else { Write-Host "INFO: config not found — Step 6 will create" }
```

---

## STEP 3 — PREREQUISITES

Install Node.js ≥ 22.14 and jq via `winget` (built-in on Windows 10/11). If winget is unavailable, fallback to manual install.

```powershell
# Check winget
if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
  Write-Host "WARN: winget not available — install App Installer from Microsoft Store, then rerun"
  Write-Host "  ms-windows-store://pdp/?ProductId=9NBLGGH4NNS1"
  exit 1
}

# Node
if (Get-Command node -ErrorAction SilentlyContinue) {
  Write-Host "SKIP: node already installed — $(node --version)"
} else {
  Write-Host "INFO: installing Node.js LTS via winget..."
  winget install --id OpenJS.NodeJS.LTS --accept-package-agreements --accept-source-agreements --silent
  # Refresh PATH in current session
  $env:PATH = [System.Environment]::GetEnvironmentVariable("PATH","Machine") + ";" +
              [System.Environment]::GetEnvironmentVariable("PATH","User")
  if (Get-Command node -ErrorAction SilentlyContinue) {
    Write-Host "PASS: node=$(node --version)"
  } else {
    Write-Host "FAIL: node install failed — close and reopen pwsh, then rerun"
    exit 1
  }
}

$nodeMajor = [int]((node --version) -replace 'v','').Split('.')[0]
if ($nodeMajor -ge 22) {
  Write-Host "PASS: node version OK ($(node --version))"
} else {
  Write-Host "WARN: node=$(node --version) — recommend >=22.14; upgrade: winget upgrade OpenJS.NodeJS.LTS"
}

# jq
if (Get-Command jq -ErrorAction SilentlyContinue) {
  Write-Host "SKIP: jq already installed — $(jq --version)"
} else {
  Write-Host "INFO: installing jq via winget..."
  winget install --id jqlang.jq --accept-package-agreements --accept-source-agreements --silent
  $env:PATH = [System.Environment]::GetEnvironmentVariable("PATH","Machine") + ";" +
              [System.Environment]::GetEnvironmentVariable("PATH","User")
  if (Get-Command jq -ErrorAction SilentlyContinue) {
    Write-Host "PASS: jq=$(jq --version)"
  } else {
    Write-Host "FAIL: jq install failed — try: winget install --id jqlang.jq"
    exit 1
  }
}
```

---

## STEP 4 — INSTALL OPENCLAW

```powershell
if (Get-Command openclaw -ErrorAction SilentlyContinue) {
  $v = (openclaw --version 2>$null) ?? 'version unknown'
  Write-Host "SKIP: openclaw already installed — $v"
} else {
  Write-Host "INFO: installing OpenClaw..."
  # Primary installer
  Invoke-Expression (Invoke-WebRequest -UseBasicParsing https://openclaw.ai/install.sh).Content
  # Refresh PATH
  $env:PATH = [System.Environment]::GetEnvironmentVariable("PATH","Machine") + ";" +
              [System.Environment]::GetEnvironmentVariable("PATH","User")
  if (-not (Get-Command openclaw -ErrorAction SilentlyContinue)) {
    Write-Host "INFO: retrying via npm..."
    $env:SHARP_IGNORE_GLOBAL_LIBVIPS = "1"
    npm install -g openclaw@latest
    $env:PATH = [System.Environment]::GetEnvironmentVariable("PATH","Machine") + ";" +
                [System.Environment]::GetEnvironmentVariable("PATH","User")
  }
  if (Get-Command openclaw -ErrorAction SilentlyContinue) {
    $v = (openclaw --version 2>$null) ?? 'installed'
    Write-Host "PASS: openclaw installed — $v"
  } else {
    Write-Host "FAIL: install failed — check node version (>=22.14 required)"
    exit 1
  }
}
```

If `openclaw` not found after install:
```powershell
# Add npm global bin to PATH manually
$npmBin = (npm prefix -g) + "\bin"
$env:PATH += ";$npmBin"
# Make it permanent
[System.Environment]::SetEnvironmentVariable("PATH", $env:PATH, "User")
```

---

## STEP 5 — FIRST-TIME ONBOARDING

Skip this step if the gateway is already running.

```powershell
$gs = (openclaw gateway status 2>$null)
if ($gs -match 'running') {
  Write-Host "SKIP: gateway already running"
  exit 0
}

$portInUse = Get-NetTCPConnection -LocalPort 18789 -State Listen -ErrorAction SilentlyContinue
if ($portInUse) {
  $pid = $portInUse.OwningProcess
  Write-Host "FAIL: port 18789 in use by PID $pid — stop it first: Stop-Process -Id $pid"
  exit 1
} else {
  Write-Host "PASS: port 18789 free"
}
```

PAUSE: Run the onboarding wizard in a new PowerShell 7 window:
```
openclaw onboard --install-daemon
```
Prompts:
1. Auth — skip cloud API keys (BytePlus added in Step 6)
2. Gateway port — press Enter for default 18789
3. Gateway bind — choose loopback
4. Install daemon — yes (Windows service or Task Scheduler, auto-starts on login)

```powershell
Start-Sleep -Seconds 3
$gs = (openclaw gateway status 2>&1)
if ($gs -match 'running') {
  Write-Host "PASS: gateway running"
} else {
  Write-Host "FAIL: gateway not running — run: openclaw doctor"
  Write-Host $gs
  exit 1
}
```

---

## STEP 6 — CONFIGURE BYTEPLUS

Don't have a BytePlus Coding Plan account yet? First month is $9 USD — sign up with a discount:
https://www.byteplus.com/activity/codingplan?ac=MMAUCIS9NT1S&rc=HJA73DT3

Once signed up, choose your preferred model in the web console (the `ark-code-latest` default routes to it automatically):
https://console.byteplus.com/ark/region:ark+ap-southeast-1/openManagement

PAUSE: Ask the user for their BytePlus Coding Plan API key (from the BytePlus Coding Plan console). Then substitute it below as `BYTEPLUS_KEY` and run the block.

```powershell
$BYTEPLUS_KEY  = "your-api-key-here"    # replace with actual key
$BYTEPLUS_BASE = "https://ark.ap-southeast.bytepluses.com/api/coding/v3"

# Guard
if ($BYTEPLUS_KEY -eq "your-api-key-here" -or [string]::IsNullOrEmpty($BYTEPLUS_KEY)) {
  Write-Host "FAIL: BYTEPLUS_KEY placeholder not replaced"
  exit 1
}

$cfgDir  = "$env:USERPROFILE\.openclaw"
$cfgPath = "$cfgDir\openclaw.json"
New-Item -ItemType Directory -Force -Path $cfgDir | Out-Null
if (-not (Test-Path $cfgPath)) { '{}' | Set-Content -Encoding UTF8 $cfgPath }

# Validate key and discover models
Write-Host "INFO: validating key and discovering models..."
$headers = @{ Authorization = "Bearer $BYTEPLUS_KEY" }
try {
  $modelsResp = Invoke-RestMethod -Uri "$BYTEPLUS_BASE/models" -Headers $headers -ErrorAction Stop
  $modelIds = $modelsResp.data | ForEach-Object { $_.id }
  Write-Host "INFO: available models:"
  $modelIds | ForEach-Object { Write-Host "  $_" }

  $MODEL_DEFAULT = "ark-code-latest"

  # Build models array from API response
  $MODELS_ARRAY = $modelsResp.data | ForEach-Object {
    [ordered]@{
      id            = $_.id
      name          = $_.id
      reasoning     = $false
      input         = @("text")
      cost          = [ordered]@{ input = 0; output = 0; cacheRead = 0; cacheWrite = 0 }
      contextWindow = if ($_.context_length)        { $_.context_length }        else { 131072 }
      maxTokens     = if ($_.max_completion_tokens) { $_.max_completion_tokens } else { 32768  }
    }
  }
  Write-Host "PASS: key valid — default model=$MODEL_DEFAULT"
} catch {
  Write-Host "WARN: could not query /models — using hardcoded list"
  $MODEL_DEFAULT = "ark-code-latest"
  $MODELS_ARRAY = @(
    [ordered]@{ id="bytedance-seed-code"; name="ByteDance Seed Code"; reasoning=$false; input=@("text"); cost=[ordered]@{input=0;output=0;cacheRead=0;cacheWrite=0}; contextWindow=262144; maxTokens=131072 },
    [ordered]@{ id="kimi-k2.5";           name="Kimi K2.5";           reasoning=$false; input=@("text"); cost=[ordered]@{input=0;output=0;cacheRead=0;cacheWrite=0}; contextWindow=262144; maxTokens=32768  },
    [ordered]@{ id="gpt-oss-120b";        name="GPT OSS 120B";        reasoning=$false; input=@("text"); cost=[ordered]@{input=0;output=0;cacheRead=0;cacheWrite=0}; contextWindow=131072; maxTokens=65536  },
    [ordered]@{ id="glm-5.1";             name="GLM 5.1";             reasoning=$false; input=@("text"); cost=[ordered]@{input=0;output=0;cacheRead=0;cacheWrite=0}; contextWindow=131072; maxTokens=65536  },
    [ordered]@{ id="glm-4.7";             name="GLM 4.7";             reasoning=$false; input=@("text"); cost=[ordered]@{input=0;output=0;cacheRead=0;cacheWrite=0}; contextWindow=200000; maxTokens=131072 },
    [ordered]@{ id="dola-seed-2.0-code";  name="Dola Seed 2.0 Code";  reasoning=$false; input=@("text"); cost=[ordered]@{input=0;output=0;cacheRead=0;cacheWrite=0}; contextWindow=262144; maxTokens=131072 },
    [ordered]@{ id="dola-seed-2.0-pro";   name="Dola Seed 2.0 Pro";   reasoning=$false; input=@("text"); cost=[ordered]@{input=0;output=0;cacheRead=0;cacheWrite=0}; contextWindow=262144; maxTokens=131072 },
    [ordered]@{ id="dola-seed-2.0-lite";  name="Dola Seed 2.0 Lite";  reasoning=$false; input=@("text"); cost=[ordered]@{input=0;output=0;cacheRead=0;cacheWrite=0}; contextWindow=262144; maxTokens=131072 }
  )
}

# Build patch object — literal values (template vars don't expand in provider config)
$patch = [ordered]@{
  models = [ordered]@{
    mode      = "merge"
    providers = [ordered]@{
      byteplus = [ordered]@{
        baseUrl  = $BYTEPLUS_BASE
        api      = "openai-completions"
        apiKey   = $BYTEPLUS_KEY
        models   = $MODELS_ARRAY
      }
    }
  }
  agents = [ordered]@{
    defaults = [ordered]@{
      model          = [ordered]@{ primary = "byteplus/$MODEL_DEFAULT" }
      timeoutSeconds = 600
    }
  }
}

# Write patch to temp file
$patchJson = $patch | ConvertTo-Json -Depth 10
$patchPath = "$env:TEMP\byteplus-patch.json"
[System.IO.File]::WriteAllText($patchPath, $patchJson, [System.Text.Encoding]::UTF8)

# Merge with existing config using jq (capture first, then write — avoids LASTEXITCODE from pipeline)
$mergedJson = jq -s '.[0] * .[1]' $cfgPath $patchPath
if ($LASTEXITCODE -ne 0) {
  Write-Host "FAIL: jq merge failed"
  exit 1
}
[System.IO.File]::WriteAllText($cfgPath, $mergedJson, [System.Text.Encoding]::UTF8)
Remove-Item $patchPath -ErrorAction SilentlyContinue
Write-Host "PASS: config written to $cfgPath"

# Verify
$storedKey = jq -r '.models.providers.byteplus.apiKey // empty' $cfgPath
if ($storedKey) {
  Write-Host "PASS: API key present in provider config"
} else {
  Write-Host "FAIL: API key missing from provider config"
  exit 1
}
```

---

## STEP 7 — RESTART GATEWAY

```powershell
openclaw gateway restart
Start-Sleep -Seconds 2

$gs = (openclaw gateway status 2>&1)
if ($gs -match 'running') {
  Write-Host "PASS: gateway running"
} else {
  Write-Host "FAIL: gateway not running — run: openclaw doctor"
  Write-Host $gs
  exit 1
}
```

---

## STEP 8 — TEST

```powershell
$cfgPath = "$env:USERPROFILE\.openclaw\openclaw.json"
$MP = jq -r '.agents.defaults.model.primary' $cfgPath
Write-Host "INFO: default model = $MP"

# Via OpenClaw
Write-Host "INFO: testing via OpenClaw..."
openclaw infer model run --model $MP --prompt "Say hi." 2>&1

# All models via OpenClaw
Write-Host "INFO: testing all models..."
$models = jq -r '.models.providers.byteplus.models[].id' $cfgPath
foreach ($model in $models) {
  Write-Host -NoNewline "byteplus/${model}: "
  openclaw infer model run --model "byteplus/$model" --prompt "Say hi." 2>&1 | Select-Object -Last 1
}

# Direct API test (bypasses OpenClaw — isolates key/URL issues)
Write-Host "INFO: direct API test..."
$KEY   = jq -r '.models.providers.byteplus.apiKey'           $cfgPath
$BASE  = jq -r '.models.providers.byteplus.baseUrl'          $cfgPath
$MODEL = jq -r '.models.providers.byteplus.models[0].id'     $cfgPath

$body = @{
  model      = $MODEL
  messages   = @(@{ role = "user"; content = "Say hi." })
  max_tokens = 50
  stream     = $false
} | ConvertTo-Json -Depth 5

$resp = Invoke-RestMethod -Method Post -Uri "$BASE/chat/completions" `
  -Headers @{ Authorization = "Bearer $KEY"; "Content-Type" = "application/json" } `
  -Body $body -ErrorAction SilentlyContinue

if ($resp.choices) {
  Write-Host "PASS: $($resp.choices[0].message.content)"
} elseif ($resp.error) {
  Write-Host "FAIL: $($resp.error.message)"
} else {
  Write-Host "WARN: unexpected response — $($resp | ConvertTo-Json -Depth 3)"
}
```

---

## OPTIONAL STEP 9 — GEMINI EMBEDDINGS

OpenClaw uses an embedding provider for semantic memory search. Add your Gemini API key to enable it.

PAUSE: Ask the user for their Google Gemini API key (from Google AI Studio: https://aistudio.google.com/apikey). Then substitute below and run.

```powershell
$GEMINI_KEY = "your-gemini-key-here"   # replace with actual key
if ($GEMINI_KEY -eq "your-gemini-key-here" -or [string]::IsNullOrEmpty($GEMINI_KEY)) {
  Write-Host "FAIL: GEMINI_KEY placeholder not replaced"
  exit 1
}

$cfgPath = "$env:USERPROFILE\.openclaw\openclaw.json"

# Merge Gemini key into env section
$mergedJson = jq --arg gkey $GEMINI_KEY '. * {"env": {"GEMINI_API_KEY": $gkey}}' $cfgPath
if ($LASTEXITCODE -ne 0) {
  Write-Host "FAIL: jq failed"
  exit 1
}
[System.IO.File]::WriteAllText($cfgPath, $mergedJson, [System.Text.Encoding]::UTF8)
Write-Host "PASS: Gemini key written to env section"

openclaw gateway restart
Start-Sleep -Seconds 2
openclaw memory status --deep 2>&1
```

---

## OPTIONAL STEP 10 — GOG SKILL (GOOGLE WORKSPACE)

> **Note:** `gogcli` is not packaged for Windows. If you need Google Workspace integration:
> - Use Windows Subsystem for Linux (WSL2) and follow `byteplus-setup-mac.md` Step 9 inside WSL.
> - Or run OpenClaw on a macOS or Linux machine for gog support.

```powershell
# Check if running in WSL (wsl.exe available as a bridge)
if (Get-Command wsl -ErrorAction SilentlyContinue) {
  Write-Host "INFO: WSL available — you can run gog setup inside WSL:"
  Write-Host "  wsl brew install gogcli"
  Write-Host "  wsl gog auth add your-google-email@gmail.com"
} else {
  Write-Host "INFO: WSL not installed — gog skill not available on this machine"
  Write-Host "  To install WSL: wsl --install (requires reboot)"
}
```

---

## OPTIONAL STEP 11 — BENCHMARK ALL MODELS

Measures raw API throughput per model. PowerShell 7+ supports `ForEach-Object -Parallel` for concurrent requests.

```powershell
$cfgPath = "$env:USERPROFILE\.openclaw\openclaw.json"
$KEY     = jq -r '.models.providers.byteplus.apiKey'  $cfgPath
$BASE    = jq -r '.models.providers.byteplus.baseUrl' $cfgPath
$MODELS  = jq -r '.models.providers.byteplus.models[].id' $cfgPath
$PROMPT  = 'Write a fizzbuzz function in Python.'

Write-Host "Benchmarking BytePlus models (parallel, max 5 concurrent)..."
Write-Host "---"

$MODELS | ForEach-Object -Parallel {
  $model  = $_
  $key    = $using:KEY
  $base   = $using:BASE
  $prompt = $using:PROMPT

  $body = @{
    model      = $model
    messages   = @(@{ role = "user"; content = $prompt })
    max_tokens = 200
    stream     = $false
  } | ConvertTo-Json -Depth 5

  $t0 = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
  try {
    $resp = Invoke-RestMethod -Method Post -Uri "$base/chat/completions" `
      -Headers @{ Authorization = "Bearer $key"; "Content-Type" = "application/json" } `
      -Body $body -ErrorAction Stop
    $t1      = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
    $elapsed = $t1 - $t0
    $tokens  = $resp.usage.completion_tokens
    $tps     = if ($tokens -gt 0) { [math]::Round($tokens / ($elapsed / 1000), 1) } else { "?" }
    "{0,-25} | {1,6}ms | {2} tokens | {3} tok/s" -f $model, $elapsed, $tokens, $tps
  } catch {
    "{0,-25} | FAIL: {1}" -f $model, $_.Exception.Message
  }
} -ThrottleLimit 5
```

If `ForEach-Object -Parallel` is unavailable (older PS 7 build), run sequentially:

```powershell
$cfgPath = "$env:USERPROFILE\.openclaw\openclaw.json"
$KEY    = jq -r '.models.providers.byteplus.apiKey'  $cfgPath
$BASE   = jq -r '.models.providers.byteplus.baseUrl' $cfgPath
$MODELS = jq -r '.models.providers.byteplus.models[].id' $cfgPath
$PROMPT = 'Write a fizzbuzz function in Python.'

foreach ($model in $MODELS) {
  $body = @{
    model      = $model
    messages   = @(@{ role = "user"; content = $PROMPT })
    max_tokens = 200
    stream     = $false
  } | ConvertTo-Json -Depth 5

  $t0 = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
  try {
    $resp    = Invoke-RestMethod -Method Post -Uri "$BASE/chat/completions" `
      -Headers @{ Authorization = "Bearer $KEY"; "Content-Type" = "application/json" } `
      -Body $body -ErrorAction Stop
    $t1      = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
    $elapsed = $t1 - $t0
    $tokens  = $resp.usage.completion_tokens
    $tps     = if ($tokens -gt 0) { [math]::Round($tokens / ($elapsed / 1000), 1) } else { "?" }
    "{0,-25} | {1,6}ms | {2} tokens | {3} tok/s" -f $model, $elapsed, $tokens, $tps
  } catch {
    "{0,-25} | FAIL: {1}" -f $model, $_.Exception.Message
  }
}
```

---

## VERIFY

```powershell
$cfgPath = "$env:USERPROFILE\.openclaw\openclaw.json"
if (Get-Command openclaw -ErrorAction SilentlyContinue) { Write-Host "PASS: openclaw" } else { Write-Host "FAIL: openclaw not found" }
$valid = jq empty $cfgPath 2>$null; if ($LASTEXITCODE -eq 0) { Write-Host "PASS: config valid JSON" } else { Write-Host "FAIL: invalid JSON" }
$KEY  = jq -r '.models.providers.byteplus.apiKey // empty' $cfgPath
if ($KEY) { Write-Host "PASS: API key in provider config" } else { Write-Host "FAIL: API key missing" }
$BASE = jq -r '.models.providers.byteplus.baseUrl // empty' $cfgPath
Write-Host "INFO: baseUrl=$BASE"
$gs = (openclaw gateway status 2>&1)
if ($gs -match 'running') { Write-Host "PASS: gateway running" } else { Write-Host "FAIL: not running" }
```

---

## UPDATE

```powershell
openclaw doctor      # check for issues first
openclaw update      # built-in updater
npm install -g openclaw@latest   # fallback if openclaw update unavailable
openclaw gateway restart
openclaw gateway status
```

---

## TROUBLESHOOTING

| symptom | cause | fix |
|---------|-------|-----|
| `openclaw` not found after install | PATH not updated | Close and reopen pwsh; or: `$env:PATH += ";$(npm prefix -g)"` |
| `winget` not found | App Installer not installed | Install from Microsoft Store (search "App Installer") |
| 401 from API | key wrong or expired | Regenerate in BytePlus Coding Plan console |
| 403 from API | region lock | BytePlus `ap-southeast` requires APAC region — try VPN |
| gateway not running | config invalid JSON | `jq . $env:USERPROFILE\.openclaw\openclaw.json` |
| inference timeout | timeout too low | Confirm `timeoutSeconds: 600` at `agents.defaults` |
| sharp build error | libvips conflict | `$env:SHARP_IGNORE_GLOBAL_LIBVIPS=1; npm install -g openclaw@latest` |
| gog not available | Windows limitation | Use WSL2 or a macOS machine for gog skill |
| memory status fails | Gemini key missing | Add `GEMINI_API_KEY` to `env` section, restart gateway |
| Invoke-RestMethod SSL error | corporate proxy/cert | Add `-SkipCertificateCheck` flag (PS 7+) |

```powershell
openclaw doctor
jq . $env:USERPROFILE\.openclaw\openclaw.json
openclaw gateway status
```

---

## UNINSTALL

### Remove BytePlus provider only

```powershell
$cfgPath = "$env:USERPROFILE\.openclaw\openclaw.json"
$cleaned = jq '
  del(.models.providers.byteplus) |
  del(.agents.defaults.model) |
  if .models.providers == {} then del(.models.providers) else . end
' $cfgPath
if ($LASTEXITCODE -eq 0) {
  [System.IO.File]::WriteAllText($cfgPath, $cleaned, [System.Text.Encoding]::UTF8)
  Write-Host "PASS: BytePlus removed from config"
} else {
  Write-Host "FAIL: jq failed — config unchanged"
}
openclaw gateway restart
```

### Full OpenClaw uninstall

```powershell
# Stop daemon (Task Scheduler or service)
openclaw gateway stop 2>$null
schtasks /Delete /TN "OpenClaw Gateway" /F 2>$null
# Uninstall package
npm uninstall -g openclaw && Write-Host "PASS: openclaw removed"
# Remove config
Remove-Item -Recurse -Force "$env:USERPROFILE\.openclaw" -ErrorAction SilentlyContinue
Write-Host "PASS: config removed"
```
