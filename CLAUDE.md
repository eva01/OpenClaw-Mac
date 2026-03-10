# OpenClaw + Local LLM — Apple Silicon Mac

<!--
  Human summary: Setup guide for running OpenClaw (AI agent platform) with local LLMs
  on Apple Silicon Mac using mlx_lm / mlx_vlm as inference backend. Covers model
  selection, venv setup, pm2 process management, proxy configuration, OpenClaw config,
  Telegram channel integration, Discord auth, recommended skills (including SecureClaw),
  and memory/GPU monitoring tools (macmon, mactop, asitop, fluidtop).
  No cloud API required — fully local and private. Script: setup-telegram.sh for automation.
-->

CONTEXT: AI agent executing this file. Run or configure each step as directed. Config file: `~/.openclaw/openclaw.json` (hot-reloads on save). Execute only the block matching the chosen model — do not run both mlx_vlm and mlx_lm blocks.

STOP_IF_NOT_APPLE_SILICON: Before proceeding, verify the machine is Apple Silicon. If not, halt immediately and inform the user this guide does not apply.
```bash
arch=$(uname -m)
chip=$(sysctl -n machdep.cpu.brand_string 2>/dev/null || system_profiler SPHardwareDataType | grep Chip | awk -F': ' '{print $2}')
if [[ "$arch" != "arm64" ]]; then
  echo "ERROR: This guide requires Apple Silicon (arm64). Detected: $arch ($chip). Halting."
  exit 1
fi
echo "OK: Apple Silicon confirmed — $chip"
```

## CONSTRAINTS
- platform: macOS Apple Silicon (M1/M2/M3/M4) ONLY — Intel Mac and non-Mac platforms are unsupported; mlx framework does not run on x86
- homebrew: required (`/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"`)
- node: >=22 (`brew install node`)
- python: 3 (pre-installed on macOS; or `brew install python`)
- min_ram: 16GB unified memory (32GB for 27B+ models)
- deps_global: pm2 (`npm install -g pm2`), huggingface-cli (`pip install huggingface-hub && huggingface-cli login`)
- venv_path: `~/models/mlx-venv` (shared across all models — contains framework, not weights)
- proxy_rule: OpenClaw → proxy port → model server. Never connect OpenClaw directly to model server.
- port_convention: model_server=10002/10004/10006..., proxy=model_port+10 (10012/10014/10016...)
- proxy_script_path: set PROXY_SCRIPT before Step 4 (see below)
- openclaw_json: `~/.openclaw/openclaw.json` — create if missing (`mkdir -p ~/.openclaw && echo '{}' > ~/.openclaw/openclaw.json`)
- model_selection: pick ONE model from the table; run only the matching Step 3 + Step 4 block

## MODELS

| id | params | engine | use_case | quant | vram |
|----|--------|--------|----------|-------|------|
| GLM-4.7-flash | 30B (A3B) | mlx_lm | tool-calling, agent tasks | 8bit | ~18GB |
| kimi-linear | 48B (A3B) | mlx_lm | long-context, fast prefill | 8bit | ~28GB |
| Qwen3.5-35B-A3B | 35B (A3B) | mlx_vlm | multimodal, fast | 8bit | ~20GB |
| Qwen3.5-27B | 27B dense | mlx_vlm | multimodal, better agent than 35B-A3B | 5bit | ~18GB |
| Qwen3.5-9B | 9B | mlx_vlm | multimodal, low memory | 8bit | ~10GB |

engine_rule: mlx_vlm=multimodal+tool-calling (Qwen3.5 series); mlx_lm=text-only+faster (GLM/kimi)
model_id_in_config: mlx_vlm uses full filesystem path as id; mlx_lm uses model name string only
recommend: GLM-4.7-flash for agent/tool-calling; kimi-linear for long docs; Qwen3.5-9B for multimodal+low RAM

## STEP 0 — DOWNLOAD MODEL

```bash
huggingface-cli download mlx-community/<MODEL_ID> --local-dir ~/models/<MODEL_ID>
# example: mlx-community/Qwen3.5-9B-8bit → ~/models/Qwen3.5-9B-8bit
```

## STEP 1 — VENV

mlx_lm is a dependency of mlx_vlm and will be installed automatically. Both engines share this venv.

```bash
python3 -m venv ~/models/mlx-venv
source ~/models/mlx-venv/bin/activate
# git+https URL fails with HTTP/2 stream errors on some networks — clone manually instead:
git -c http.version=HTTP/1.1 clone --depth 1 https://github.com/Blaizzy/mlx-vlm.git /tmp/mlx-vlm
pip install /tmp/mlx-vlm                                      # always install mlx_vlm regardless of engine
pip install mlx-lm torch torchvision                          # mlx-lm explicit for GLM/kimi users
```

CONSTRAINTS:
- mlx_vlm must be installed from GitHub main (cloned via HTTP/1.1), not PyPI
- always install mlx_vlm even if only using mlx_lm engine — keeps venv consistent
- mlx_lm must be installed explicitly if using GLM-4.7-flash or kimi-linear
- never copy venv folder (hardcoded absolute paths); recreate with `python3 -m venv` at new location

## STEP 2 — INSTALL OPENCLAW

```bash
curl -fsSL https://openclaw.ai/install.sh | bash
```

sharp_build_error_fix: `SHARP_IGNORE_GLOBAL_LIBVIPS=1 npm install -g openclaw@latest`

### First-time setup — run the interactive wizard

OpenClaw's onboarding wizard walks you through auth, gateway port, and daemon install. **Run this in your terminal** (not via an AI agent — it requires you to read prompts and make choices):

```bash
openclaw onboard --install-daemon
```

The wizard will ask:
1. **Auth choice** — for local-only setup, skip cloud API keys for now; you can add them later via config
2. **Gateway port** — default `18789` is fine
3. **Gateway bind** — choose `loopback` (local only) unless you need remote access
4. **Install daemon** — say yes to auto-start on login

Once done, open the dashboard to confirm everything is running:

```bash
openclaw dashboard   # opens browser with token pre-filled — do NOT navigate to the bare URL directly
```

### Scripted / non-interactive (AI agent use)

Skip the wizard and write config directly (Steps 3–5 cover this). For a quick non-interactive install with a cloud key:

```bash
openclaw onboard --non-interactive \
  --auth-choice anthropic-api-key \
  --anthropic-api-key "sk-ant-..." \
  --gateway-port 18789 \
  --gateway-bind loopback \
  --install-daemon
```

verify: `openclaw gateway status`

## STEP 3 — MODEL SERVER (pm2)

NOTE: run only the block matching your chosen model. Check for port conflict before starting:
```bash
lsof -i :10002  # or :10004 — must be empty; kill any existing process first
```

mlx_vlm only (Qwen3.5 series):
```bash
pm2 start ~/models/mlx-venv/bin/python3 --name "qwen3.5-9b" --interpreter none \
  -- -m mlx_vlm.server --host 0.0.0.0 --port 10002
pm2 save
```

NOTE (mlx_vlm 0.4.0+): `--model` and `--trust-remote-code` flags were removed from server startup. The model is now loaded per-request via the `model` field in API calls. The proxy and OpenClaw config handle this automatically.

mlx_lm only (GLM-4.7-flash / kimi-linear) — no --trust-remote-code flag:
```bash
pm2 start ~/models/mlx-venv/bin/python3 --name "glm-4.7-flash" --interpreter none \
  -- -m mlx_lm.server --model ~/models/GLM-4.7-flash-8bit --host 0.0.0.0 --port 10004
pm2 save
```

verify_model_server_healthy (run before Step 4):
```bash
# mlx_vlm
curl -sf http://127.0.0.1:10002/v1/models | python3 -c "import sys,json; print('OK:', json.load(sys.stdin))" \
  || echo "FAIL: model server not ready — check: pm2 logs qwen3.5-9b"

# mlx_lm
curl -sf http://127.0.0.1:10004/v1/models | python3 -c "import sys,json; print('OK:', json.load(sys.stdin))" \
  || echo "FAIL: model server not ready — check: pm2 logs glm-4.7-flash"
```

persist_across_reboots:
```bash
pm2 startup
# pm2 startup prints a sudo command — copy and run that command exactly as printed, then:
pm2 save
```

## STEP 4 — PROXY (pm2)

PURPOSE: renames `max_completion_tokens`→`max_tokens` by default. Additional field stripping is opt-in via flags.
- default: rename fields only (ENABLE_RENAME_FIELDS=true)
- --strip-model: removes `model` field (required for mlx_lm which ignores model routing)
- full field stripping not enabled by default — if getting 422s, check mlx_vlm version first

Set proxy script path first (avoids cwd-dependent breakage):
```bash
PROXY_SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/mlx-proxy.py"
# or hardcode: PROXY_SCRIPT="$HOME/Documents/GitHub/OpenClaw-Mac/mlx-proxy.py"
```

Check proxy port is free:
```bash
lsof -i :10012  # or :10014 — must be empty
```

mlx_vlm (Qwen3.5):
```bash
pm2 start ~/models/mlx-venv/bin/python3 --name "mlx-proxy-qwen" --interpreter none \
  -- "$PROXY_SCRIPT" --host 0.0.0.0 --port 10012 --upstream http://127.0.0.1:10002
pm2 save
```

mlx_lm (GLM/kimi) — --strip-model required:
```bash
pm2 start ~/models/mlx-venv/bin/python3 --name "mlx-proxy-glm" --interpreter none \
  -- "$PROXY_SCRIPT" --host 0.0.0.0 --port 10014 --upstream http://127.0.0.1:10004 --strip-model
pm2 save
```

verify_proxy:
```bash
curl -sf http://127.0.0.1:10012/v1/models || echo "FAIL: proxy not responding"
```

## STEP 5 — OPENCLAW CONFIG

CONFIG_RULES:
- baseUrl → proxy port (never model server directly)
- apiKey → any non-empty string ("DEADBEEF")
- api → "openai-completions"
- streaming → false (more reliable for local inference)
- timeoutSeconds → 600
- model reference format → `provider/model_id` (e.g. `local//abs/path` or `local-glm/GLM-4.7-flash`)
- mlx_vlm model id → full filesystem path; mlx_lm model id → model name string
- input → ["text","image"] for mlx_vlm; ["text"] for mlx_lm
- all costs → 0
- create file if missing: `mkdir -p ~/.openclaw && echo '{}' > ~/.openclaw/openclaw.json`

Qwen3.5-9B (mlx_vlm):
```json
{
  "models": {
    "mode": "merge",
    "providers": {
      "local": {
        "baseUrl": "http://127.0.0.1:10012",
        "apiKey": "DEADBEEF",
        "api": "openai-completions",
        "models": [{
          "id": "/Users/you/models/Qwen3.5-9B-8bit",
          "name": "Qwen 3.5 9B",
          "reasoning": false,
          "input": ["text", "image"],
          "cost": {"input":0,"output":0,"cacheRead":0,"cacheWrite":0},
          "contextWindow": 262144,
          "maxTokens": 32768
        }]
      }
    }
  },
  "agents": {
    "defaults": {
      "model": {"primary": "local//Users/you/models/Qwen3.5-9B-8bit"},
      "models": {"local//Users/you/models/Qwen3.5-9B-8bit": {"alias": "qwen3.5-9b", "streaming": false}},
      "timeoutSeconds": 600
    }
  }
}
```

GLM-4.7-flash (mlx_lm):
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

local-first + cloud fallback (complete config — both providers and agents blocks required):
```json
{
  "models": {
    "mode": "merge",
    "providers": {
      "local": {
        "baseUrl": "http://127.0.0.1:10012",
        "apiKey": "DEADBEEF",
        "api": "openai-completions",
        "models": [{
          "id": "/Users/you/models/Qwen3.5-9B-8bit",
          "name": "Qwen 3.5 9B",
          "reasoning": false,
          "input": ["text", "image"],
          "cost": {"input":0,"output":0,"cacheRead":0,"cacheWrite":0},
          "contextWindow": 262144,
          "maxTokens": 32768
        }]
      }
    }
  },
  "agents": {
    "defaults": {
      "model": {
        "primary": "local//Users/you/models/Qwen3.5-9B-8bit",
        "fallbacks": ["openai/gpt-5.4", "anthropic/claude-sonnet-4-5"]
      },
      "models": {
        "local//Users/you/models/Qwen3.5-9B-8bit": {"alias": "Qwen Local", "streaming": false},
        "openai/gpt-5.4": {"alias": "GPT"},
        "anthropic/claude-sonnet-4-5": {"alias": "Sonnet"}
      },
      "timeoutSeconds": 600
    }
  }
}
```

## CLOUD PROVIDERS (optional)

OpenAI: `openclaw onboard --auth-choice openai-api-key`
or: `{"env": {"OPENAI_API_KEY": "sk-..."}}`

Gemini: `openclaw onboard --auth-choice gemini-api-key`
or: `{"env": {"GEMINI_API_KEY": "AIza..."}, "agents": {"defaults": {"model": {"primary": "google/gemini-2.5-flash"}}}}`

Gemini web search grounding:
```json
{"tools": {"web": {"search": {"provider": "gemini", "gemini": {"apiKey": "AIza...", "model": "gemini-2.5-flash"}}}}}
```

MiniMax pay-as-you-go (direct API key, anthropic-messages protocol):
```json
{
  "models": {"mode": "merge", "providers": {"minimax": {
    "baseUrl": "https://api.minimax.io/anthropic",
    "apiKey": "your-minimax-api-key",
    "api": "anthropic-messages",
    "models": [{"id": "MiniMax-M2.5","name": "MiniMax M2.5","reasoning": false,"input": ["text"],
      "cost": {"input":15,"output":60,"cacheRead":2,"cacheWrite":10},"contextWindow": 200000,"maxTokens": 8192}]
  }}},
  "agents": {"defaults": {"model": {"primary": "minimax/MiniMax-M2.5"}, "models": {"minimax/MiniMax-M2.5": {"alias": "MiniMax"}}}}
}
```

MiniMax Coding Plan (OAuth — for subscription users):

Coding Plan uses OAuth, not a direct API key. Run this interactively in your terminal:
```bash
openclaw plugins enable minimax-portal-auth
openclaw gateway restart
openclaw onboard --auth-choice minimax-portal
```
Select **Global (api.minimax.io)** when prompted, then complete browser login. OpenClaw writes the OAuth token to config automatically — no manual JSON editing needed.

MiniMax via LM Studio (openai-responses protocol):
```json
{"models": {"mode": "merge", "providers": {"lmstudio": {
  "baseUrl": "http://127.0.0.1:1234/v1", "apiKey": "lmstudio", "api": "openai-responses",
  "models": [{"id": "minimax-m2.5-gs32","name": "MiniMax M2.5 GS32","reasoning": false,"input": ["text"],
    "cost": {"input":0,"output":0,"cacheRead":0,"cacheWrite":0},"contextWindow": 196608,"maxTokens": 8192}]
}}}}
```

## STEP 6 — DISCORD (optional)

ERROR: "You are not authorized to use this command" → add explicit user ID even with groupPolicy:open

```json
{
  "channels": {
    "discord": {
      "groupPolicy": "open",
      "guilds": {"YOUR_SERVER_ID": {"requireMention": false, "users": ["YOUR_USER_ID"]}}
    }
  }
}
```

get_user_id: Discord Settings > Advanced > Developer Mode → right-click username
get_server_id: right-click server name

## STEP 7 — TELEGRAM (optional)

PREREQ: Create bot via @BotFather → /newbot → save token (format: `123456789:ABCdef...`)

config (write to `~/.openclaw/openclaw.json`, merge with existing content):
```json
{
  "channels": {
    "telegram": {
      "enabled": true,
      "botToken": "123456789:ABCdef...",
      "dmPolicy": "pairing",
      "groups": {"*": {"requireMention": true}}
    }
  }
}
```

apply: `openclaw gateway restart`

automated_script (recommended — validates token, merges config, restarts gateway):
```bash
TELEGRAM_BOT_TOKEN="123456789:ABCdef..." bash /path/to/repo/setup-telegram.sh
```

env_var_alternative: `TELEGRAM_BOT_TOKEN="..." openclaw gateway restart`

non_interactive_note: `--telegram-bot-token` flag may not exist in all openclaw versions; prefer script or manual config above.

pairing_management:
```bash
openclaw pairing list telegram
openclaw pairing approve telegram <code>
```

skip_pairing: `{"channels": {"telegram": {"dmPolicy": "open"}}}`

CONSTRAINTS:
- user must click Start in bot before it can respond
- groupAllowFrom: use numeric user IDs only, not @usernames (non-numeric entries silently ignored)
- wrong config path: channels.telegram NOT plugins.entries.telegram (causes "plugin not found")
- docker only: set env OPENCLAW_TELEGRAM_DISABLE_AUTO_SELECT_FAMILY=true for image 2026.2.17+; not needed on bare macOS
- groupPolicy "allowlist" with empty groupAllowFrom silently drops all group messages — if group messages aren't arriving, check: `"groupPolicy": "open"` or add your Telegram user ID to `groupAllowFrom`

## STEP 8 — SKILLS (optional)

SECURITY WARNING: review skill source before installing. ClawHavoc incident Feb 2026 found 341 malicious skills in the ClawHub registry. Validate source repo before running `openclaw skills install`.

install: `openclaw skills install <skill-name>`
browse: https://clawhub.com

essential_skills:
| skill | installs | capability | install_cmd |
|-------|----------|------------|-------------|
| github | 10K | manage issues/PRs/workflow runs/code review via gh CLI | `openclaw skills install github` |
| summarize | 10K | condense long content to structured summaries | `openclaw skills install summarize` |
| agent-browser | 11K | web browsing + research | `openclaw skills install agent-browser` |
| tavily | — | AI-optimized web search, better signal-to-noise than raw search | `openclaw skills install tavily` |
| gog | 14K | Google Workspace: Gmail/Calendar/Drive/Sheets/Docs (48 tools) | `openclaw skills install gog` |
| self-improving-agent | 15K | agent critiques and refines its own outputs iteratively | `openclaw skills install self-improving-agent` |
| capability-evolver | 35K | most installed; evolves agent capabilities dynamically | `openclaw skills install capability-evolver` |

security_skill: secureclaw (Adversa AI, open-source)
- 55 config audit checks
- 15 behavioral rules (~1150 tokens, stays resident)
- hardening modules auto-apply fixes

```bash
openclaw skills install secureclaw
openclaw run "Run a SecureClaw security audit on my current setup and summarize findings"
```

## DEBUGGING

| symptom | cause | fix |
|---------|-------|-----|
| HTTP 422 | old mlx_vlm from PyPI | clone + reinstall: `git -c http.version=HTTP/1.1 clone --depth 1 https://github.com/Blaizzy/mlx-vlm.git /tmp/mlx-vlm && pip install /tmp/mlx-vlm` |
| mlx_vlm server exits: "unrecognized arguments: --model" | mlx_vlm 0.4.0 removed startup `--model` flag | remove `--model` and `--trust-remote-code` from the pm2 start command; model loads per-request |
| mlx_lm server exits immediately | unsupported flag passed | remove `--trust-remote-code` from mlx_lm commands |
| "unauthorized: gateway token missing" in dashboard | token not in URL | run `openclaw dashboard` — opens browser with token pre-filled in URL (`#token=...`); do NOT navigate to bare `http://127.0.0.1:18789/` directly |
| connection refused on proxy port | proxy not running or port conflict | `pm2 list` → check status; `lsof -i :10012` → kill conflict |
| connection refused on model port | model server crashed on bind | `lsof -i :10002` → kill conflict; `pm2 logs <name>` for error |
| garbage responses | quantization too aggressive | use 8bit or 5bit, not 3bit |
| OOM | model too large | smaller model or lower quant |
| timeout in OpenClaw | timeoutSeconds too low | set 600 in config |
| pm2 processes not surviving reboot | pm2 startup not completed | run printed sudo command from `pm2 startup`, then `pm2 save` |

logs:
```bash
pm2 logs qwen3.5-9b
pm2 logs mlx-proxy-qwen
```

inspect_raw_requests (socat):
```bash
pm2 stop mlx-proxy-qwen
socat -v TCP-LISTEN:10012,reuseaddr,fork \
  SYSTEM:'cat; echo -e "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\n\r\n{\"choices\":[{\"message\":{\"role\":\"assistant\",\"content\":\"ok\"}}]}"'
```

curl_debug:
```bash
# basic
curl -X POST http://127.0.0.1:10002/v1/chat/completions -H "Content-Type: application/json" \
  -d '{"model":"/Users/you/models/Qwen3.5-9B-8bit","messages":[{"role":"user","content":"hi"}],"stream":false}'
# with tools
curl -X POST http://127.0.0.1:10002/v1/chat/completions -H "Content-Type: application/json" \
  -d '{"model":"/Users/you/models/Qwen3.5-9B-8bit","messages":[{"role":"user","content":"hi"}],"stream":false,"tools":[]}'
# array content (multimodal format)
curl -X POST http://127.0.0.1:10002/v1/chat/completions -H "Content-Type: application/json" \
  -d '{"model":"/Users/you/models/Qwen3.5-9B-8bit","messages":[{"role":"user","content":[{"type":"text","text":"hi"}]}],"stream":false}'
```

## MONITORING

| tool | sudo | install | key_metrics |
|------|------|---------|-------------|
| macmon | no | `brew install macmon` | CPU/GPU/ANE power+util, RAM, swap, temp |
| mactop | no | `brew install mactop` | CPU/GPU/E-P-cores, power, freq, temp; JSON/CSV output |
| asitop | yes | `pip install asitop` → `sudo asitop` | CPU/GPU/ANE util+freq, RAM, swap, power charts |
| fluidtop | yes | `pip install fluidtop` → `sudo fluidtop` | asitop fork; better newer chip support, AI workload focus |

RECOMMENDED: `brew install macmon && macmon`

memory_pressure_signals:
- swap_used > 0 → model too large for RAM; switch to lower quant or smaller model
- GPU util = 0% during inference → model on CPU only (check mlx install)
- ANE util spikes → mlx offloading to Neural Engine (normal)
- RAM near capacity + high swap → expect 2-5x slowdown; reduce model size

```bash
macmon          # terminal 1: live metrics
pm2 monit       # terminal 2: process memory
memory_pressure # quick system pressure check
```

## CHECKLIST

```
prereq: brew, node>=22, python3, pm2, huggingface-cli
0.  [[ "$(uname -m)" == "arm64" ]] || { echo "ERROR: Apple Silicon required"; exit 1; }
1.  huggingface-cli download mlx-community/<MODEL> --local-dir ~/models/<MODEL>
2.  python3 -m venv ~/models/mlx-venv && source ~/models/mlx-venv/bin/activate
3a. git -c http.version=HTTP/1.1 clone --depth 1 https://github.com/Blaizzy/mlx-vlm.git /tmp/mlx-vlm
3b. pip install /tmp/mlx-vlm mlx-lm torch torchvision
4.  curl -fsSL https://openclaw.ai/install.sh | bash && openclaw onboard --install-daemon
5.  mkdir -p ~/.openclaw && [ -f ~/.openclaw/openclaw.json ] || echo '{}' > ~/.openclaw/openclaw.json
6.  lsof -i :10002 && lsof -i :10012  # must be empty
7.  pm2 start [model server — pick ONE block from Step 3] && pm2 save
8.  PROXY_SCRIPT=/path/to/mlx-proxy.py pm2 start [proxy — matching Step 4 block] && pm2 save
9.  pm2 startup  # run the printed sudo command, then: pm2 save
10. edit ~/.openclaw/openclaw.json (Step 5)
11. [optional] TELEGRAM_BOT_TOKEN=... bash /path/to/setup-telegram.sh
12. [optional] openclaw skills install secureclaw github summarize
13. brew install macmon && macmon  # monitor memory pressure
```

## VERIFY

Run after completing the checklist to confirm everything is working end-to-end.

```bash
# 1. pm2 processes — all should show "online"
pm2 status

# 2. model server — should return JSON with model list
curl -sf http://127.0.0.1:10004/v1/models   # mlx_lm (GLM/kimi)
curl -sf http://127.0.0.1:10002/v1/models   # mlx_vlm (Qwen3.5)

# 3. proxy — should mirror model server response
curl -sf http://127.0.0.1:10014/v1/models   # GLM proxy
curl -sf http://127.0.0.1:10012/v1/models   # Qwen proxy

# 4. openclaw gateway
openclaw gateway status   # expect: Runtime: running, Listening: 127.0.0.1:18789

# 5. end-to-end inference through proxy
# GLM (mlx_lm — no model field needed, --strip-model removes it):
curl -s -X POST http://127.0.0.1:10014/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"messages":[{"role":"user","content":"Say hello."}],"stream":false,"max_tokens":4000}' \
  | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['choices'][0]['message']['content'])"
# expect: non-empty response (GLM is a reasoning model — needs max_tokens>=4000 to finish thinking)

# Qwen (mlx_vlm — must pass full model path in request body):
curl -s -X POST http://127.0.0.1:10012/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model":"/Users/you/models/Qwen3.5-9B-8bit","messages":[{"role":"user","content":"Say hello."}],"stream":false,"max_tokens":100}' \
  | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['choices'][0]['message']['content'])"
# expect: non-empty response; first call takes ~30s to load model into GPU

# 6. open dashboard (auto-fills token in URL)
openclaw dashboard
```

expected_state:
- pm2: glm-4.7-flash=online, mlx-proxy-glm=online (add qwen3.5/mlx-proxy-qwen if Qwen downloaded)
- gateway: running on 127.0.0.1:18789
- inference: non-empty content field in response
- dashboard: opens browser, no token prompt (token is in the URL hash)

## UNINSTALL

Removes OpenClaw, model servers, proxy, and all associated data. Each block is independent — skip any you want to keep.

```bash
# 1. stop and remove pm2 model servers + proxy
pm2 delete glm-4.7-flash mlx-proxy-glm 2>/dev/null || true
pm2 delete qwen3.5-35b mlx-proxy-qwen 2>/dev/null || true   # if Qwen was set up
pm2 save

# 2. remove pm2 LaunchAgent (auto-start on reboot)
pm2 unstartup launchd 2>/dev/null || true
# if that prints a sudo command, run it

# 3. stop and remove OpenClaw LaunchAgent
launchctl bootout gui/$(id -u) ~/Library/LaunchAgents/ai.openclaw.gateway.plist 2>/dev/null || true
rm -f ~/Library/LaunchAgents/ai.openclaw.gateway.plist

# 4. uninstall OpenClaw npm package
npm uninstall -g openclaw

# 5. remove OpenClaw config and data
rm -rf ~/.openclaw

# 6. remove model weights (LARGE — frees disk space)
rm -rf ~/models/GLM-4.7-flash-8bit
rm -rf ~/models/Qwen3.5-35B-A3B-8bit   # if downloaded
rm -rf ~/models/mlx-venv                # shared venv

# 7. remove HuggingFace model cache
rm -rf ~/.cache/huggingface/hub/models--mlx-community--GLM-4.7-flash-8bit
rm -rf ~/.cache/huggingface/hub/models--mlx-community--Qwen3.5-35B-A3B-8bit

# 8. [optional] uninstall pm2 globally (only if not used for other projects)
# npm uninstall -g pm2
# rm -rf ~/.pm2
```

verify_clean:
```bash
pm2 list                          # should show no mlx/openclaw processes
launchctl list | grep openclaw    # should return nothing
ls ~/Library/LaunchAgents/ | grep openclaw  # should return nothing
which openclaw                    # should return "not found"
```
