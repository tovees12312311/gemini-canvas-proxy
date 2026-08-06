# Deployment

Ways to run the Gemini Canvas Proxy: bare metal, Docker Compose (local or VPS), or Podman.

## Bare metal

```bash
git clone https://github.com/pranrichh/gemini-canvas-proxy.git
cd gemini-canvas-proxy
./setup.sh            # Linux/macOS — or .\setup.ps1 on Windows
```

The setup script verifies Python, writes the native messaging manifest, and generates a bearer token. The native host auto-starts when Chrome loads the extension and auto-stops when Chrome closes. Keep the Gemini tab open — the proxy lives and dies with it.

- **Stop:** `./stop.sh` (Linux/macOS), or reload/disable the extension.
- **Windows:** stop the `python.exe` process whose command line contains `gemini_proxy`, or reload the extension.

## Docker Compose (self-contained)

The single-service stack runs everything in one container: Xvfb + Openbox + Chromium + x11vnc + noVNC + the Python proxy. Log into Gemini through the noVNC web UI in your own browser — no local Chrome needed.

**What's in the container:** virtual display, window manager, Chromium with a persistent profile, VNC server, noVNC UI on `:6080`, and the OpenAI-compatible API on `:8765`. Login cookies, the native messaging manifest, and the bearer token survive container restarts via the `browser-data` volume. The proxy runs in two explicit roles (`--http-only` entrypoint + `--bridge-only` Chromium-launched bridge) talking over a mode-`0600` Unix socket — only one process ever binds port 8765.

### Local loopback (default)

```bash
docker compose up -d --build
open http://127.0.0.1:6080/vnc.html?autoconnect=true&resize=scale
```

Both ports bind `127.0.0.1` — nothing on your LAN can reach them.

**First-time setup inside the container:**

1. In the noVNC window: log in to `gemini.google.com`, open `chrome://extensions`, enable Developer mode, **Load unpacked → `/app/extension`** (bind-mounted read-only from the repo).
2. Copy the Extension ID (32 lowercase `[a-p]` chars).
3. From your laptop:
   ```bash
   docker compose exec proxy /app/setup-extension.sh <extension-id>
   docker compose restart proxy
   ```
4. Read the token and test:
   ```bash
   PROXY_TOKEN="$(docker compose exec -T proxy cat /browser-data/proxy-token)"
   curl -H "Authorization: Bearer $PROXY_TOKEN" http://127.0.0.1:8765/v1/models
   ```

After setup, container restarts, host reboots, and `docker compose down/up` cycles all preserve login, manifest, and token.

### VPS / Tailscale (override)

`docker-compose.vps.yml` flips both ports to `0.0.0.0` so they're reachable via the VPS's Tailscale IP:

```bash
docker compose -f docker-compose.yml -f docker-compose.vps.yml up -d --build
# From any tailnet device:
open http://<vps-tailscale-ip>:6080/vnc.html?autoconnect=true&resize=scale
curl -H "Authorization: Bearer $PROXY_TOKEN" http://<vps-tailscale-ip>:8765/v1/models
```

**Security:** the proxy requires its bearer token, but noVNC has no VNC password by default. Authentication does not replace network isolation — only expose `0.0.0.0:6080` and `0.0.0.0:8765` behind a private mesh (Tailscale, WireGuard, firewall) restricted to known peers. Keep the token private. For a VNC password, set `VNC_PASSWORD` and pass `-rfbauth` to x11vnc in `entrypoint.sh`.

### Shared folder with the host (override)

By default `/browser-data` is a Docker-managed named volume. To share it with the host — so the same folder backs both the in-container Chromium and a host Chrome you launch separately:

```bash
# Default: shares ./browser-data (created next to docker-compose.yml on first run)
docker compose -f docker-compose.yml -f docker-compose.shared.yml up -d --build

# Custom host path
BROWSER_DATA_HOST=~/.gemini-canvas-proxy/browser-data \
  docker compose -f docker-compose.yml -f docker-compose.shared.yml up -d --build
```

Point host Chrome at the same path to reuse cookies:

```bash
google-chrome --user-data-dir="$PWD/browser-data" chrome://extensions
```

Combine all overrides for a VPS reachable via Tailscale with browser state on a host path:

```bash
docker compose -f docker-compose.yml \
               -f docker-compose.shared.yml \
               -f docker-compose.vps.yml up -d --build
```

### Image notes

- Base `python:3.12-slim` + Debian's `chromium`, `xvfb`, `x11vnc`, `novnc`, `websockify`, `openbox`. ~600 MB on disk.
- Runs as non-root `proxy` user (UID/GID 1000) via `tini` as PID 1.
- `/dev/shm` bumped to 1 GB (`shm_size: 1g`) — Chromium OOMs without it.
- Managed Chromium policy (`chromium-policies/managed/gemini-proxy-signin.json`: `BrowserSignin: 0`, `SyncDisabled: true`) stops Google's Account Reconcilor from wiping cookie-only sessions — this is what makes login survive restarts. The entrypoint warns if the policy file is missing.
- Stop: `docker compose down`. Wipe everything: `docker compose down -v`. Logs: `docker compose logs -f`.

## Podman

For rootless/systemd environments (Fedora, RHEL, etc.), a quadlet unit (`gemini-canvas-proxy.container`) and guide are included:

```bash
podman build -t localhost/gemini-canvas-proxy:local .
# adjust Volume= paths in gemini-canvas-proxy.container, then:
mkdir -p ~/.config/containers/systemd
cp gemini-canvas-proxy.container ~/.config/containers/systemd/
systemctl --user daemon-reload
systemctl --user start gemini-canvas-proxy.service
```

See [docs/podman.md](podman.md) for the full guide, including a VNC toggle to save RAM on small VPS boxes:

```bash
podman exec gemini-canvas-proxy /app/toggle-vnc.sh stop    # save CPU/RAM
podman exec gemini-canvas-proxy /app/toggle-vnc.sh start   # bring noVNC back
podman exec gemini-canvas-proxy /app/toggle-vnc.sh status
```

## Daily usage

1. **Keep the Gemini tab open** — the Canvas tab with the proxy HTML must stay open. Background tab, minimized window, or a separate Chrome profile all work.
2. **Reload the extension** after a browser restart — the native host auto-reconnects.
3. **The proxy auto-starts** when Chrome launches the extension — no manual process management.
