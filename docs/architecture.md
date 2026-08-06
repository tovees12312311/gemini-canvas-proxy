# Architecture

How the Gemini Canvas Proxy turns a free Canvas session into a local OpenAI-compatible API.

## Data flow

```
Your App (Hermes, OpenClaw, curl, Python SDK, etc.)
    │
    ├── HTTP POST localhost:8765/v1/chat/completions
    │
    ▼
Native Host (Python, port 8765)           ← OpenAI ↔ Gemini format translation
    │
    ├── stdio (4-byte length + JSON)      ← Chrome native messaging protocol
    │
    ▼
Chrome Extension (service worker)         ← Routes to the Gemini tab
    │
    ├── chrome.tabs.sendMessage
    │
    ▼
Content Script (top-level Gemini page)    ← Relay between extension and iframe
    │
    ├── MessageChannel                    ← Private port transferred once via
    │                                      postMessage across the sandbox boundary
    ▼
Canvas Proxy Page (in sandboxed iframe)   ← fetch() to Gemini API (FREE)
    │
    ├── fetch('https://generativelanguage.googleapis.com/...')
    │   Auth: Canvas auto-injected credentials (unlimited, model-scoped)
    │
    ▼
Response flows back the same path → HTTP response to your app
```

## The key insight: MessageChannel, not WebSocket

**CanvasToAPI** and similar projects bridge the Canvas page to a local server with a WebSocket (`ws://localhost:port`). Chrome 142+ [Local Network Access](https://developers.google.com/privacy-sandbox/blog/local-network-access) blocks these connections from sandboxed iframes — users had to disable `chrome://flags/#local-network-access-check`, and that flag is disappearing in Chrome 145+.

This project uses a **`MessageChannel`** instead: browser-level IPC that crosses the Canvas sandbox boundary without a local network request. The Canvas page transfers one end of a private port during a one-time `postMessage` handshake; all API requests and responses then travel only over that port. Chrome cannot block it because it is not a network request — making the proxy future-proof.

Since the port is private (never broadcast), the extension also validates the exact `https://gemini.google.com` origin on every message, so unrelated page content cannot inject requests or responses.

## How Canvas auth works

When your code contains the literal string `const apiKey = "";`, Google **auto-injects** the real API key at compile time. That key:

- Has **unlimited quota** — no rate limit, no daily cap
- Is **model-scoped** — only works with the currently promoted model (see the README model table)
- Is **session-bound** — dies when the Canvas tab closes

The Canvas page appends it via `URL.searchParams.set('key', apiKey)` and validates every request path against a strict regex (`/v1beta/models/<model>:generateContent|streamGenerateContent`), so relayed paths cannot be redirected to other hosts.

## MV3 state persistence

Chrome Manifest V3 service workers can be suspended at any time, and module globals are lost. The extension therefore keeps all state in `chrome.storage.session`:

- **Canvas tab selection** — which tab completed the `page_ready` handshake, persisted and preferred over passively-discovered Gemini tabs
- **Chunk buffers** — partially-received native-message chunks, with a 90-second TTL swept by a `chrome.alarms` alarm so stale transfers can't leak sensitive request bodies

## Native messaging protocol

Chrome native messaging frames each message as `[4-byte length (native endian)] [UTF-8 JSON]`:

- Host → extension: **1 MB max** (hard-coded `kMaximumNativeMessageSize`)
- Extension → host: **64 MB max**

Payloads over ~900 KB are chunked: the host splits the serialized bytes into 600 KB pieces, base64-encodes each into an `api_request_chunk` native message (staying comfortably under 1 MB after encoding + envelope), and the service worker reassembles them into the exact original UTF-8 byte stream before parsing. This works in every environment — no HTTP fetch, no localhost network access, no Local Network Access issues.

## Docker role split

The container runs two explicit roles so only one process ever binds port 8765:

- **`--http-only`** — owned by the entrypoint; serves the OpenAI HTTP API and listens on a mode-`0600` Unix-domain socket (`/tmp/gemini-canvas-proxy.sock`)
- **`--bridge-only`** — launched by Chromium through the native-messaging manifest (`gemini_proxy_bridge.sh`); bridges Chrome's stdio to the Unix socket

HTTP requests fail fast with 502 when no bridge is connected, instead of hanging for the 60-second timeout. See [deployment.md](deployment.md) for the container setup.

## Credits

- **coxcelot** — [I am canceled autobrowsing agent harness](https://github.com/coxcelot/iamcanceledpresentsagenericautobrowsingagentharness). The postMessage bridge concept was inspired by this autonomous browser agent that runs inside Gemini Canvas. This project strips it down to the API proxy layer and adds native messaging host integration for system-level access.
- **CanvasToAPI** — [iBUHub/CanvasToAPI](https://github.com/iBUHub/CanvasToAPI). The OpenAI ↔ Gemini format translation was informed by its source.
