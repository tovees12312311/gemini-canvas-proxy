# Podman Deployment

Alternative to Docker Compose for rootless/systemd environments (Fedora, RHEL,
and other distributions where `podman` is the default container engine).

## Why login survives restarts

Google login persists across container restarts when all of these hold:

1. Chromium runs with a **persistent profile** (`--user-data-dir` on a volume).
2. The managed Chromium policy is present:
   - `BrowserSignin: 0`
   - `SyncDisabled: true`

   This stops Google's Account Reconcilor from wiping cookie-only sessions
   (the classic "login works, then vanishes on restart" bug). The image ships
   this policy at `/etc/chromium/policies/managed/gemini-proxy-signin.json`;
   the entrypoint warns if it's missing.
3. The `browser-data` volume (Chromium profile + native messaging manifest) is
   persistent.

## Quick start (quadlet)

A systemd quadlet unit is included at `gemini-canvas-proxy.container`:

```bash
# 1. Build the image
podman build -t localhost/gemini-canvas-proxy:local .

# 2. Adjust the Volume= paths in gemini-canvas-proxy.container to your clone
#    (the file uses %h/Ai/gemini-canvas-proxy as an example).

# 3. Install as a user service
mkdir -p ~/.config/containers/systemd
cp gemini-canvas-proxy.container ~/.config/containers/systemd/
systemctl --user daemon-reload
systemctl --user start gemini-canvas-proxy.service

# 4. Verify
systemctl --user status gemini-canvas-proxy.service
```

## Manual `podman run`

```bash
podman run -d \
  --name gemini-canvas-proxy \
  -p 6080:6080 -p 8765:8765 \
  -v gemini-canvas-proxy-data:/browser-data \
  -v "$PWD":/app:ro,Z \
  localhost/gemini-canvas-proxy:local
```

## First-time setup

1. Open `http://<host-ip>:6080/vnc.html?autoconnect=true&resize=scale`
2. Log in to `gemini.google.com`
3. `chrome://extensions` → enable Developer mode → Load unpacked → `/app/extension`
4. Copy the Extension ID (32 lowercase chars, `[a-p]`)
5. Register the native messaging host:
   ```bash
   podman exec gemini-canvas-proxy /app/setup-extension.sh <extension-id>
   ```
6. Restart the unit once so Chromium re-reads the manifest:
   ```bash
   systemctl --user restart gemini-canvas-proxy.service
   ```
7. The proxy is on `http://127.0.0.1:8765/v1` — authenticate with the bearer
   token printed at startup (`podman logs gemini-canvas-proxy | grep token`).

## Saving RAM: VNC toggle

The container always starts Xvfb, but x11vnc + websockify can be stopped when
you don't need the browser view — useful on small VPS boxes:

```bash
podman exec gemini-canvas-proxy /app/toggle-vnc.sh stop    # save CPU/RAM
podman exec gemini-canvas-proxy /app/toggle-vnc.sh start   # bring noVNC back
podman exec gemini-canvas-proxy /app/toggle-vnc.sh status
```

`start` re-execs as the `proxy` user (same as Xvfb) — running it as root hits
MIT-SHM attach errors.

## Diagnostics

```bash
podman exec gemini-canvas-proxy ps aux
podman exec gemini-canvas-proxy cat /tmp/chromium.log
podman exec gemini-canvas-proxy cat /tmp/proxy.log
journalctl --user -u gemini-canvas-proxy.service -n 80 --no-pager
```
