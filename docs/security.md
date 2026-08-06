# Security

The proxy's security model, configuration reference, and the protections enforced by each layer.

## Threat model

The proxy exposes an LLM endpoint backed by your Google session's Canvas credentials. Two abuse paths matter: **local attackers** (other processes/users on the same machine or LAN) calling the API, and **malicious content** (web pages, prompt payloads, remote URLs) reaching the proxy or the extension.

## HTTP boundary

| Control | Default | Env var |
|---|---|---|
| Listen address | `127.0.0.1` (loopback only) | `PROXY_BIND` |
| Bearer auth on every `/v1/*` endpoint | required | `PROXY_TOKEN` / token file |
| Health endpoint | unauthenticated | — |
| CORS | disabled (no `Access-Control-Allow-Origin`) | `PROXY_ALLOWED_ORIGIN` |
| Max request body | 32 MB, rejected **before** reading | `PROXY_MAX_REQUEST_BYTES` |
| Token file location | `native_host/.proxy_token` (bare metal) / `/browser-data/proxy-token` (Docker) | `PROXY_TOKEN_FILE` |

- The listener binds `127.0.0.1` by default; `PROXY_BIND=0.0.0.0` is explicit opt-in with a startup warning. Even then, keep the port behind a firewall / private mesh.
- Bearer comparison is constant-time (`hmac.compare_digest`). Missing/incorrect tokens get `401` + `WWW-Authenticate: Bearer`; a token that was never configured gets `503`.
- CORS preflight returns `403` for any origin other than the single exact `PROXY_ALLOWED_ORIGIN` value. `Vary: Origin` is emitted when an origin is allowed.
- Request bodies above the ceiling are rejected with `413` before `json.loads` reads them — no unbounded allocation from an attacker-controlled `Content-Length`.

**Do not commit tokens.** `native_host/.proxy_token` and `gemini_proxy.bat` are gitignored; the Docker token lives in the `browser-data` volume.

## Extension boundary

- Content script is scoped to `https://gemini.google.com/*` only — no `<all_urls>` host permissions, no `activeTab`, no `scripting`.
- Every runtime message is validated: the sender must be a tab on the exact `https://gemini.google.com` origin, and responses are only accepted from the active Canvas tab.
- All API traffic rides a private `MessageChannel` port transferred once during the ready handshake — no wildcard `postMessage` broadcasts, no cross-iframe eavesdropping.
- Canvas-tab state and partial chunk buffers persist in `chrome.storage.session` with a 90-second TTL sweep, so interrupted transfers don't leave sensitive request bodies lying around.

## Remote image fetching (SSRF defense)

Remote `http(s)://` image URLs are **disabled by default** (`PROXY_ALLOW_URL_FETCH`). When enabled:

- URL scheme/authority validated (HTTP(S) only, no userinfo)
- Every resolved destination address checked against `ipaddress`: private, loopback, link-local, reserved, unspecified, and multicast ranges are rejected — including metadata endpoints (`169.254.169.254` etc.)
- The destination policy is **reapplied on every redirect** via a custom redirect handler
- Response bodies streamed with a 20 MB ceiling (`PROXY_MAX_IMAGE_BYTES`); declared `Content-Length` over the ceiling rejected before reading
- `image/*` content type required
- Failures are logged with a sanitized hostname and surfaced to the model as an explicit `[Remote image omitted: reason]` part

## Canvas API destination validation

- The Canvas page accepts only `/v1beta/models/<model>:generateContent|streamGenerateContent` paths — no host-changing paths, no traversal (`..`), no authority characters.
- The endpoint is built with `new URL(path, geminiApiOrigin)` and re-asserted to be `https://generativelanguage.googleapis.com` before fetching; the API key is appended via `searchParams` (never string-concatenated into a loggable URL).
- The native host independently validates model identifiers (`^[A-Za-z0-9._-]+$`, no `..`) and returns `400` on invalid input before anything reaches native messaging.

## Operational notes

- Treat `native_host/.proxy_token` / `/browser-data/proxy-token` as secrets. Don't put tokens in shell history, compose files, or shared config.
- noVNC has no password by default — only expose `:6080` behind a private mesh; set `VNC_PASSWORD` + `-rfbauth` otherwise.
- Docker runs the proxy as a non-root `proxy` user; the bridge Unix socket is mode `0600`.
- The repo's own CI runs the stdlib test suite on every push/PR (read-only permissions).
