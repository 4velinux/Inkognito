#!/usr/bin/env bash
# ---------------------------------------------------------------------------
#  Inkognito · smart installer and launcher for Proxmox VE, Linux and macOS
#  A locally launched, privacy-first LinkedIn formatter for self-hosting.
#
#    bash -c "$(curl -fsSL https://raw.githubusercontent.com/4velinux/Inkognito/main/install.sh)"
#
#  It looks at the machine and picks the right setup on its own:
#    Proxmox VE host      → creates a tiny Alpine LXC for your whole network
#    NAS (TrueNAS, Unraid,
#         Synology, QNAP) → runs the Docker container, always on
#    Headless Linux       → always-on service for your network
#    (server, Pi, VM, LXC)   (systemd, OpenRC or cron, whichever exists)
#    Desktop (macOS, Linux
#    with a screen, WSL)  → this computer only, opens your browser
#  Windows: use install.ps1 (Git Bash and WSL also work with this script).
#
#  Override the guess: --desktop · --server · --docker · --proxmox
#  After install, the `inkognito` command:
#    inkognito                 start if needed and open the browser
#    inkognito --stop | --update | --status | --uninstall
#    inkognito --autostart on|off
#  Options: --port N · --lan · --local-only · --no-browser · --yes · --serve
#
#  Privacy: launching never touches the network. Only install and --update
#  download the app, from GitHub releases, verified by SHA-256.
# ---------------------------------------------------------------------------
set -Eeuo pipefail

LAUNCHER_VERSION="1.2.0"
REPO="${INKOGNITO_REPO:-4velinux/Inkognito}"
REF="${INKOGNITO_REF:-main}"
RAW="https://raw.githubusercontent.com/${REPO}/${REF}"
REL="https://github.com/${REPO}/releases/latest/download"
IMAGE="${INKOGNITO_IMAGE:-ghcr.io/$(printf '%s' "$REPO" | tr '[:upper:]' '[:lower:]'):latest}"
DEFAULT_PORT=8765

ACTION="launch"; FORCE_PROFILE="${INKOGNITO_PROFILE:-}"; OPEN=1; BIND_ARG=""; PORT_ARG="${INKOGNITO_PORT:-}"; AUTOSTART_ARG=""; YES="${INKOGNITO_YES:-}"

usage() { sed -n '2,29p' "${BASH_SOURCE[0]:-/dev/null}" 2>/dev/null | sed 's/^# \{0,1\}//' || true; echo "See https://github.com/${REPO}"; }
while [ $# -gt 0 ]; do
  case "$1" in
    --stop) ACTION="stop" ;;
    --update) ACTION="update" ;;
    --status) ACTION="status" ;;
    --uninstall) ACTION="uninstall" ;;
    --serve) ACTION="serve" ;;
    --detect) ACTION="detect" ;;
    --autostart) ACTION="autostart"; AUTOSTART_ARG="${2:-on}"; shift ;;
    --port) PORT_ARG="${2:?--port needs a number}"; shift ;;
    --lan) BIND_ARG="0.0.0.0" ;;
    --local-only) BIND_ARG="127.0.0.1" ;;
    --no-browser) OPEN=0 ;;
    --yes|-y) YES=1 ;;
    --desktop|--local) FORCE_PROFILE="desktop" ;;
    --server) FORCE_PROFILE="server" ;;
    --docker) FORCE_PROFILE="docker" ;;
    --proxmox) FORCE_PROFILE="proxmox" ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1 (try --help)"; exit 1 ;;
  esac
  shift
done

if [ -t 1 ]; then BL=$'\e[38;5;69m'; GN=$'\e[32m'; RD=$'\e[31m'; YW=$'\e[33m'; DIM=$'\e[2m'; B=$'\e[1m'; CL=$'\e[0m'; else BL=""; GN=""; RD=""; YW=""; DIM=""; B=""; CL=""; fi
msg()  { printf ' %s›%s %s\n' "$BL" "$CL" "$*"; }
ok()   { printf ' %s✓%s %s\n' "$GN" "$CL" "$*"; }
warn() { printf ' %s!%s %s\n' "$YW" "$CL" "$*" >&2; }
die()  { printf ' %s✗%s %s\n' "$RD" "$CL" "$*" >&2; exit 1; }

# ===========================================================================
#  Host detection
# ===========================================================================
OS="other"; WSL=0
case "$(uname -s 2>/dev/null || echo unknown)" in
  Darwin) OS="mac" ;;
  Linux) OS="linux"; grep -qi microsoft /proc/version 2>/dev/null && WSL=1 ;;
  MINGW*|MSYS*|CYGWIN*) OS="win" ;;
esac
IS_ROOT=0; [ "$(id -u 2>/dev/null || echo 1)" = "0" ] && IS_ROOT=1

is_proxmox() { command -v pveversion >/dev/null 2>&1 && command -v pct >/dev/null 2>&1; }

NAS=""
detect_nas() {
  if [ -f /etc/version ] && grep -qi truenas /etc/version 2>/dev/null; then NAS="TrueNAS SCALE"
  elif command -v midclt >/dev/null 2>&1; then NAS="TrueNAS SCALE"
  elif [ -f /etc/unraid-version ]; then NAS="Unraid"
  elif [ -f /etc/synoinfo.conf ] || [ -d /usr/syno ]; then NAS="Synology DSM"
  elif [ -f /etc/config/qpkg.conf ] || [ -d /share/CACHEDEV1_DATA ]; then NAS="QNAP"
  fi
  [ -n "$NAS" ]
}

os_name() {
  case "$OS" in
    mac) printf 'macOS %s' "$(sw_vers -productVersion 2>/dev/null || true)" ;;
    win) printf 'Windows (%s)' "$(uname -s | cut -d_ -f1)" ;;
    linux)
      local n=""
      # shellcheck disable=SC1091
      [ -r /etc/os-release ] && n="$(. /etc/os-release && printf '%s' "${PRETTY_NAME:-$NAME}")"
      [ -f /etc/unraid-version ] && n="Unraid $(sed -n 's/version="\(.*\)"/\1/p' /etc/unraid-version)"
      is_proxmox && n="Proxmox VE $(pveversion 2>/dev/null | cut -d/ -f2)"
      printf '%s' "${n:-Linux}"
      [ "$WSL" = 1 ] && printf ' on WSL'
      ;;
    *) uname -s ;;
  esac
}

virt_name() {
  local v=""
  if command -v systemd-detect-virt >/dev/null 2>&1; then v="$(systemd-detect-virt 2>/dev/null || true)"; fi
  if [ -z "$v" ] || [ "$v" = "none" ]; then
    if [ -f /.dockerenv ]; then v="docker"; elif [ -f /run/.containerenv ]; then v="podman"
    elif grep -qa 'container=lxc' /proc/1/environ 2>/dev/null; then v="lxc"; fi
  fi
  [ "$v" = "none" ] && v=""
  printf '%s' "$v"
}

has_display() {
  [ "$OS" = "mac" ] && return 0
  [ "$OS" = "win" ] && return 0
  [ "$WSL" = 1 ] && return 0
  [ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ] && return 0
  # a graphical session exists on this machine even if this shell came in over SSH
  if [ -z "${SSH_CONNECTION:-}" ] && command -v loginctl >/dev/null 2>&1; then
    loginctl list-sessions --no-legend 2>/dev/null | awk '{print $1}' | while read -r s; do
      loginctl show-session "$s" -p Type --value 2>/dev/null
    done | grep -qE '^(x11|wayland)$' && return 0
  fi
  return 1
}

init_system() {
  if [ -d /run/systemd/system ] && command -v systemctl >/dev/null 2>&1; then echo systemd
  elif command -v rc-service >/dev/null 2>&1 && [ -d /etc/init.d ]; then echo openrc
  elif command -v crontab >/dev/null 2>&1; then echo cron
  else echo none; fi
}

docker_cmd() {
  if command -v docker >/dev/null 2>&1; then
    if docker info >/dev/null 2>&1; then echo "docker"; return 0; fi
    if [ "$IS_ROOT" = 0 ] && command -v sudo >/dev/null 2>&1 && sudo -n docker info >/dev/null 2>&1; then echo "sudo docker"; return 0; fi
  fi
  return 1
}

REASON=""; PROFILE=""
detect_profile() { # sets PROFILE and REASON
  if [ -n "$FORCE_PROFILE" ]; then PROFILE="$FORCE_PROFILE"; REASON="chosen with --$FORCE_PROFILE"; return; fi
  if is_proxmox; then PROFILE="proxmox"; REASON="Proxmox VE host"; return; fi
  if detect_nas; then
    if docker_cmd >/dev/null; then PROFILE="docker"; REASON="$NAS with Docker"; return; fi
    PROFILE="server"; REASON="$NAS, Docker not usable by this user"; return
  fi
  case "$(virt_name)" in
    docker|podman) PROFILE="server"; REASON="running inside a $(virt_name) container"; return ;;
  esac
  if has_display; then PROFILE="desktop"; REASON="desktop with a screen"; return; fi
  PROFILE="server"
  if [ -n "${SSH_CONNECTION:-}" ]; then REASON="you are connected over SSH, so it will serve your network"
  else REASON="no screen attached, so it will serve your network"; fi
}

lan_ip() {
  local ip=""
  if [ "$OS" = "mac" ]; then ip="$(ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null || true)"
  else
    ip="$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src"){print $(i+1); exit}}' || true)"
    [ -n "$ip" ] || ip="$(hostname -I 2>/dev/null | awk '{print $1}' || true)"
  fi
  printf '%s' "${ip:-this-machine}"
}

# ===========================================================================
#  Paths (desktop and non-root: your user folder; root server: /opt)
# ===========================================================================
user_data() {
  case "$OS" in
    mac) printf '%s' "$HOME/Library/Application Support/Inkognito" ;;
    win) printf '%s' "${LOCALAPPDATA:-$HOME/AppData/Local}/Inkognito" ;;
    *)   printf '%s' "${XDG_DATA_HOME:-$HOME/.local/share}/inkognito" ;;
  esac
}
set_paths() { # dir
  DATA="$1"; WWW="$DATA/www"; APP="$WWW/index.html"; SELF="$DATA/inkognito.sh"
  PIDF="$DATA/server.pid"; LOG="$DATA/server.log"; PORTF="$DATA/port"; PROFF="$DATA/profile"; BINDF="$DATA/bind"
  if [ "$DATA" = "/opt/inkognito" ]; then BIN="/usr/local/bin/inkognito"; else BIN="$HOME/.local/bin/inkognito"; fi
}
# Pick an existing install first, so later commands find it
if [ -n "${INKOGNITO_HOME:-}" ]; then set_paths "$INKOGNITO_HOME"
elif [ -f "$(user_data)/www/index.html" ]; then set_paths "$(user_data)"
elif [ -f /opt/inkognito/www/index.html ]; then set_paths /opt/inkognito
else set_paths "$(user_data)"; fi

SCRIPT_DIR=""
if [ -n "${BASH_SOURCE[0]:-}" ] && [ -f "${BASH_SOURCE[0]}" ]; then SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; fi

# ===========================================================================
#  Helpers
# ===========================================================================
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
saved() { cat "$1" 2>/dev/null || true; }
pick_port() {
  local p="${PORT_ARG:-}"
  [ -z "$p" ] && p="$(saved "$PORTF")"
  p="${p:-$DEFAULT_PORT}"
  if port_open "$p" && ! is_ours "$p"; then
    if [ -n "$PORT_ARG" ]; then die "Port $p is used by another program. Pick another with --port."; fi
    local q=$((p + 1)); while port_open "$q"; do q=$((q + 1)); done
    warn "Port $p is busy, using $q. Drafts are saved per address, so drafts from :$p will not show on :$q."
    p="$q"
  fi
  echo "$p"
}
countdown() { # message
  [ -n "$YES" ] && return 0
  [ -t 0 ] || return 0
  printf '\n %s%s%s\n' "$DIM" "$1" "$CL"
  printf ' Starting in 5 s. Enter starts now, Ctrl+C cancels. '
  read -r -t 5 _ || true
  printf '\n'
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
    mv "$tmp/app.html" "$APP"
    ok "Installed Inkognito v$(app_version "$APP")"
  fi
  printf 'v%s\n' "$(app_version "$APP")" > "$WWW/version.txt"
  chmod 755 "$DATA" "$WWW"; chmod 644 "$APP" "$WWW/version.txt"
  rm -rf "$tmp"
}

install_self() {
  mkdir -p "$DATA" "$(dirname "$BIN")"
  if [ -n "$SCRIPT_DIR" ] && [ "${BASH_SOURCE[0]}" != "$SELF" ]; then cp "${BASH_SOURCE[0]}" "$SELF.new"
  elif [ ! -f "$SELF" ] || [ "$ACTION" = "update" ]; then download "$RAW/install.sh" "$SELF.new"
  fi
  if [ -f "$SELF.new" ]; then mv "$SELF.new" "$SELF"; chmod 755 "$SELF"; fi
  if [ "$OS" != "win" ]; then ln -sf "$SELF" "$BIN" 2>/dev/null || true; fi
  if [ "$OS" = "linux" ] && [ "$WSL" = 0 ] && [ "$(saved "$PROFF")" = "desktop" ]; then
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

# ===========================================================================
#  Local web server (Python 3 or Ruby, whichever the machine already has)
# ===========================================================================
find_python() {
  local c v
  for c in python3 python; do
    command -v "$c" >/dev/null 2>&1 || continue
    # macOS ships a stub python3 that opens an installer dialog: skip it unless developer tools exist
    if [ "$OS" = "mac" ] && [ "$(command -v "$c")" = "/usr/bin/python3" ] && ! xcode-select -p >/dev/null 2>&1; then continue; fi
    v="$("$c" -c 'import sys;print(sys.version_info>=(3,7))' 2>/dev/null || true)"
    [ "$v" = "True" ] && { command -v "$c"; return 0; }
  done
  return 1
}
has_ruby() { command -v ruby >/dev/null 2>&1 && ruby -e 'require "webrick"' 2>/dev/null; }
can_serve() { find_python >/dev/null || has_ruby; }

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
ALLOWED = ("/", "/index.html", "/version.txt")
class H(http.server.SimpleHTTPRequestHandler):
    def __init__(s, *a, **k): super().__init__(*a, directory=root, **k)
    def end_headers(s):
        for k, v in HEADERS.items(): s.send_header(k, v)
        super().end_headers()
    def log_message(s, *a): pass
    def do_GET(s):
        if s.path.split("?")[0] not in ALLOWED: return s.send_error(404)
        return super().do_GET()
    def do_HEAD(s):
        if s.path.split("?")[0] not in ALLOWED: return s.send_error(404)
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

effective_bind() {
  if [ -n "$BIND_ARG" ]; then echo "$BIND_ARG"; return; fi
  local b; b="$(saved "$BINDF")"; echo "${b:-127.0.0.1}"
}

serve_fg() { # port; replaces this process so the PID is the server
  local port="$1" py bind; bind="$(effective_bind)"
  [ -f "$APP" ] || die "App not installed yet. Run without --serve first."
  if py="$(find_python)"; then exec "$py" -c "$PY_SERVER" "$port" "$bind" "$WWW"; fi
  if has_ruby; then exec ruby -run -e httpd -- "$WWW" -p "$port" -b "$bind"; fi
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
      else msg "Open $url in a browser."; fi ;;
    *) msg "Open $url in a browser." ;;
  esac
}

running_pid() { [ -f "$PIDF" ] && kill -0 "$(cat "$PIDF")" 2>/dev/null && cat "$PIDF"; }

start_bg() { # port
  local port="$1" lan=""
  if is_ours "$port"; then ok "Already running on port $port"; return 0; fi
  [ "$(effective_bind)" = "0.0.0.0" ] && lan="--lan"
  # shellcheck disable=SC2086
  nohup bash "$SELF" --serve --port "$port" $lan > "$LOG" 2>&1 &
  echo $! > "$PIDF"
  wait_up "$port" || { cat "$LOG" >&2; die "The server did not start (log above)."; }
  ok "Serving on port $port ${DIM}(pid $(cat "$PIDF"))${CL}"
}
wait_up() { for _ in $(seq 1 60); do port_open "$1" && return 0; sleep 0.1; done; return 1; }

# ===========================================================================
#  Autostart: systemd (system or user), OpenRC, launchd, cron
# ===========================================================================
LA_LABEL="io.github.inkognito"
LA_PLIST="$HOME/Library/LaunchAgents/$LA_LABEL.plist"
SD_SYS="/etc/systemd/system/inkognito.service"
SD_USER="$HOME/.config/systemd/user/inkognito.service"
RC_SCRIPT="/etc/init.d/inkognito"
XDG_AUTO="$HOME/.config/autostart/inkognito.desktop"

autostart_state() {
  if [ -f "$SD_SYS" ]; then echo "on (systemd service)"
  elif [ -f "$RC_SCRIPT" ]; then echo "on (OpenRC service)"
  elif [ -f "$SD_USER" ]; then echo "on (systemd user service)"
  elif [ -f "$LA_PLIST" ]; then echo "on (LaunchAgent)"
  elif [ -f "$XDG_AUTO" ]; then echo "on (desktop session)"
  elif command -v crontab >/dev/null 2>&1 && crontab -l 2>/dev/null | grep -q 'inkognito\.sh"* --serve'; then echo "on (cron @reboot)"
  else echo "off"; fi
}

autostart_on() {
  local port lan="" how=""; port="$(saved "$PORTF")"; port="${port:-$DEFAULT_PORT}"
  [ "$(effective_bind)" = "0.0.0.0" ] && lan=" --lan"
  stop_server quiet
  case "$OS" in
    mac)
      mkdir -p "$(dirname "$LA_PLIST")"
      cat > "$LA_PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>$LA_LABEL</string>
  <key>ProgramArguments</key><array><string>/bin/bash</string><string>$SELF</string><string>--serve</string><string>--port</string><string>$port</string>$( [ -n "$lan" ] && echo "<string>--lan</string>")</array>
  <key>EnvironmentVariables</key><dict><key>INKOGNITO_HOME</key><string>$DATA</string></dict>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>StandardErrorPath</key><string>$LOG</string>
</dict></plist>
EOF
      launchctl bootout "gui/$(id -u)/$LA_LABEL" >/dev/null 2>&1 || true
      launchctl bootstrap "gui/$(id -u)" "$LA_PLIST" 2>/dev/null || launchctl load -w "$LA_PLIST"
      how="LaunchAgent" ;;
    linux)
      case "$(init_system):$IS_ROOT" in
        systemd:1)
          cat > "$SD_SYS" <<EOF
[Unit]
Description=Inkognito, privacy-first LinkedIn formatter (port $port)
After=network-online.target
Wants=network-online.target

[Service]
Environment=INKOGNITO_HOME=$DATA
ExecStart=/usr/bin/env bash $SELF --serve --port $port$lan
Restart=on-failure
DynamicUser=yes
NoNewPrivileges=yes
ProtectSystem=strict
ProtectHome=yes
PrivateTmp=yes
PrivateDevices=yes
ReadOnlyPaths=$DATA
CapabilityBoundingSet=
RestrictAddressFamilies=AF_INET AF_INET6 AF_UNIX
MemoryMax=64M

[Install]
WantedBy=multi-user.target
EOF
          systemctl daemon-reload && systemctl enable --now inkognito.service >/dev/null 2>&1
          how="systemd service, sandboxed with a throwaway user" ;;
        openrc:1)
          cat > "$RC_SCRIPT" <<EOF
#!/sbin/openrc-run
description="Inkognito, privacy-first LinkedIn formatter"
command="/bin/bash"
command_args="$SELF --serve --port $port$lan"
command_user="nobody:nobody"
command_background=true
pidfile="/run/inkognito.pid"
export INKOGNITO_HOME="$DATA"
depend() { need net; }
EOF
          chmod 755 "$RC_SCRIPT"; rc-update add inkognito default >/dev/null; rc-service inkognito restart >/dev/null
          how="OpenRC service" ;;
        systemd:0)
          if systemctl --user show-environment >/dev/null 2>&1; then
            mkdir -p "$(dirname "$SD_USER")"
            cat > "$SD_USER" <<EOF
[Unit]
Description=Inkognito, privacy-first LinkedIn formatter (port $port)

[Service]
Environment=INKOGNITO_HOME=$DATA
ExecStart=/usr/bin/env bash "$SELF" --serve --port $port$lan
Restart=on-failure
NoNewPrivileges=yes
PrivateTmp=yes

[Install]
WantedBy=default.target
EOF
            systemctl --user daemon-reload && systemctl --user enable --now inkognito.service >/dev/null
            how="systemd user service"
            if [ "$(saved "$PROFF")" = "server" ]; then
              if loginctl enable-linger "$(id -un)" >/dev/null 2>&1; then how="$how, runs without anyone logged in"
              else warn "Could not enable lingering, so it stops when you log out. Fix with: sudo loginctl enable-linger $(id -un)"; fi
            fi
          elif [ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]; then
            mkdir -p "$(dirname "$XDG_AUTO")"
            printf '[Desktop Entry]\nType=Application\nName=Inkognito server\nExec="%s" --no-browser\nX-GNOME-Autostart-enabled=true\n' "$SELF" > "$XDG_AUTO"
            how="desktop session autostart"
          else cron_on "$port" "$lan"; how="cron @reboot"; fi ;;
        *) cron_on "$port" "$lan"; how="$(command -v crontab >/dev/null 2>&1 && echo "cron @reboot" || echo "background process")" ;;
      esac ;;
    *) die "On Windows use install.ps1 -Autostart on." ;;
  esac
  wait_up "$port" || start_bg "$port"
  if [ "$how" = "background process" ]; then ok "Running now (no way to start it automatically on this system)"
  else ok "Starts automatically ($how)"; fi
}
cron_on() { # port lan
  if ! command -v crontab >/dev/null 2>&1; then
    warn "No systemd, OpenRC or cron here, so it runs until this machine or container restarts."
    start_bg "$1"; return 0
  fi
  { crontab -l 2>/dev/null | grep -v 'inkognito\.sh"* --serve' || true
    echo "@reboot INKOGNITO_HOME=\"$DATA\" nohup bash \"$SELF\" --serve --port $1$2 >/dev/null 2>&1"; } | crontab -
  start_bg "$1"
}
autostart_off() {
  if [ -f "$SD_SYS" ]; then systemctl disable --now inkognito.service >/dev/null 2>&1 || true; rm -f "$SD_SYS"; systemctl daemon-reload || true; fi
  if [ -f "$RC_SCRIPT" ]; then rc-service inkognito stop >/dev/null 2>&1 || true; rc-update del inkognito >/dev/null 2>&1 || true; rm -f "$RC_SCRIPT"; fi
  if [ -f "$SD_USER" ]; then systemctl --user disable --now inkognito.service >/dev/null 2>&1 || true; rm -f "$SD_USER"; systemctl --user daemon-reload 2>/dev/null || true; fi
  if [ -f "$LA_PLIST" ]; then launchctl bootout "gui/$(id -u)/$LA_LABEL" >/dev/null 2>&1 || launchctl unload -w "$LA_PLIST" >/dev/null 2>&1 || true; rm -f "$LA_PLIST"; fi
  rm -f "$XDG_AUTO"
  if command -v crontab >/dev/null 2>&1 && crontab -l 2>/dev/null | grep -q 'inkognito\.sh"* --serve'; then crontab -l 2>/dev/null | grep -v 'inkognito\.sh"* --serve' | crontab -; fi
}

stop_server() { # [quiet]
  local pid; pid="$(running_pid || true)"
  if [ -n "$pid" ]; then pkill -P "$pid" 2>/dev/null || true; kill "$pid" 2>/dev/null || true; rm -f "$PIDF"; [ -z "${1:-}" ] && ok "Stopped"; return 0; fi
  if [ "$(saved "$PROFF")" = "docker" ] && D="$(docker_cmd)"; then $D stop inkognito >/dev/null 2>&1 && { [ -z "${1:-}" ] && ok "Container stopped"; }; return 0; fi
  if [ -z "${1:-}" ]; then
    case "$(autostart_state)" in
      off) msg "Not running." ;;
      *) warn "It runs as a service ($(autostart_state)). Use: inkognito --autostart off" ;;
    esac
  fi
}

# ===========================================================================
#  Docker profile (NAS appliances, or --docker)
# ===========================================================================
docker_up() { # port
  local D port="$1" img="$IMAGE"
  D="$(docker_cmd)" || die "Docker is not available to this user."
  msg "Getting the container image"
  if ! $D pull -q "$img" >/dev/null 2>&1; then
    warn "Could not pull $img, building it from the source instead."
    img="inkognito:local"
    $D build -q -t "$img" "https://github.com/${REPO}.git#${REF}" >/dev/null || die "Docker build failed."
  fi
  $D rm -f inkognito >/dev/null 2>&1 || true
  $D run -d --name inkognito --restart unless-stopped -p "${port}:8080" \
    --read-only --tmpfs /tmp --cap-drop ALL --security-opt no-new-privileges:true \
    --label io.github.inkognito=1 "$img" >/dev/null
  wait_up "$port" || die "The container did not come up. Check: $D logs inkognito"
  mkdir -p "$DATA"; echo docker > "$PROFF"; echo "$port" > "$PORTF"
  ok "Container running, restarts on its own after reboots"
}

# ===========================================================================
#  Commands
# ===========================================================================
banner() { printf '\n  %sInkognito%s %s· privacy-first LinkedIn formatter · your drafts stay on your machine%s\n\n' "$B" "$CL" "$DIM" "$CL"; }

status() {
  local port prof; port="$(saved "$PORTF")"; port="${port:-$DEFAULT_PORT}"; prof="$(saved "$PROFF")"
  printf ' Setup      %s\n' "${prof:-not installed}"
  printf ' App        %s\n' "$( [ -f "$APP" ] && echo "v$(app_version "$APP") in $DATA" || { [ "$prof" = docker ] && echo "in the inkognito container" || echo "not installed"; })"
  if [ "$(effective_bind)" = "0.0.0.0" ] || [ "$prof" = docker ]; then printf ' Address    http://%s:%s  (and http://localhost:%s)\n' "$(lan_ip)" "$port" "$port"
  else printf ' Address    http://localhost:%s  (this machine only)\n' "$port"; fi
  printf ' Server     %s\n' "$(is_ours "$port" && echo running || echo stopped)"
  printf ' Autostart  %s\n' "$( [ "$prof" = docker ] && echo "on (Docker restart policy)" || autostart_state)"
  printf ' Launcher   v%s\n' "$LAUNCHER_VERSION"
}

uninstall() {
  local D
  if [ "$(saved "$PROFF")" = "docker" ] && D="$(docker_cmd)"; then $D rm -f inkognito >/dev/null 2>&1 || true; fi
  autostart_off
  stop_server quiet
  rm -f "$BIN" "$HOME/.local/share/applications/inkognito.desktop"
  rm -rf "$DATA"
  ok "Inkognito removed from this machine."
  msg "Drafts live in your browser. To erase them too, open Inkognito first and use Erase all local data."
}

run_proxmox() {
  local helper
  if [ -n "$SCRIPT_DIR" ] && [ -f "$SCRIPT_DIR/proxmox/inkognito-lxc.sh" ]; then helper="$SCRIPT_DIR/proxmox/inkognito-lxc.sh"
  else helper="$(mktemp)"; download "$RAW/proxmox/inkognito-lxc.sh" "$helper"; fi
  INKOGNITO_REPO="$REPO" INKOGNITO_REF="$REF" INKOGNITO_YES="$YES" exec bash "$helper"
}

describe() { # profile
  case "$1" in
    proxmox) echo "Create a small Alpine LXC container that serves Inkognito to your whole network" ;;
    docker)  echo "Run the Inkognito container on port $2, always on, for your whole network" ;;
    server)  echo "Install an always-on service on port $2 for your whole network" ;;
    desktop) echo "Install for you only, on http://localhost:$2, and open your browser" ;;
  esac
}

install_or_launch() {
  local prof port
  prof="$(saved "$PROFF")"
  if [ -z "$prof" ] || [ -n "$FORCE_PROFILE" ]; then
    detect_profile; prof="$PROFILE"
    banner
    ok "Detected $(os_name)$( v="$(virt_name)"; [ -n "$v" ] && echo " ($v)") · $REASON"
  fi

  case "$prof" in
    proxmox)
      is_proxmox || die "--proxmox needs a Proxmox VE host."
      msg "Plan: $(describe proxmox)"
      msg "Want it on the host itself instead? Run again with --desktop or --server."
      run_proxmox ;;

    docker)
      port="$(pick_port)"
      msg "Plan: $(describe docker "$port")"
      countdown "Other devices on your network will be able to open it."
      docker_up "$port"
      finish docker "$port" ;;

    server)
      if [ "$IS_ROOT" = 1 ] && [ -z "${INKOGNITO_HOME:-}" ] && [ ! -f "$APP" ]; then set_paths /opt/inkognito; fi
      [ -n "$BIND_ARG" ] || BIND_ARG="0.0.0.0"
      port="$(pick_port)"
      if [ ! -f "$APP" ]; then
        can_serve || die "This machine has no Python 3 or Ruby to serve the app. Install python3, or use --docker."
        msg "Plan: $(describe server "$port")"
        [ "$BIND_ARG" = "0.0.0.0" ] || msg "Listening on this machine only (--local-only)."
        countdown "Installs to $DATA and starts with the machine. Other devices on your network can open it (drafts stay in each person's browser)."
        mkdir -p "$DATA"; echo server > "$PROFF"; echo "$BIND_ARG" > "$BINDF"; echo "$port" > "$PORTF"
        install_self; fetch_app
        autostart_on
      else
        echo "$port" > "$PORTF"
        is_ours "$port" && ok "Running on port $port" || { case "$(autostart_state)" in off) start_bg "$port" ;; *) warn "Service not answering yet. Check: inkognito --status" ;; esac; }
      fi
      finish server "$port" ;;

    desktop|*)
      if [ ! -f "$APP" ]; then
        port="$(pick_port)"
        msg "Plan: $(describe desktop "$port")"
        mkdir -p "$DATA"; echo desktop > "$PROFF"; echo "${BIND_ARG:-127.0.0.1}" > "$BINDF"
        install_self; fetch_app
      fi
      [ -f "$SELF" ] || install_self
      port="$(pick_port)"
      if ! can_serve; then
        warn "No Python 3 or Ruby here to run a local server."
        msg "Opening the app straight from disk instead (it works the same)."
        OPEN=1; open_browser "file://$APP"; exit 0
      fi
      [ "$(effective_bind)" = "0.0.0.0" ] && warn "--lan: other devices on your network can open Inkognito."
      start_bg "$port"; echo "$port" > "$PORTF"
      open_browser "http://localhost:$port"
      finish desktop "$port" ;;
  esac
}

finish() { # profile port
  [ -f "$DATA/.welcomed" ] && return 0
  mkdir -p "$DATA"; touch "$DATA/.welcomed"
  local cmd="inkognito"
  if [ "$OS" = "win" ]; then cmd="bash \"$SELF\""
  elif [ "$BIN" = "$HOME/.local/bin/inkognito" ]; then case ":$PATH:" in *":$HOME/.local/bin:"*) ;; *) cmd="$SELF";; esac; fi
  printf '\n'
  if [ "$1" = desktop ]; then printf '  %sOpen%s       http://localhost:%s\n' "$GN" "$CL" "$2"
  else printf '  %sOpen%s       http://%s:%s  %sfrom any device on your network%s\n' "$GN" "$CL" "$(lan_ip)" "$2" "$DIM" "$CL"; fi
  printf '  %sCommands%s   %s --status · --update · --stop · --uninstall\n' "$DIM" "$CL" "$cmd"
  [ "$1" = desktop ] && printf '  %sAt login%s   %s --autostart on\n' "$DIM" "$CL" "$cmd"
  [ "$1" != desktop ] && printf '  %sAway from home?%s Use Tailscale or WireGuard, never an open router port.\n' "$DIM" "$CL"
  printf '\n'
}

case "$ACTION" in
  detect)
    detect_profile; printf 'host=%s\nvirt=%s\nprofile=%s\nreason=%s\ninit=%s\nroot=%s\n' "$(os_name)" "$(virt_name)" "$PROFILE" "$REASON" "$(init_system)" "$IS_ROOT" ;;
  serve)
    PORT="$(pick_port)"; serve_fg "$PORT" || die "Needs Python 3.7+ or Ruby with WEBrick to serve. Or open $APP directly." ;;
  stop) stop_server ;;
  status) status ;;
  uninstall) uninstall ;;
  autostart)
    [ -f "$APP" ] || die "Install first: run inkognito without options."
    case "$AUTOSTART_ARG" in on) autostart_on ;; off) autostart_off; ok "Autostart off" ;; *) die "Use --autostart on or --autostart off." ;; esac ;;
  update)
    if [ "$(saved "$PROFF")" = "docker" ]; then banner; docker_up "$(saved "$PORTF")"; exit 0; fi
    banner; install_self; fetch_app
    msg "Reload the page in your browser to use the new version." ;;
  launch) install_or_launch ;;
esac
