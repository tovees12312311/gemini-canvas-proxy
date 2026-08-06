# ⚡ Gemini Canvas Proxy

> Free unlimited Gemini API for any OpenAI-compatible tool — bridged from Gemini Canvas via a Chrome extension. No WebSocket, no Local Network Access issues.

[![Tests](https://img.shields.io/github/actions/workflow/status/pranrichh/gemini-canvas-proxy/tests.yml?branch=main&label=tests)](https://github.com/pranrichh/gemini-canvas-proxy/actions)
[![License](https://img.shields.io/github/license/pranrichh/gemini-canvas-proxy)](LICENSE)
[![Models](https://img.shields.io/badge/models-4%20working-blue)](#available-models)

An OpenAI-compatible endpoint at `localhost:8765` backed by free unlimited Gemini inference from [Gemini Canvas](https://gemini.google.com). Works with anything that speaks OpenAI — [Hermes Agent](https://github.com/NousResearch/hermes-agent), OpenClaw, LiteLLM, LangChain, the OpenAI SDK, curl.

```
Your App (Hermes, curl, SDK, ...)
    │  HTTP POST localhost:8765/v1/chat/completions
    ▼
Native Host (Python :8765)          ← OpenAI ↔ Gemini translation
    │  stdio (4-byte length + JSON)
    ▼
Chrome Extension (service worker)   ← routes to the Gemini tab
    │  chrome.tabs.sendMessage
    ▼
Content Script (Gemini page)        ← MessageChannel relay (private port,
    │                                  transferred once via postMessage)
    ▼
Canvas Proxy Page (sandboxed iframe) ← fetch() to Gemini API — FREE
```

**Why not WebSocket?** Chrome 142+ [Local Network Access](https://developers.google.com/privacy-sandbox/blog/local-network-access) blocks `ws://localhost` from sandboxed iframes (and the flag is being removed in Chrome 145+). This project uses a private `MessageChannel` instead — browser-level IPC that crosses the Canvas sandbox boundary without a network call, so it can't be blocked. Full architecture in [docs/architecture.md](docs/architecture.md).

---

## Quick Start (bare metal)

**Prerequisites:** Chromium browser, Python 3.8+, a Google account with Gemini access.

```bash
git clone https://github.com/pranrichh/gemini-canvas-proxy.git
cd gemini-canvas-proxy
./setup.sh          # Windows: .\setup.ps1
```

1. Open `chrome://extensions/` → enable **Developer mode** → **Load unpacked** → select `extension/`
2. Copy the **Extension ID** (32 lowercase chars) and paste it when the setup script asks
3. Open [gemini.google.com](https://gemini.google.com) → **+** → **Canvas** → prompt **"Create an HTML web app"** → switch to **Code** tab → replace the generated code with the contents of `canvas-proxy.html` → **Preview** (green "Proxy Active" status)
4. Test it:

```bash
PROXY_TOKEN="$(cat native_host/.proxy_token)"
curl http://127.0.0.1:8765/v1/chat/completions \
  -H "Authorization: Bearer $PROXY_TOKEN" \
  -H 'Content-Type: application/json' \
  -d '{"model":"gemini-3-flash-preview","messages":[{"role":"user","content":"Say hello in 5 words"}]}'
```

The setup scripts generate a per-install bearer token and print it — use it as the API key in any client. Keep the Gemini tab open; the proxy lives and dies with it.

**Running 24/7 or on a server?** Use the self-contained Docker Compose stack (Chromium + noVNC + proxy in one container, login survives restarts) — see [docs/deployment.md](docs/deployment.md).

---

## Features

- ✅ **Chat completions** — OpenAI-compatible, with system prompts and multi-turn history
- ✅ **Tool/function calling** — native Gemini `functionCall`/`functionResponse` parts, with `thoughtSignature` round-tripping for Gemini 3
- ✅ **Multimodal input** — data-URI images by default; remote `http(s)://` images opt-in (SSRF-guarded)
- ✅ **Image generation** — Nano Banana / Nano Banana 2 return images as markdown data URLs
- ✅ **Streaming** — simulated SSE, correctly emitting `tool_calls` deltas and `finish_reason`
- ✅ **Generation controls** — `temperature`, `top_p`, `top_k`, `stop`, `seed`, penalties, `response_format: json_object`
- ✅ **Bearer auth** — every `/v1/*` request requires a token; binds to `127.0.0.1` by default
- ✅ **Large payloads** — >900 KB requests chunked below Chrome's 1 MB native-messaging cap (byte-accurate base64 reassembly)

## Available Models

The Canvas key is model-scoped — it works only with models Canvas currently promotes. Tested:

| Model ID | Name | Type | Status |
|---|---|---|---|
| `gemini-3-flash-preview` | Gemini 3 Flash | Text + Tools | ✅ |
| `gemini-2.5-flash-preview-05-20` | Gemini 2.5 Flash | Text + Tools | ✅ |
| `gemini-3.1-flash-image-preview` | Nano Banana 2 | Image Generation | ✅ |
| `gemini-2.5-flash-image` | Nano Banana | Image Generation | ✅ |

Google rotates promoted models — a 403 usually means the key isn't scoped for that model. Try one from the working list.

---

## Docs

- [Architecture](docs/architecture.md) — how the bridge works, Canvas auth mechanism, credits
- [API Reference](docs/api.md) — endpoints, supported parameters, multimodal, tool calling, chunking
- [Deployment](docs/deployment.md) — Docker Compose (loopback / VPS / Tailscale / shared folder), Podman, daily usage
- [Security](docs/security.md) — auth, CORS, SSRF protections, configuration reference
- [Troubleshooting](docs/troubleshooting.md) — common errors and fixes, limitations
- [Integrations](docs/integrations.md) — Hermes Agent, OpenAI SDK (Python/JS), LangChain

## Project Structure

```
gemini-canvas-proxy/
├── canvas-proxy.html          # Paste into Gemini Canvas code view (React UI)
├── extension/
│   ├── manifest.json          # Chrome MV3 extension manifest
│   ├── background.js          # Service worker: native host ↔ content script
│   └── content_script.js      # MessageChannel relay: iframe ↔ extension
├── native_host/
│   └── gemini_proxy.py        # HTTP server (:8765) + OpenAI↔Gemini translation
├── setup.sh / setup.ps1       # Setup scripts (Linux/macOS, Windows)
├── stop.sh                    # Stop the proxy
├── Dockerfile                 # Self-contained image (Chromium + noVNC + proxy)
├── docker-compose.yml         # Full stack in a container (loopback only)
├── docker-compose.shared.yml  # Override: share browser-data with host
├── docker-compose.vps.yml     # Override: bind 0.0.0.0 for Tailscale/VPS
├── preflight.sh               # Container root preflight (chown + user drop)
├── entrypoint.sh              # Container entrypoint (boots full stack)
├── setup-extension.sh         # In-container extension manifest setup
├── toggle-vnc.sh              # Stop/start x11vnc+websockify (save RAM)
├── chromium-policies/         # BrowserSignin=0 policy (login persistence)
├── tests/                     # stdlib unittest suite (no deps)
└── docs/                      # This documentation
```

## License

[MIT](LICENSE) — but see the [ToS note](docs/troubleshooting.md#limitations): using Canvas credentials outside Canvas may violate Google's Terms of Service.

## Credits

- **coxcelot** — [I am canceled autobrowsing agent harness](https://github.com/coxcelot/iamcanceledpresentsagenericautobrowsingagentharness) — the postMessage bridge concept
- **CanvasToAPI** — [iBUHub/CanvasToAPI](https://github.com/iBUHub/CanvasToAPI) — OpenAI ↔ Gemini format translation reference
