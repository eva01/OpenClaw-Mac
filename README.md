<!-- README.md — OpenClaw + Local LLM setup (Apple Silicon Mac entry point) -->
<!-- Human summary: Two-step entry point for running OpenClaw with a local LLM on Apple Silicon Mac.
     Step 1 installs prerequisites and OpenClaw, gets the gateway running. Step 2 downloads the model,
     sets up the mlx inference stack (venv, model server, proxy), and configures OpenClaw.
     Apple Silicon (M1/M2/M3/M4) only — mlx does not run on Intel Mac or non-Mac platforms.
     Full setup guide: local-llm-setup-mac.md. Telegram setup: setup-telegram.md. -->

CONTEXT: AI agent executing this file. There are two steps:
- STEP 1: Install prerequisites and OpenClaw, start the gateway
- STEP 2: Download the model, set up the mlx inference stack, configure OpenClaw

This setup is Apple Silicon Mac only. Config: `~/.openclaw/openclaw.json` (hot-reloads on save).
If you see files other than this README on this branch, you are on the wrong branch.

CONSTRAINTS:
- platform: macOS Apple Silicon (M1/M2/M3/M4) only — mlx does not run on Intel Mac or x86
- min_ram: 16GB unified memory (32GB recommended for 27B+ models)
- homebrew: required
- node: >=22
- python: 3 (pre-installed on macOS)
- deps: pm2 (`npm install -g pm2`), huggingface-cli (`pip3 install huggingface-hub`)
- proxy_rule: OpenClaw → proxy → model server (never connect OpenClaw directly to model server)
- non_interactive: true — all blocks run unattended unless marked PAUSE
- pause_policy: PAUSE blocks require the human to act; agent stops and waits for confirmation

## MODELS

| id | params | engine | use_case | quant | vram |
|----|--------|--------|----------|-------|------|
| GLM-4.7-flash | 30B (A3B) | mlx_lm | tool-calling, agent tasks | 8bit | ~18GB |
| kimi-linear | 48B (A3B) | mlx_lm | long-context, fast prefill | 8bit | ~28GB |

Default: `GLM-4.7-flash` — best for tool-calling and agent tasks.

---

## STEP 1 — INSTALL OPENCLAW

This step installs all prerequisites, installs OpenClaw, and starts the gateway.
No model needed yet. Skip any sub-block whose check already passes.

### Check system

```bash
# Apple Silicon guard
arch=$(uname -m)
chip=$(sysctl -n machdep.cpu.brand_string 2>/dev/null || system_profiler SPHardwareDataType | grep Chip | awk -F': ' '{print $2}')
if [[ "$arch" != "arm64" ]]; then
  echo "FAIL: Apple Silicon required. Detected: $arch ($chip). This guide does not apply."; exit 1
fi
echo "PASS: Apple Silicon — $chip"

# RAM
RAM_GB=$(( $(sysctl -n hw.memsize) / 1024 / 1024 / 1024 ))
[[ $RAM_GB -ge 16 ]] && echo "PASS: ${RAM_GB}GB RAM" || echo "WARN: ${RAM_GB}GB RAM — 16GB minimum; 32GB recommended for 27B+ models"

# Xcode CLT — required by Homebrew
xcode-select -p &>/dev/null && echo "PASS: Xcode CLT" || echo "FAIL: Xcode CLT not installed — see PAUSE below"

# Homebrew
command -v brew &>/dev/null && echo "PASS: brew $(brew --version | head -1)" || echo "INFO: Homebrew not installed — will install"

# Node
command -v node &>/dev/null && echo "PASS: node=$(node --version)" || echo "INFO: node not found — will install"

# pm2
command -v pm2 &>/dev/null && echo "PASS: pm2=$(pm2 --version)" || echo "INFO: pm2 not found — will install"

# HuggingFace CLI
command -v huggingface-cli &>/dev/null && echo "PASS: huggingface-cli" || echo "INFO: huggingface-cli not found — will install"

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

### Install prerequisites and OpenClaw

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

# pm2
command -v pm2 &>/dev/null || npm install -g pm2
echo "PASS: pm2=$(pm2 --version)"

# HuggingFace CLI
if ! command -v huggingface-cli &>/dev/null; then
  pip3 install huggingface-hub
fi
command -v huggingface-cli &>/dev/null && echo "PASS: huggingface-cli installed" || echo "WARN: huggingface-cli not in PATH — try: pip3 install --user huggingface-hub"

# OpenClaw
if command -v openclaw &>/dev/null; then
  echo "SKIP: openclaw already installed — $(openclaw --version 2>/dev/null || echo version unknown)"
else
  curl -fsSL https://openclaw.ai/install.sh | bash
  command -v openclaw &>/dev/null || SHARP_IGNORE_GLOBAL_LIBVIPS=1 npm install -g openclaw@latest
  command -v openclaw &>/dev/null && echo "PASS: openclaw installed" || { echo "FAIL: install failed — check node version (>=22)"; exit 1; }
fi
```

### First-time onboarding

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

PAUSE: Log in to HuggingFace (needed for model download in Step 2):
```
huggingface-cli login
```
Paste your HuggingFace token (read access is enough). Then tell the agent to continue.

---

## STEP 2 — LOCAL MODEL

Downloads the model, sets up the mlx inference stack, and configures OpenClaw.
Run only the sub-blocks matching your chosen model.

### Download model

```bash
# GLM-4.7-flash (recommended default)
huggingface-cli download mlx-community/GLM-4.7-flash-8bit --local-dir ~/models/GLM-4.7-flash-8bit
echo "PASS: model downloaded to ~/models/GLM-4.7-flash-8bit"
```

```bash
# kimi-linear (alternative — 32GB RAM required)
huggingface-cli download mlx-community/kimi-k1.5-linear-8bit --local-dir ~/models/kimi-linear-8bit
echo "PASS: model downloaded to ~/models/kimi-linear-8bit"
```

### Set up venv (shared across all models)

```bash
python3 -m venv ~/models/mlx-venv
source ~/models/mlx-venv/bin/activate
# Clone mlx-vlm via HTTP/1.1 (avoids stream errors on some networks)
git -c http.version=HTTP/1.1 clone --depth 1 https://github.com/Blaizzy/mlx-vlm.git /tmp/mlx-vlm
pip install /tmp/mlx-vlm
pip install mlx-lm torch torchvision
echo "PASS: venv ready at ~/models/mlx-venv"
```

### Start model server (pm2)

Check port is free:
```bash
lsof -i :10004  # must be empty; kill any existing process first
```

GLM-4.7-flash / kimi-linear (mlx_lm):
```bash
pm2 start ~/models/mlx-venv/bin/python3 --name "glm-4.7-flash" --interpreter none \
  -- -m mlx_lm.server --model ~/models/GLM-4.7-flash-8bit --host 0.0.0.0 --port 10004
pm2 save
```

Verify:
```bash
curl -sf http://127.0.0.1:10004/v1/models | python3 -c "import sys,json; print('PASS:', json.load(sys.stdin))" \
  || echo "FAIL: model server not ready — check: pm2 logs glm-4.7-flash"
```

Persist across reboots:
```bash
pm2 startup
# pm2 startup prints a sudo command — copy and run it exactly as printed, then:
pm2 save
```

### Start proxy (pm2)

The proxy translates field names between OpenClaw and the mlx server.

Check proxy port is free:
```bash
lsof -i :10014  # must be empty
```

```bash
PROXY_SCRIPT="$HOME/Documents/GitHub/OpenClaw-Mac/mlx-proxy.py"
pm2 start ~/models/mlx-venv/bin/python3 --name "mlx-proxy-glm" --interpreter none \
  -- "$PROXY_SCRIPT" --host 0.0.0.0 --port 10014 --upstream http://127.0.0.1:10004 --strip-model
pm2 save
```

Verify:
```bash
curl -sf http://127.0.0.1:10014/v1/models | python3 -c "import sys,json; print('PASS:', json.load(sys.stdin))" \
  || echo "FAIL: proxy not responding"
```

### Configure OpenClaw

```bash
mkdir -p ~/.openclaw
[[ -f ~/.openclaw/openclaw.json ]] || echo '{}' > ~/.openclaw/openclaw.json
```

Write config for GLM-4.7-flash (mlx_lm) — merge into `~/.openclaw/openclaw.json`:
```json
{
  "models": {
    "mode": "merge",
    "providers": {
      "local-glm": {
        "baseUrl": "http://127.0.0.1:10014",
        "apiKey": "DEADBEEF",
        "api": "openai-completions",
        "models": [{
          "id": "GLM-4.7-flash",
          "name": "GLM 4.7 Flash",
          "reasoning": false,
          "input": ["text"],
          "cost": {"input":0,"output":0,"cacheRead":0,"cacheWrite":0},
          "contextWindow": 131072,
          "maxTokens": 16384
        }]
      }
    }
  },
  "agents": {
    "defaults": {
      "model": {"primary": "local-glm/GLM-4.7-flash"},
      "models": {"local-glm/GLM-4.7-flash": {"alias": "glm-flash", "streaming": false}},
      "timeoutSeconds": 600
    }
  }
}
```

Restart gateway to apply config:
```bash
openclaw gateway restart && sleep 2
openclaw gateway status 2>&1 | grep -qi "running" \
  && echo "PASS: gateway running" \
  || { echo "FAIL: gateway not running — run: openclaw doctor"; exit 1; }
```

End-to-end test:
```bash
curl -s -X POST http://127.0.0.1:10014/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"messages":[{"role":"user","content":"Say hello."}],"stream":false,"max_tokens":4000}' \
  | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['choices'][0]['message']['content'])"
# GLM is a reasoning model — needs max_tokens>=4000 to finish thinking
# expect: non-empty response
```

```bash
openclaw dashboard   # opens browser — do NOT navigate to bare URL directly
```

---

## NEXT STEP — TELEGRAM BOT (OPTIONAL)

OpenClaw is now running with a local model. To chat with it and approve agent actions from your phone, set up the Telegram bot next:

```
setup-telegram.md
```

---

## TROUBLESHOOTING

| symptom | fix |
|---------|-----|
| `openclaw` not found after install | `export PATH="$(npm prefix -g)/bin:$PATH"` then re-run |
| HTTP 422 from model server | old mlx_vlm from PyPI — reinstall from GitHub: `git -c http.version=HTTP/1.1 clone --depth 1 https://github.com/Blaizzy/mlx-vlm.git /tmp/mlx-vlm && pip install /tmp/mlx-vlm` |
| model server exits immediately | `pm2 logs <name>` — usually a port conflict or bad flag |
| connection refused on proxy port | proxy not running — `pm2 list`; restart proxy block |
| OOM / model too large | smaller quant or lower param model |
| gateway not running | `openclaw doctor` → check JSON is valid: `jq . ~/.openclaw/openclaw.json` |
| inference timeout | confirm `timeoutSeconds: 600` in agents.defaults |
| sharp build error | `SHARP_IGNORE_GLOBAL_LIBVIPS=1 npm install -g openclaw@latest` |
| pm2 processes not surviving reboot | run `pm2 startup`, execute the printed sudo command, then `pm2 save` |
| anything else | `openclaw doctor` |

### Update OpenClaw

```bash
openclaw update
openclaw gateway restart
openclaw doctor
```

---

## DETAILED GUIDE

For full troubleshooting, advanced proxy configuration, monitoring tools, Discord setup, skills, cloud fallback config, and uninstall:

- **Full setup guide**: `local-llm-setup-mac.md`
- **Telegram bot**: `setup-telegram.md` — connect OpenClaw to a Telegram bot so you can chat with it and approve agent actions from your phone
