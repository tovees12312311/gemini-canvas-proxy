# API Reference

The proxy exposes an OpenAI-compatible HTTP API on `localhost:8765`.

## Endpoints

| Endpoint | Method | Description |
|---|---|---|
| `/v1/chat/completions` | POST | OpenAI-compatible chat completions (tools, streaming, multimodal) |
| `/v1/models` | GET | List available models |
| `/health` | GET | Health check (the only unauthenticated endpoint) |

All `/v1/*` endpoints require `Authorization: Bearer <token>`. The token is generated on first setup (`native_host/.proxy_token` on bare metal, `/browser-data/proxy-token` in Docker) and printed by the setup scripts. `curl` returns `401` with `WWW-Authenticate: Bearer` on missing/invalid tokens.

## Chat completions

Minimal request:

```json
{
  "model": "gemini-3-flash-preview",
  "messages": [
    {"role": "system", "content": "You are concise."},
    {"role": "user", "content": "Explain HTTP in one sentence."}
  ]
}
```

Responses use standard OpenAI chat completion shape, including `choices[0].message`, `finish_reason`, and `usage`.

### Supported generation parameters

| OpenAI parameter | Maps to Gemini | Notes |
|---|---|---|
| `temperature` | `generationConfig.temperature` | |
| `max_tokens` / `max_completion_tokens` | `generationConfig.maxOutputTokens` | |
| `top_p` | `generationConfig.topP` | |
| `top_k` | `generationConfig.topK` | |
| `stop` (string or list) | `generationConfig.stopSequences` | Scalar becomes a one-item list |
| `seed` | `generationConfig.seed` | |
| `frequency_penalty` | `generationConfig.frequencyPenalty` | |
| `presence_penalty` | `generationConfig.presencePenalty` | |
| `response_format: {"type":"json_object"}` | `generationConfig.responseMimeType` | |

Unsupported options (`n > 1`, `logprobs`, `top_logprobs`, malformed `stop`) are **ignored with a stderr warning**, not silently dropped — check proxy logs to see what was skipped. Gemini returns one candidate per request.

### Finish reasons

Raw Gemini finish reasons map to OpenAI values:

| Gemini | OpenAI |
|---|---|
| `STOP` | `stop` |
| `MAX_TOKENS` | `length` |
| `SAFETY`, `RECITATION`, `BLOCKLIST`, `PROHIBITED_CONTENT` | `content_filter` |
| anything else | `stop` (with a warning) |

Safety-blocked or empty responses become HTTP `502` with the `blockReason`, `finishReason`, and `safetyRatings` preserved under `error.details` — so a blocked prompt never masquerades as an empty success.

### Streaming

Streaming is simulated: the full Gemini response is buffered, then emitted as a single SSE chunk plus `data: [DONE]`. Tool calls are correctly emitted as `choices[0].delta.tool_calls` with a final `finish_reason: "tool_calls"`, so agent frameworks see proper function-call deltas.

## Multimodal input

Send images as OpenAI-format content arrays:

```json
{
  "model": "gemini-3-flash-preview",
  "messages": [{
    "role": "user",
    "content": [
      {"type": "text", "text": "What's in this image?"},
      {"type": "image_url", "image_url": {"url": "data:image/png;base64,iVBOR..."}}
    ]
  }]
}
```

- **`data:` URIs** work by default.
- **Remote `http(s)://` images** are **disabled by default** (fetching caller-controlled URLs expands the proxy's network access). Opt in with `PROXY_ALLOW_URL_FETCH=true`; the host then rejects non-public destinations and redirects (private/loopback/link-local/metadata addresses), caps each response at 20 MB (`PROXY_MAX_IMAGE_BYTES`), requires an `image/*` content type, and converts accepted images to `inlineData`. Rejected images become an explicit `[Remote image omitted: reason]` text part plus a sanitized stderr log.

## Image generation

Nano Banana / Nano Banana 2 models return images as markdown data URLs in `message.content`:

```
![generated_image](data:image/png;base64,iVBOR...)
```

## Tool / function calling

The proxy uses **native Gemini function calling** for outgoing tool calls and conversation history:

- **Outgoing**: OpenAI `tools` are translated to Gemini `tools[{functionDeclarations}]` with **UPPERCASE** type values (`STRING`, `OBJECT`, ...) — required by Gemini 1.5+.
- **History**: assistant `tool_calls` become native `functionCall` parts, and tool results become `functionResponse` parts in a `user` turn. Gemini 3 requires a `thoughtSignature` on every `functionCall` in history — real signatures captured from responses round-trip through the OpenAI layer as `x_gemini_thought_signature`; unsigned calls get a compatibility fallback with a stderr warning.
- **Schema sanitization**: tool schemas are recursively stripped of fields Gemini rejects (`$schema`, `additionalProperties`, `title`, `format`, `nullable`, `default`, `examples`, `maxLength`/`minLength`/`pattern`, `maxItems`/`minItems`/`uniqueItems`, `items: true`) — preventing `MALFORMED_FUNCTION_CALL` / empty responses when tools come from MCP servers or strict JSON Schema sources.

## Large payloads (>900 KB)

Chrome's native messaging cap is 1 MB host→extension. The proxy chunks oversized requests automatically:

1. The host splits the serialized JSON bytes into 600 KB pieces
2. Each piece is base64-encoded into a separate `api_request_chunk` native message (every envelope verified ≤ 1 MB)
3. The extension reassembles the exact byte stream, decodes UTF-8 strictly, and forwards to Canvas

No HTTP fetch, no localhost access, no Local Network Access issues — pure native messaging. Works with CJK/emoji payloads byte-identically.

## Error codes

| Code | Meaning |
|---|---|
| `400` | Invalid JSON or invalid model identifier (letters, digits, `.`, `_`, `-` only) |
| `401` | Missing/invalid bearer token |
| `403` | CORS preflight from a non-allowed origin |
| `413` | Request body exceeds `PROXY_MAX_REQUEST_BYTES` (32 MB default) |
| `502` | Gemini blocked/empty response (details in `error.details`), or native-messaging bridge unavailable |
| `503` | No bearer token configured |
| `504` | Canvas tab not responding within 60 s |
