#!/usr/bin/env bash
# ---------------------------------------------------------------------------
#  Inkognito · installer and launcher for Proxmox VE, Linux and macOS
#  A locally launched, privacy-first LinkedIn formatter for self-hosting.
#
#  One line (keeps the prompts working):
#    bash -c "$(curl -fsSL https://raw.githubusercontent.com/4velinux/inkognito/main/install.sh)"
#
#  On a Proxmox VE host it acts as a helper script and creates an Alpine LXC.
#  Anywhere else it installs to your user folder, serves the app on
#  http://localhost:8765 (this machine only) and opens your browser.
#  Windows: use install.ps1. Git Bash and WSL also work with this script.
#
#  After the first run, use the `inkognito` command:
#    inkognito                 start if needed and open the browser
#    inkognito --stop          stop the local server
#    inkognito --update        download the newest release (checksum-verified)
#    inkognito --autostart on  start with your login (off to disable)
#    inkognito --status        show version, port and state
#    inkognito --uninstall     remove everything this script installed
#  Options: --port N · --lan (listen on your network, not only this machine)
#           --no-browser · --serve (run in the foreground) · --local · --proxmox
#
#  Privacy: launching never touches the network. Only the first install and
#  --update download the app, from GitHub releases, verified by SHA-256.
# ---------------------------------------------------------------------------
set -Eeuo pipefail

LAUNCHER_VERSION="1.1.0"
REPO="${INKOGNITO_REPO:-4velinux/inkognito}"
REF="${INKOGNITO_REF:-main}"
RAW="https://raw.githubusercontent.com/${REPO}/${REF}"
REL="https://github.com/${REPO}/releases/latest/download"
DEFAULT_PORT=8765

ACTION="launch"; MODE="auto"; OPEN=1; BIND="127.0.0.1"; PORT_ARG="${INKOGNITO_PORT:-}"; AUTOSTART_ARG=""

usage() { sed -n '2,31p' "${BASH_SOURCE[0]:-/dev/null}" 2>/dev/null | sed 's/^# \{0,1\}//' || true; echo "See https://github.com/${REPO}"; }
while [ $# -gt 0 ]; do
  case "$1" in
    --stop) ACTION="stop" ;;
    --update) ACTION="update" ;;
    --status) ACTION="status" ;;
    --uninstall) ACTION="uninstall" ;;
    --serve) ACTION="serve" ;;
    --autostart) ACTION="autostart"; AUTOSTART_ARG="${2:-on}"; shift ;;
    --port) PORT_ARG="${2:?--port needs a number}"; shift ;;
    --lan) BIND="0.0.0.0" ;;
    --no-browser) OPEN=0 ;;
    --local) MODE="local" ;;
    --proxmox) MODE="proxmox" ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1 (try --help)"; exit 1 ;;
  esac
  shift
done

if [ -t 1 ]; then BL=$'\e[38;5;69m'; GN=$'\e[32m'; RD=$'\e[31m'; YW=$'\e[33m'; DIM=$'\e[2m'; B=$'\e[1m'; CL=$'\e[0m'; else BL=""; GN=""; RD=""; YW=""; DIM=""; B=""; CL=""; fi
msg()  { printf ' %s›%s %s\n' "$BL" "$CL" "$*"; }
ok()   { printf ' %s✓%s %s\n' "$GN" "$CL" "$*"; }
warn() { printf ' %s!%s %s\n' "$YW" "$CL" "$*"; }
die()  { printf ' %s✗%s %s\n' "$RD" "$CL" "$*" >&2; exit 1; }

# --- where am I -------------------------------------------------------------
OS="other"; WSL=0
case "$(uname -s 2>/dev/null || echo unknown)" in
  Darwin) OS="mac" ;;
  Linux) OS="linux"; grep -qi microsoft /proc/version 2>/dev/null && WSL=1 ;;
  MINGW*|MSYS*|CYGWIN*) OS="win" ;;
esac
is_proxmox() { command -v pveversion >/dev/null 2>&1 && command -v pct >/dev/null 2>&1; }

case "$OS" in
  mac) DATA="$HOME/Library/Application Support/Inkognito" ;;
  win) DATA="${LOCALAPPDATA:-$HOME/AppData/Local}/Inkognito" ;;
  *)   DATA="${XDG_DATA_HOME:-$HOME/.local/share}/inkognito" ;;
esac
WWW="$DATA/www"; APP="$WWW/index.html"; SELF="$DATA/inkognito.sh"
PIDF="$DATA/server.pid"; LOG="$DATA/server.log"; PORTF="$DATA/port"
BIN="$HOME/.local/bin/inkognito"
SCRIPT_DIR=""
if [ -n "${BASH_SOURCE[0]:-}" ] && [ -f "${BASH_SOURCE[0]}" ]; then SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; fi

# --- helpers ----------------------------------------------------------------
download() { # url dest
  if command -v curl >/dev/null 2>&1; then curl -fsSL --max-time 90 -o "$2" "$1"
  elif command -v wget >/dev/null 2>&1; then wget -q -T 90 -O "$2" "$1"
  else die "Needs curl or wget to download the app."; fi
}
sha256() { if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d' ' -f1; else shasum -a 256 "$1" | cut -d' ' -f1; fi; }
app_version() { sed -n "s/.*var VERSION='\([^']*\)'.*/\1/p" "$1" 2>/dev/null | head -n1; }
check_app() {
  grep -q '<title>Inkognito</title>' "$1" || die "Downloaded file is not Inkognito."
  grep -q "connect-src 'none'" "$1" || die "Refusing a build without the privacy lock."
}
port_open() { (exec 3<>"/dev/tcp/127.0.0.1/$1") >/dev/null 2>&1; }
is_ours() { # port
  local reply=""
  reply="$( (exec 3<>"/dev/tcp/127.0.0.1/$1" && printf 'GET / HTTP/1.0\r\nHost: localhost\r\n\r\n' >&3 && head -c 4000 <&3) 2>/dev/null || true)"
  case "$reply" in *"<title>Inkognito</title>"*) return 0 ;; *) return 1 ;; esac
}
pick_port() {
  local p="${PORT_ARG:-}"
  if [ -z "$p" ] && [ -f "$PORTF" ]; then p="$(cat "$PORTF")"; fi
  p="${p:-$DEFAULT_PORT}"
  if port_open "$p" && ! is_ours "$p"; then
    if [ -n "$PORT_ARG" ]; then die "Port $p is used by another program. Pick another with --port."; fi
    local q=$((p + 1)); while port_open "$q"; do q=$((q + 1)); done
    warn "Port $p is busy, using $q. Drafts are saved per address, so drafts from :$p will not show on :$q." >&2
    p="$q"
  fi
  echo "$p"
}

fetch_app() {
  mkdir -p "$WWW"
  local tmp; tmp="$(mktemp -d)"
  local src="${INKOGNITO_FILE:-}"
  if [ -z "$src" ] && [ -n "$SCRIPT_DIR" ] && [ -f "$SCRIPT_DIR/inkognito.html" ]; then src="$SCRIPT_DIR/inkognito.html"; fi
  if [ -n "$src" ]; then
    msg "Using the app from $src"
    cp "$src" "$tmp/app.html"
  else
    msg "Downloading the latest release of $REPO"
    if download "$REL/inkognito.html" "$tmp/app.html" 2>/dev/null; then
      download "$REL/inkognito.html.sha256" "$tmp/app.sha256" || die "The release has no checksum file."
      [ "$(cut -d' ' -f1 "$tmp/app.sha256")" = "$(sha256 "$tmp/app.html")" ] || die "Checksum mismatch. Nothing was installed."
      ok "Checksum verified"
    else
      warn "No release yet, using the main branch (no checksum available)."
      download "$RAW/inkognito.html" "$tmp/app.html" || die "Download failed. Are you online?"
    fi
  fi
  check_app "$tmp/app.html"
  if [ -f "$APP" ] && [ "$(sha256 "$APP")" = "$(sha256 "$tmp/app.html")" ]; then
    ok "Already on v$(app_version "$APP")"
  else
    [ -f "$APP" ] && cp "$APP" "$DATA/previous.html"
    mv "$tmp/app.html" "$APP"; chmod 644 "$APP"
    ok "Installed Inkognito v$(app_version "$APP")"
  fi
  printf 'v%s\n' "$(app_version "$APP")" > "$WWW/version.txt"
  rm -rf "$tmp"
}

install_self() {
  mkdir -p "$DATA" "$(dirname "$BIN")"
  if [ -n "$SCRIPT_DIR" ] && [ "${BASH_SOURCE[0]}" != "$SELF" ]; then cp "${BASH_SOURCE[0]}" "$SELF.new"
  elif [ ! -f "$SELF" ] || [ "$ACTION" = "update" ]; then download "$RAW/install.sh" "$SELF.new"
  fi
  if [ -f "$SELF.new" ]; then mv "$SELF.new" "$SELF"; chmod 755 "$SELF"; fi
  if [ "$OS" != "win" ]; then ln -sf "$SELF" "$BIN" 2>/dev/null || true; fi
  if [ "$OS" = "linux" ] && [ "$WSL" = 0 ]; then
    mkdir -p "$HOME/.local/share/applications"
    cat > "$HOME/.local/share/applications/inkognito.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Inkognito
Comment=Privacy-first LinkedIn formatter
Exec="$SELF"
Icon=accessories-text-editor
Terminal=false
Categories=Office;Utility;
EOF
  fi
}

find_python() {
  local c v
  for c in python3 python; do
    command -v "$c" >/dev/null 2>&1 || continue
    # macOS ships a stub python3 that opens an installer dialog: skip it unless developer tools exist
    if [ "$OS" = "mac" ] && [ "$(command -v "$c")" = "/usr/bin/python3" ] && ! xcode-select -p >/dev/null 2>&1; then continue; fi
    v="$("$c" -c 'import sys;print(sys.version_info>=(3,7))' 2>/dev/null || true)"
    [ "$v" = "True" ] && { echo "$c"; return 0; }
  done
  return 1
}

read -r -d '' PY_SERVER <<'PY' || true
import http.server, socketserver, sys
port, bind, root = int(sys.argv[1]), sys.argv[2], sys.argv[3]
CSP = ("default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; img-src data: blob:; "
       "font-src data:; connect-src 'none'; form-action 'none'; base-uri 'none'; frame-ancestors 'none'")
HEADERS = {
    "Cache-Control": "no-cache", "X-Content-Type-Options": "nosniff", "X-Frame-Options": "DENY",
    "Referrer-Policy": "no-referrer", "Cross-Origin-Opener-Policy": "same-origin",
    "Permissions-Policy": "camera=(), microphone=(), geolocation=(), payment=(), usb=()",
    "Content-Security-Policy": CSP,
}
class H(http.server.SimpleHTTPRequestHandler):
    def __init__(s, *a, **k): super().__init__(*a, directory=root, **k)
    def end_headers(s):
        for k, v in HEADERS.items(): s.send_header(k, v)
        super().end_headers()
    def log_message(s, *a): pass
    def do_GET(s):
        if s.path.split("?")[0] not in ("/", "/index.html", "/version.txt"): return s.send_error(404)
        return super().do_GET()
    def do_HEAD(s):
        if s.path.split("?")[0] not in ("/", "/index.html", "/version.txt"): return s.send_error(404)
        return super().do_HEAD()
class S(socketserver.ThreadingMixIn, http.server.HTTPServer):
    daemon_threads = True
    allow_reuse_address = True
print("Inkognito serving on http://%s:%d" % ("localhost" if bind == "127.0.0.1" else bind, port), flush=True)
try:
    S((bind, port), H).serve_forever()
except KeyboardInterrupt:
    pass
PY

serve_fg() { # foreground; replaces this process so the PID is the server
  local port="$1" py
  [ -f "$APP" ] || die "App not installed yet. Run without --serve first."
  case "${INKOGNITO_SERVER:-auto}" in
    auto|python) if py="$(find_python)"; then exec "$py" -c "$PY_SERVER" "$port" "$BIND" "$WWW"; fi ;;
  esac
  case "${INKOGNITO_SERVER:-auto}" in
    auto|ruby) if command -v ruby >/dev/null 2>&1 && ruby -e 'require "webrick"' 2>/dev/null; then exec ruby -run -e httpd -- "$WWW" -p "$port" -b "$BIND"; fi ;;
  esac
  return 1
}

open_browser() {
  local url="$1"
  [ "$OPEN" = 1 ] || return 0
  case "$OS" in
    mac) open "$url" ;;
    win) cmd.exe //c start "" "$url" >/dev/null 2>&1 || start "$url" ;;
    linux)
      if [ "$WSL" = 1 ]; then (command -v wslview >/dev/null && wslview "$url") || cmd.exe /c start "" "$url" >/dev/null 2>&1 || true
      elif [ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ] && command -v xdg-open >/dev/null 2>&1; then xdg-open "$url" >/dev/null 2>&1 &
      else msg "No desktop session found. Open $url in a browser."; fi ;;
    *) msg "Open $url in a browser." ;;
  esac
}

running_pid() { [ -f "$PIDF" ] && kill -0 "$(cat "$PIDF")" 2>/dev/null && cat "$PIDF"; }

start_bg() { # port
  local port="$1"
  if is_ours "$port"; then ok "Already running on port $port"; return 0; fi
  if ! find_python >/dev/null && ! { command -v ruby >/dev/null 2>&1 && ruby -e 'require "webrick"' 2>/dev/null; }; then
    warn "No Python 3 or Ruby found to run a local server."
    msg "Opening the app straight from disk instead (it works the same)."
    open_browser "file://$APP"; exit 0
  fi
  local lan=""; [ "$BIND" = "0.0.0.0" ] && lan="--lan"
  # shellcheck disable=SC2086
  nohup bash "$SELF" --serve --port "$port" $lan > "$LOG" 2>&1 &
  echo $! > "$PIDF"
  for _ in $(seq 1 50); do port_open "$port" && break; sleep 0.1; done
  port_open "$port" || { cat "$LOG" >&2; die "The server did not start (log above)."; }
  echo "$port" > "$PORTF"
  ok "Serving on http://localhost:$port ${DIM}(pid $(cat "$PIDF"))${CL}"
}

stop_server() {
  local pid; pid="$(running_pid || true)"
  if [ -n "$pid" ]; then
    pkill -P "$pid" 2>/dev/null || true; kill "$pid" 2>/dev/null || true; rm -f "$PIDF"; ok "Stopped"
  else msg "Not running from this launcher."; fi
  if autostart_state >/dev/null 2>&1 && [ "$(autostart_state)" = "on" ]; then warn "Autostart is on, so it will start again at login. Turn off with: inkognito --autostart off"; fi
}

LA_LABEL="io.github.inkognito"
LA_PLIST="$HOME/Library/LaunchAgents/$LA_LABEL.plist"
SD_UNIT="$HOME/.config/systemd/user/inkognito.service"
autostart_state() {
  case "$OS" in
    mac) [ -f "$LA_PLIST" ] && echo on || echo off ;;
    linux) [ -f "$SD_UNIT" ] || [ -f "$HOME/.config/autostart/inkognito.desktop" ] && echo on || echo off ;;
    *) echo "n/a" ;;
  esac
}
autostart() { # on|off
  local port; port="$(cat "$PORTF" 2>/dev/null || echo "$DEFAULT_PORT")"
  case "$OS:$1" in
    mac:on)
      mkdir -p "$(dirname "$LA_PLIST")"
      cat > "$LA_PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>$LA_LABEL</string>
  <key>ProgramArguments</key><array><string>/bin/bash</string><string>$SELF</string><string>--serve</string><string>--port</string><string>$port</string></array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>StandardErrorPath</key><string>$LOG</string>
</dict></plist>
EOF
      stop_server >/dev/null 2>&1 || true
      launchctl bootout "gui/$(id -u)/$LA_LABEL" >/dev/null 2>&1 || true
      launchctl bootstrap "gui/$(id -u)" "$LA_PLIST" 2>/dev/null || launchctl load -w "$LA_PLIST"
      ok "Starts at login on http://localhost:$port" ;;
    mac:off)
      launchctl bootout "gui/$(id -u)/$LA_LABEL" >/dev/null 2>&1 || launchctl unload -w "$LA_PLIST" >/dev/null 2>&1 || true
      rm -f "$LA_PLIST"; ok "Autostart off" ;;
    linux:on)
      if command -v systemctl >/dev/null 2>&1 && systemctl --user show-environment >/dev/null 2>&1; then
        mkdir -p "$(dirname "$SD_UNIT")"
        cat > "$SD_UNIT" <<EOF
[Unit]
Description=Inkognito privacy-first LinkedIn formatter (localhost:$port)

[Service]
ExecStart=/usr/bin/env bash "$SELF" --serve --port $port$([ "$BIND" = 0.0.0.0 ] && echo " --lan")
Restart=on-failure
NoNewPrivileges=yes
PrivateTmp=yes

[Install]
WantedBy=default.target
EOF
        stop_server >/dev/null 2>&1 || true
        systemctl --user daemon-reload && systemctl --user enable --now inkognito.service >/dev/null
        ok "Starts at login on http://localhost:$port (systemd user service)"
      else
        mkdir -p "$HOME/.config/autostart"
        printf '[Desktop Entry]\nType=Application\nName=Inkognito server\nExec="%s" --no-browser\nX-GNOME-Autostart-enabled=true\n' "$SELF" > "$HOME/.config/autostart/inkognito.desktop"
        ok "Starts with your desktop session on http://localhost:$port"
      fi ;;
    linux:off)
      if [ -f "$SD_UNIT" ]; then systemctl --user disable --now inkognito.service >/dev/null 2>&1 || true; rm -f "$SD_UNIT"; systemctl --user daemon-reload 2>/dev/null || true; fi
      rm -f "$HOME/.config/autostart/inkognito.desktop"; ok "Autostart off" ;;
    win:*) die "On Windows use install.ps1 -Autostart for login startup." ;;
    *) die "Use --autostart on or --autostart off." ;;
  esac
}

status() {
  local port; port="$(cat "$PORTF" 2>/dev/null || echo "$DEFAULT_PORT")"
  printf ' App        %s\n' "$( [ -f "$APP" ] && echo "v$(app_version "$APP") in $DATA" || echo "not installed")"
  printf ' Address    http://localhost:%s\n' "$port"
  printf ' Server     %s\n' "$(is_ours "$port" && echo running || echo stopped)"
  printf ' Autostart  %s\n' "$(autostart_state)"
  printf ' Launcher   v%s\n' "$LAUNCHER_VERSION"
}

uninstall() {
  [ "$(autostart_state)" = "on" ] && autostart off
  stop_server >/dev/null 2>&1 || true
  rm -f "$BIN" "$HOME/.local/share/applications/inkognito.desktop"
  rm -rf "$DATA"
  ok "Inkognito removed from this machine."
  msg "Drafts live in your browser. To erase them too, open Inkognito first and use Erase all local data."
}

banner() {
  printf '\n  %sInkognito%s %s· privacy-first LinkedIn formatter · your drafts stay on this machine%s\n\n' "$B" "$CL" "$DIM" "$CL"
}

# --- Proxmox: act as a helper script ----------------------------------------
run_proxmox() {
  local helper
  if [ -n "$SCRIPT_DIR" ] && [ -f "$SCRIPT_DIR/proxmox/inkognito-lxc.sh" ]; then helper="$SCRIPT_DIR/proxmox/inkognito-lxc.sh"
  else helper="$(mktemp)"; download "$RAW/proxmox/inkognito-lxc.sh" "$helper"; fi
  exec bash "$helper"
}

if [ "$ACTION" = "launch" ] && { [ "$MODE" = "proxmox" ] || { [ "$MODE" = "auto" ] && is_proxmox; }; }; then
  is_proxmox || die "--proxmox needs a Proxmox VE host."
  ok "Proxmox VE $(pveversion | cut -d/ -f2) detected"
  choice="1"
  if [ "$MODE" = "auto" ] && [ -t 0 ]; then
    printf '   1) Create an Alpine LXC container for it %s(recommended)%s\n   2) Run it locally on this host instead\n' "$DIM" "$CL"
    read -r -p "   Choose [1]: " choice; choice="${choice:-1}"
  fi
  if [ "$choice" = "1" ]; then run_proxmox; fi
fi

# --- local machine -----------------------------------------------------------
case "$ACTION" in
  serve)
    PORT="$(pick_port)"; serve_fg "$PORT" || die "Needs Python 3.7+ or Ruby with WEBrick to serve. Or open $APP directly." ;;
  stop) stop_server ;;
  status) status ;;
  uninstall) uninstall ;;
  autostart) [ -f "$APP" ] || { install_self; fetch_app; }; autostart "$AUTOSTART_ARG" ;;
  update)
    banner; install_self; fetch_app
    if is_ours "$(cat "$PORTF" 2>/dev/null || echo "$DEFAULT_PORT")"; then msg "Reload the page in your browser to use the new version."; fi ;;
  launch)
    [ -f "$APP" ] || { banner; install_self; fetch_app; }
    [ -f "$SELF" ] || install_self
    PORT="$(pick_port)"
    if [ "$BIND" = "0.0.0.0" ]; then warn "--lan: anyone on your network can open Inkognito (drafts still stay in each person's browser)."; fi
    start_bg "$PORT"
    open_browser "http://localhost:$PORT"
    if [ ! -f "$DATA/.welcomed" ]; then
      next="inkognito"
      if [ "$OS" = "win" ]; then next="bash \"$SELF\""
      else case ":$PATH:" in *":$HOME/.local/bin:"*) ;; *) next="$SELF   (or add ~/.local/bin to your PATH)";; esac; fi
      printf '\n  %sOpen%s       http://localhost:%s\n' "$GN" "$CL" "$PORT"
      printf '  %sNext time%s  %s\n' "$DIM" "$CL" "$next"
      printf '  %sStop%s       inkognito --stop\n  %sAt login%s   inkognito --autostart on\n\n' "$DIM" "$CL" "$DIM" "$CL"
      touch "$DATA/.welcomed"
    fi ;;
esac
