# Troubleshooting

Common errors, their causes, and fixes.

## "No Canvas tab found"

- Make sure you're on `gemini.google.com` with the proxy HTML in the Preview iframe
- Reload the extension at `chrome://extensions/`
- Check the extension's service worker console for debug logs

## "Specified native messaging host not found"

- Re-run the setup script with the correct extension ID
- If using **Chromium snap** (Ubuntu), the manifest must be in `~/snap/chromium/common/chromium/NativeMessagingHosts/` — the setup script handles this automatically
- Verify the `path` in the manifest points to the correct absolute path of `gemini_proxy.py`
- Extension IDs must be exactly 32 characters from `[a-p]` — the setup scripts now reject anything else

## 401 from Gemini API

- The Canvas key may have expired — re-paste the proxy HTML into Canvas
- Try a different model name (the key is model-scoped)
- Make sure `const apiKey = "";` is at the top of the script (Canvas auto-injects the key)

## 403 "unregistered caller"

- The model name in your request doesn't match what Canvas is promoting
- Try `gemini-3-flash-preview`, `gemini-2.5-flash-preview-05-20`, or check Google's current Canvas model

## [ERROR] Expected identifier but found "!"

- **Cause**: pasting `canvas-proxy.html` into a default React Canvas. Gemini's `esbuild` compiler fails on raw HTML tags like `<!DOCTYPE html>`.
- **Fix**: when starting the Canvas, explicitly ask for **"Create an HTML web app"** — this makes Gemini use the HTML renderer, which parses the proxy code correctly.

## Empty response / `completion_tokens: 0` on image inputs

- **Cause**: the proxy enables Gemini thinking by default (`includeThoughts: True`). On image inputs, thinking burns hidden tokens that count against `max_tokens`, so a low budget (20–100) returns empty with `finish_reason: "length"` and 0 output tokens.
- **Fix**: pass `"reasoning_effort": "none"` in the OpenAI body — maps to `thinkingConfig: {includeThoughts: False, thinkingBudget: 0}`. Raising `max_tokens` also works but spends a huge output budget you don't need for a one-word answer.

## empty_delta / empty response after a tool list

- **Cause**: `MALFORMED_FUNCTION_CALL`. Gemini rejected a tool schema field like `$schema`, `additionalProperties`, or `format`.
- **Fix**: the proxy sanitizes schemas automatically; if you still hit this, check the proxy logs to identify the offending field, and consider whether the tool source (MCP server, etc.) generates non-standard JSON Schema.

## Text-encoded tool calls (e.g. `[terminal(command='...')]` as plain text)

- **Cause**: broken tool-call pipeline — either streaming dropped `tool_calls`, or a `thoughtSignature` is missing from history (Gemini 3 requirement).
- **Fix**: restart the conversation (history contamination is a common cause of persistent text-fallback), and confirm the extension is reloaded so the service worker runs current code.

## 502 with `error.details`

- Gemini blocked the request (safety/policy) or returned no candidates — the details preserve `blockReason`, `finishReason`, and `safetyRatings`. A blocked prompt is no longer silently empty.
- Or: the native-messaging bridge is unavailable (Docker `--http-only` with no `--bridge-only` connected).

## 504 Gateway Timeout

- The Canvas tab is closed, unresponsive, or the extension isn't routing. Reopen the Canvas tab / reload the extension.

## Docker: login doesn't survive restarts

- The image ships the managed policy `BrowserSignin: 0` + `SyncDisabled: true` at `/etc/chromium/policies/managed/gemini-proxy-signin.json`. If the entrypoint warns it's missing, you're on an old image — rebuild.
- Ensure `browser-data` volume persists (`docker compose down`, NOT `down -v`).
- After re-login, restart the container once to confirm.

## Docker: `docker compose exec proxy /app/setup-extension.sh` rejects the ID

- Chrome extension IDs are exactly 32 chars from `[a-p]`. Copy the full ID from `chrome://extensions`.

## Dev: running the tests

```bash
python3 -m unittest discover -s tests -v
```

The suite is stdlib-only (no third-party deps) and runs in CI on every push/PR.

---

## Limitations

- **Canvas tab must stay open** — closing it kills the proxy
- **Model-scoped key** — only the currently promoted model works
- **Large payloads** — >900 KB requests are chunked below Chrome's 1 MB native-messaging cap (byte-accurate base64 reassembly)
- **No real streaming** — responses are buffered then sent as a single SSE chunk (but `tool_calls` are correctly emitted with proper `finish_reason`)
- **ToS risk** — using Canvas credentials outside Canvas may violate Google's Terms of Service
- **Tool calling** — native Gemini function calling with `thoughtSignature` for history; schemas auto-sanitized for Gemini compatibility
