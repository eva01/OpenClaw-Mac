# BytePlus Coding Plan — OpenClaw Setup

Base URL: `https://ark.ap-southeast.bytepluses.com/api/coding/v3`

## Models

| id | name | context | max tokens | speed |
|----|------|---------|------------|-------|
| `bytedance-seed-code` | ByteDance Seed Code | 256k | 32k | 89 tok/s |
| `dola-seed-2.0-pro` | Dola Seed 2.0 Pro | 256k | 128k | 70 tok/s |
| `dola-seed-2.0-lite` | Dola Seed 2.0 Lite | 256k | 128k | 76 tok/s |
| `kimi-k2.5` | Kimi K2.5 | 256k | 32k | 34 tok/s |
| `glm-4.7` | GLM 4.7 | 200k | 128k | 39 tok/s |

Default model: `kimi-k2.5`

## Installation

### 1. Get your API key

Go to the BytePlus Coding Plan dashboard and copy your API key.

### 2. Write config

```bash
read -s -p "BytePlus API key: " BYTEPLUS_KEY && echo

mkdir -p ~/.openclaw
cat > /tmp/byteplus-patch.json << EOF
{
  "models": {
    "mode": "merge",
    "providers": {
      "byteplus-plan": {
        "baseUrl": "https://ark.ap-southeast.bytepluses.com/api/coding/v3",
        "apiKey": "$BYTEPLUS_KEY",
        "api": "openai-completions",
        "models": [
          {
            "id": "bytedance-seed-code",
            "name": "ByteDance Seed Code",
            "reasoning": false,
            "input": ["text"],
            "cost": {"input": 0, "output": 0, "cacheRead": 0, "cacheWrite": 0},
            "contextWindow": 256000,
            "maxTokens": 32000
          },
          {
            "id": "glm-4.7",
            "name": "GLM 4.7",
            "reasoning": false,
            "input": ["text"],
            "cost": {"input": 0, "output": 0, "cacheRead": 0, "cacheWrite": 0},
            "contextWindow": 200000,
            "maxTokens": 128000
          },
          {
            "id": "kimi-k2.5",
            "name": "Kimi K2.5",
            "reasoning": false,
            "input": ["text"],
            "cost": {"input": 0, "output": 0, "cacheRead": 0, "cacheWrite": 0},
            "contextWindow": 256000,
            "maxTokens": 32000
          },
          {
            "id": "dola-seed-2.0-pro",
            "name": "Dola Seed 2.0 Pro",
            "reasoning": false,
            "input": ["text"],
            "cost": {"input": 0, "output": 0, "cacheRead": 0, "cacheWrite": 0},
            "contextWindow": 256000,
            "maxTokens": 128000
          },
          {
            "id": "dola-seed-2.0-lite",
            "name": "Dola Seed 2.0 Lite",
            "reasoning": false,
            "input": ["text"],
            "cost": {"input": 0, "output": 0, "cacheRead": 0, "cacheWrite": 0},
            "contextWindow": 256000,
            "maxTokens": 128000
          }
        ]
      }
    }
  },
  "agents": {
    "defaults": {
      "models": {
        "byteplus-plan/bytedance-seed-code": {"alias": "seed-code", "streaming": false},
        "byteplus-plan/glm-4.7":             {"alias": "glm-4.7",   "streaming": false},
        "byteplus-plan/kimi-k2.5":           {"alias": "kimi-k2.5", "streaming": false},
        "byteplus-plan/dola-seed-2.0-pro":   {"alias": "dola-pro",  "streaming": false},
        "byteplus-plan/dola-seed-2.0-lite":  {"alias": "dola-lite", "streaming": false}
      },
      "model": {
        "primary": "byteplus-plan/kimi-k2.5"
      },
      "timeoutSeconds": 600
    }
  }
}
EOF

# Merge into existing config (requires jq)
if [ -f ~/.openclaw/openclaw.json ]; then
  jq -s '.[0] * .[1]' ~/.openclaw/openclaw.json /tmp/byteplus-patch.json > /tmp/openclaw-merged.json \
    && mv /tmp/openclaw-merged.json ~/.openclaw/openclaw.json
else
  cp /tmp/byteplus-patch.json ~/.openclaw/openclaw.json
fi

echo "Done. Restart the gateway: openclaw gateway restart"
```

> Note: `timeoutSeconds` belongs at `agents.defaults` level, not inside `agents.defaults.models.<id>` — putting it there causes a config validation error.

### 3. Restart gateway

```bash
openclaw gateway restart
```

### 4. Verify gateway

```bash
openclaw gateway status
# expect: Runtime: running, Listening: 127.0.0.1:18789
```

## Onboarding

### Memory search (Gemini embeddings)

OpenClaw uses an embedding provider for semantic memory recall. Add your Gemini API key to `~/.openclaw/openclaw.json`:

```json
{
  "env": {
    "GEMINI_API_KEY": "your-gemini-api-key"
  }
}
```

Then restart the gateway:

```bash
openclaw gateway restart
```

Verify:

```bash
openclaw memory status --deep
# expect: Provider: gemini, Model: gemini-embedding-001, Embeddings: ready
```

### Google Workspace (gog skill)

Gives OpenClaw access to Google Calendar, Drive, Docs, Sheets, and more.

**1. Install the CLI**

```bash
brew install gogcli
```

**2. Create OAuth credentials**

- Go to Google Cloud Console → APIs & Services → Credentials
- Create an OAuth 2.0 Client ID (Desktop app type)
- Enable these APIs: Google Calendar, Drive, Docs, Sheets, Gmail (if available)
- Download the credentials JSON

**3. Store credentials and add test user**

- Go to OAuth consent screen → Test users → add your Google account email
- Store the credentials:

```bash
gog auth credentials set /path/to/client_secret_*.json
```

**4. Authenticate**

```bash
gog auth add your-google-email@gmail.com
# browser opens → sign in → click Continue past the unverified app warning
```

**5. Verify**

```bash
gog auth list          # should show your account with all scopes
gog calendar list      # should return events or "No events"
gog drive ls           # should list Drive files
```


### Health check

Run after full setup to catch any remaining issues:

```bash
openclaw doctor
```

Expected state — no errors, memory search ready, gog skill shows ✓ ready:

```bash
openclaw skills info gog
# expect: gog ✓ Ready
```

## Test OpenClaw (end-to-end)

OpenClaw uses WebSocket internally — direct HTTP to the gateway port does not work. Use the CLI:

```bash
# Quick smoke test
openclaw infer model run --model "byteplus-plan/kimi-k2.5" --prompt "Say hi."

# Test each model
for model in bytedance-seed-code glm-4.7 kimi-k2.5 dola-seed-2.0-pro dola-seed-2.0-lite; do
  echo -n "$model: "
  openclaw infer model run --model "byteplus-plan/$model" --prompt "Say hi."
done
```

## Benchmark all models (direct API)

Tests the raw API directly — useful for measuring speed independent of OpenClaw overhead.

```bash
BYTEPLUS_BASE="https://ark.ap-southeast.bytepluses.com/api/coding/v3"
BYTEPLUS_KEY="your-api-key"

for model in bytedance-seed-code glm-4.7 kimi-k2.5 dola-seed-2.0-pro dola-seed-2.0-lite; do
  python3 -c "
import urllib.request, json, time
model = '$model'
payload = json.dumps({
  'model': model,
  'messages': [{'role': 'user', 'content': 'Write a fizzbuzz function in Python.'}],
  'max_tokens': 200,
  'stream': False
}).encode()
req = urllib.request.Request(
  '$BYTEPLUS_BASE/chat/completions',
  data=payload,
  headers={'Content-Type': 'application/json', 'Authorization': 'Bearer $BYTEPLUS_KEY'}
)
t0 = time.time()
with urllib.request.urlopen(req, timeout=60) as r:
    d = json.load(r)
elapsed = time.time() - t0
tokens = d.get('usage', {}).get('completion_tokens', '?')
tps = round(tokens / elapsed, 1) if isinstance(tokens, int) else '?'
print(f'{model:25s} | {elapsed*1000:6.0f}ms | {tokens} tokens | {tps} tok/s')
" &
done
wait
```

Expected output:
```
bytedance-seed-code       |  14262ms | 1272 tokens | 89.2 tok/s
dola-seed-2.0-pro         |  12931ms |  906 tokens | 70.1 tok/s
dola-seed-2.0-lite        |  17234ms | 1301 tokens | 75.5 tok/s
kimi-k2.5                 |  19887ms |  671 tokens | 33.7 tok/s
glm-4.7                   |  31877ms | 1250 tokens | 39.2 tok/s
```

## API examples (direct)

### curl

```bash
curl -s -X POST https://ark.ap-southeast.bytepluses.com/api/coding/v3/chat/completions \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $BYTEPLUS_KEY" \
  -d '{
    "model": "kimi-k2.5",
    "messages": [{"role": "user", "content": "Hello!"}],
    "max_tokens": 100,
    "stream": false
  }' | python3 -c "import sys,json; print(json.load(sys.stdin)['choices'][0]['message']['content'])"
```

### Python (no deps)

```python
import urllib.request
import json

BYTEPLUS_BASE = "https://ark.ap-southeast.bytepluses.com/api/coding/v3"
BYTEPLUS_KEY  = "your-api-key"

def chat(model: str, prompt: str, max_tokens: int = 1000) -> str:
    payload = json.dumps({
        "model": model,
        "messages": [{"role": "user", "content": prompt}],
        "max_tokens": max_tokens,
        "stream": False,
    }).encode()
    req = urllib.request.Request(
        f"{BYTEPLUS_BASE}/chat/completions",
        data=payload,
        headers={
            "Content-Type": "application/json",
            "Authorization": f"Bearer {BYTEPLUS_KEY}",
        },
    )
    with urllib.request.urlopen(req, timeout=600) as r:
        d = json.load(r)
    return d["choices"][0]["message"]["content"]

print(chat("bytedance-seed-code", "Write a fizzbuzz in Python."))
```

### Python (openai SDK)

```python
from openai import OpenAI

client = OpenAI(
    base_url="https://ark.ap-southeast.bytepluses.com/api/coding/v3",
    api_key="your-api-key",
)

response = client.chat.completions.create(
    model="kimi-k2.5",
    messages=[{"role": "user", "content": "Write a fizzbuzz in Python."}],
    max_tokens=1000,
    stream=False,
)
print(response.choices[0].message.content)
```

### Streaming (openai SDK)

```python
from openai import OpenAI

client = OpenAI(
    base_url="https://ark.ap-southeast.bytepluses.com/api/coding/v3",
    api_key="your-api-key",
)

with client.chat.completions.stream(
    model="bytedance-seed-code",
    messages=[{"role": "user", "content": "Explain async/await in Python."}],
    max_tokens=1000,
) as stream:
    for chunk in stream:
        if chunk.choices[0].delta.content:
            print(chunk.choices[0].delta.content, end="", flush=True)
print()
```
