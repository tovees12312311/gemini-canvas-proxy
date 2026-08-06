# Integrations

Point any OpenAI-compatible client at `http://127.0.0.1:8765/v1` with the generated bearer token as the API key.

**Get the token:**

```bash
# bare metal
PROXY_TOKEN="$(cat native_host/.proxy_token)"

# docker
PROXY_TOKEN="$(docker compose exec -T proxy cat /browser-data/proxy-token)"
```

## curl

```bash
curl http://127.0.0.1:8765/v1/chat/completions \
  -H "Authorization: Bearer $PROXY_TOKEN" \
  -H 'Content-Type: application/json' \
  -d '{"model":"gemini-3-flash-preview","messages":[{"role":"user","content":"Hello!"}]}'
```

## Hermes Agent

[Hermes Agent](https://github.com/NousResearch/hermes-agent) is an open-source AI agent framework with full tool calling support.

### Option 1: Interactive setup

1. Run `hermes model`
2. Select **`Custom (Direct API)`**
3. Enter:
   - **Base URL**: `http://127.0.0.1:8765/v1`
   - **API Key**: the bearer token printed by the setup script
4. Pick a model (e.g. `gemini-3-flash-preview`)

### Option 2: Manual config

Add to `~/.hermes/config.yaml`:

```yaml
custom_providers:
  - name: "Local (127.0.0.1:8765)"
    base_url: http://127.0.0.1:8765/v1
    api_key: "<token printed by setup>"
    model: gemini-3-flash-preview
    api_mode: chat_completions
```

Then:

```bash
hermes chat -q "Say hello" --provider "Local (127.0.0.1:8765)" --model gemini-3-flash-preview
```

Full tool calling (terminal, browser, file operations, MCP tools) works through the proxy — Gemini generates native function calls, Hermes executes them locally, and results return as native `functionResponse` parts.

## OpenAI Python SDK

```python
import os
from openai import OpenAI

client = OpenAI(
    base_url="http://127.0.0.1:8765/v1",
    api_key=os.environ["GEMINI_PROXY_TOKEN"],
)

response = client.chat.completions.create(
    model="gemini-3-flash-preview",
    messages=[{"role": "user", "content": "Hello!"}],
)
print(response.choices[0].message.content)
```

## OpenAI JavaScript SDK

```javascript
import OpenAI from "openai";

const client = new OpenAI({
  baseURL: "http://127.0.0.1:8765/v1",
  apiKey: process.env.GEMINI_PROXY_TOKEN,
});

const response = await client.chat.completions.create({
  model: "gemini-3-flash-preview",
  messages: [{ role: "user", content: "Hello!" }],
});
```

## LangChain

```bash
export OPENAI_API_KEY="$GEMINI_PROXY_TOKEN"
export OPENAI_API_BASE=http://127.0.0.1:8765/v1
```

## OpenClaw / LiteLLM / anything else

Any tool that accepts an OpenAI base URL works: set `base_url`/`baseURL` to `http://127.0.0.1:8765/v1` and use the bearer token as the API key.
