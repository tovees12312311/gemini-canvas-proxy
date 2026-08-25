#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════
# Gemini Canvas Proxy — Setup Script (WSL + Windows Chrome)
# ═══════════════════════════════════════════════════════════════════════════
# For the common WSL setup: the repo lives inside WSL, but Chrome runs on
# WINDOWS. Windows Chrome discovers native messaging hosts via the Windows
# REGISTRY — not via ~/.config inside WSL — and it can only launch Windows
# executables. So this script:
#
#   1. Generates (or reuses) the bearer token, inside WSL
#   2. Asks for the Chrome extension ID (after you load the extension)
#   3. Writes a .bat wrapper into %LOCALAPPDATA%\GeminiCanvasProxy that
#      re-enters WSL via wsl.exe and runs the Python native host HERE
#   4. Writes the native messaging manifest next to it (with Windows paths)
#   5. Registers the manifest in the Windows registry (Chrome/Edge/Chromium)
#
# Result: Windows Chrome ⇄ wsl.exe ⇄ Python host in WSL. The HTTP server
# listens inside WSL on 127.0.0.1:8765, so your WSL terminal can curl it
# directly, and Windows apps reach it via localhost:8765 thanks to WSL2's
# localhost forwarding.
#
# If your Chrome runs INSIDE WSL (WSLg / Linux Chrome), use ./setup.sh instead.
# ═══════════════════════════════════════════════════════════════════════════

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NATIVE_HOST_NAME="com.gemini.proxy"
HOST_SCRIPT="$SCRIPT_DIR/native_host/gemini_proxy.py"
TOKEN_FILE="$SCRIPT_DIR/native_host/.proxy_token"

# ── Sanity checks ────────────────────────────────────────────────────────────

if [ ! -f "$HOST_SCRIPT" ]; then
    echo "✗ ERROR: gemini_proxy.py not found at $HOST_SCRIPT"
    echo "  Make sure you're running this from the gemini-canvas-proxy directory."
    exit 1
fi

if ! grep -qiE '(microsoft|wsl)' /proc/version 2>/dev/null; then
    echo "✗ ERROR: This doesn't look like WSL."
    echo "  Use ./setup.sh on native Linux/macOS, or .\\setup.ps1 on Windows."
    exit 1
fi

if ! command -v wsl.exe &>/dev/null || ! command -v reg.exe &>/dev/null; then
    echo "✗ ERROR: Windows interop (wsl.exe / reg.exe) is unavailable."
    echo "  Enable it in /etc/wsl.conf:  [interop] enabled=true"
    echo "  then run 'wsl.exe --shutdown' from Windows and reopen this terminal."
    exit 1
fi

if ! command -v python3 &>/dev/null; then
    echo "✗ ERROR: python3 not found inside WSL. The native host requires Python 3.8+."
    echo "  Install with: sudo apt install python3"
    exit 1
fi

DISTRO_NAME="${WSL_DISTRO_NAME:-}"
if [ -z "$DISTRO_NAME" ]; then
    echo "✗ ERROR: \$WSL_DISTRO_NAME is not set; cannot determine the distro name"
    echo "  that wsl.exe should target. Re-open your WSL terminal and retry."
    exit 1
fi

echo "╔══════════════════════════════════════════════════════════════╗"
echo "║   Gemini Canvas Proxy — Setup (WSL + Windows Chrome)         ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""
echo "✓ WSL distro: $DISTRO_NAME"

chmod +x "$HOST_SCRIPT"
echo "✓ Native host script is executable"

# ── Step 1: Bearer token (lives inside WSL, next to the Python host) ─────────

if [ ! -s "$TOKEN_FILE" ]; then
    umask 077
    python3 -c 'import uuid; print(uuid.uuid4())' > "$TOKEN_FILE"
fi
chmod 600 "$TOKEN_FILE"
PROXY_TOKEN="$(tr -d '\r\n' < "$TOKEN_FILE")"
echo "✓ Bearer token written to $TOKEN_FILE"

# ── Step 2: Get the extension ID ─────────────────────────────────────────────
# NOTE: load the extension in WINDOWS Chrome. The extension/ folder is
# reachable from Windows via the \\wsl.localhost share.

EXT_DIR_WIN="$(wslpath -w "$SCRIPT_DIR/extension" 2>/dev/null || echo "\\\\wsl.localhost\\$DISTRO_NAME$SCRIPT_DIR/extension")"

echo ""
echo "━━━ Load the Chrome Extension (in WINDOWS Chrome) ━━━"
echo "1. Open chrome://extensions/ in your Windows Chrome"
echo "2. Enable 'Developer mode' (top-right toggle)"
echo "3. Click 'Load unpacked' and paste this path into the file picker:"
echo "     $EXT_DIR_WIN"
echo "4. Copy the Extension ID (32-char string below the extension name)"
echo ""
read -p "Paste Extension ID: " EXTENSION_ID

if ! [[ "$EXTENSION_ID" =~ ^[a-p]{32}$ ]]; then
    echo "✗ Invalid extension ID."
    echo "  Chrome extension IDs must contain exactly 32 characters from a-p."
    exit 1
fi

echo ""
echo "✓ Extension ID: $EXTENSION_ID"

# ── Step 3: Locate %LOCALAPPDATA% on the Windows side ────────────────────────
# cmd.exe prints a harmless UNC-path warning when invoked from a WSL cwd, so
# silence stderr. Output arrives with a trailing \r.

LOCALAPPDATA_WIN="$(cd /mnt/c 2>/dev/null && cmd.exe /c "echo %LOCALAPPDATA%" 2>/dev/null | tr -d '\r')"
if [ -z "$LOCALAPPDATA_WIN" ] || [[ "$LOCALAPPDATA_WIN" == *"%LOCALAPPDATA%"* ]]; then
    LOCALAPPDATA_WIN="$(powershell.exe -NoProfile -Command '$env:LOCALAPPDATA' 2>/dev/null | tr -d '\r')"
fi
if [ -z "$LOCALAPPDATA_WIN" ]; then
    echo "✗ ERROR: could not resolve %LOCALAPPDATA% on the Windows side."
    exit 1
fi

WIN_DIR_WIN="$LOCALAPPDATA_WIN\\GeminiCanvasProxy"
WIN_DIR_WSL="$(wslpath -u "$WIN_DIR_WIN" 2>/dev/null || true)"
if [ -z "$WIN_DIR_WSL" ]; then
    echo "✗ ERROR: could not translate $WIN_DIR_WIN to a WSL path (is C: mounted?)."
    exit 1
fi
mkdir -p "$WIN_DIR_WSL"

# ── Step 4: Write the .bat wrapper ───────────────────────────────────────────
# Windows Chrome launches this .bat; it hops into WSL and execs the Python
# host. `--exec` skips the shell so stdio passes through unmodified — that
# matters because native messaging is a binary protocol on stdin/stdout.

BAT_WIN="$WIN_DIR_WIN\\gemini_proxy.bat"
BAT_WSL="$WIN_DIR_WSL/gemini_proxy.bat"

printf '@echo off\r\nwsl.exe -d %s --exec /usr/bin/env python3 "%s"\r\n' \
    "$DISTRO_NAME" "$HOST_SCRIPT" > "$BAT_WSL"
echo "✓ Wrapper: $BAT_WIN"
echo "    → wsl.exe -d $DISTRO_NAME --exec /usr/bin/env python3 $HOST_SCRIPT"

# ── Step 5: Write the manifest (Windows paths, escaped for JSON) ─────────────

MANIFEST_WIN="$WIN_DIR_WIN\\$NATIVE_HOST_NAME.json"
MANIFEST_WSL="$WIN_DIR_WSL/$NATIVE_HOST_NAME.json"
BAT_WIN_JSON="${BAT_WIN//\\/\\\\}"

cat > "$MANIFEST_WSL" << EOF
{
    "name": "$NATIVE_HOST_NAME",
    "description": "Gemini Canvas Proxy — free unlimited LLM API via Canvas MessageChannel bridge",
    "path": "$BAT_WIN_JSON",
    "type": "stdio",
    "allowed_origins": ["chrome-extension://$EXTENSION_ID/"]
}
EOF
echo "✓ Manifest: $MANIFEST_WIN"

# ── Step 6: Register in the Windows registry ─────────────────────────────────
# Windows Chrome/Edge discover native hosts via HKCU registry keys, not files.

INSTALLED_COUNT=0
register_browser() {
    local reg_key="$1"
    local display_name="$2"
    if reg.exe add "$reg_key\\$NATIVE_HOST_NAME" /ve /t REG_SZ /d "$MANIFEST_WIN" /f >/dev/null 2>&1; then
        INSTALLED_COUNT=$((INSTALLED_COUNT + 1))
        echo "  ✓ $display_name → $reg_key\\$NATIVE_HOST_NAME"
    else
        echo "  ⊘ $display_name (registry write failed)"
    fi
}

echo ""
echo "Registering native messaging host in the Windows registry:"
register_browser 'HKCU\Software\Google\Chrome\NativeMessagingHosts' "Google Chrome"
register_browser 'HKCU\Software\Microsoft\Edge\NativeMessagingHosts' "Microsoft Edge"
register_browser 'HKCU\Software\Chromium\NativeMessagingHosts' "Chromium"

if [ "$INSTALLED_COUNT" -eq 0 ]; then
    echo "✗ ERROR: could not write any registry keys via reg.exe."
    exit 1
fi

# ── Done ─────────────────────────────────────────────────────────────────────

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║                  Setup Complete                              ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""
echo "IMPORTANT: fully restart Windows Chrome now (chrome://restart, or quit"
echo "from the tray) — Chrome only reads native messaging registry keys at start."
echo ""
echo "Next steps (all in Windows Chrome):"
echo ""
echo "  1. Go to gemini.google.com"
echo "  2. Click the '+' icon (left of the prompt bar)"
echo "  3. Select 'Canvas' from the menu"
echo "  4. Type: Create an HTML web app"
echo "  5. Switch to the Code tab (top of the Canvas panel)"
echo "  6. Select all generated code → delete it"
echo "  7. Open canvas-proxy.html from this project"
echo "  8. Copy ALL contents → paste into Canvas code editor"
echo "  9. Click Preview — you should see 'Gemini Canvas Proxy'"
echo "     with a green 'Proxy Active' status"
echo ""
echo "  10. Test from this WSL terminal:"
echo "      curl http://127.0.0.1:8765/v1/chat/completions \\"
echo "        -H 'Authorization: Bearer $PROXY_TOKEN' \\"
echo "        -H 'Content-Type: application/json' \\"
echo "        -d '{\"model\":\"gemini-3-flash-preview\",\"messages\":[{\"role\":\"user\",\"content\":\"Hello!\"}]}'"
echo ""
echo "  The API also works from Windows apps at http://localhost:8765/v1"
echo "  (WSL2 forwards localhost automatically)."
echo ""
echo "  Bearer token: $PROXY_TOKEN"
echo "  Keep this token private; clients must send it as their API key."
echo ""
