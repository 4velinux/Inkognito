#!/usr/bin/env bash
# ---------------------------------------------------------------------------
#  Inkognito · Proxmox VE installer
#  Creates a tiny Alpine Linux LXC that serves the privacy-first LinkedIn
#  formatter on your network. About 1 GB disk and ~10 MB RAM in use.
#
#  Run on the Proxmox host shell:
#    bash -c "$(wget -qLO - https://raw.githubusercontent.com/4velinux/inkognito/main/proxmox/inkognito-lxc.sh)"
#
#  Every setting has a default; override with environment variables, e.g.
#    CTID=150 CT_NET=192.168.1.50/24 CT_GW=192.168.1.1 bash inkognito-lxc.sh
#
#  CTID            container ID                 (next free ID)
#  CT_HOSTNAME     hostname                     (inkognito)
#  CT_CORES        CPU cores                    (1)
#  CT_RAM          memory in MB                 (64)
#  CT_DISK         disk in GB                   (1)
#  CT_BRIDGE       network bridge               (vmbr0)
#  CT_NET          dhcp or CIDR address         (dhcp)
#  CT_GW           gateway when CT_NET is CIDR
#  CT_VLAN         VLAN tag                     (none)
#  CT_STORAGE      storage for the container    (auto)
#  TPL_STORAGE     storage for the template     (auto)
#  INKOGNITO_REPO  GitHub owner/repo to install from, use your fork here  (4velinux/inkognito)
#  INKOGNITO_REF   branch used for the setup files                         (main)
#  CHANNEL         release (checksum-verified tags) or main (every commit)  (release)
#  AUTO_UPDATE     yes = check for new versions every night              (yes)
#  INKOGNITO_YES   1 = skip the confirmation prompt
# ---------------------------------------------------------------------------
set -Eeuo pipefail

REPO="${INKOGNITO_REPO:-4velinux/inkognito}"
REF="${INKOGNITO_REF:-main}"
RAW="https://raw.githubusercontent.com/${REPO}/${REF}"
CT_HOSTNAME="${CT_HOSTNAME:-inkognito}"
CT_CORES="${CT_CORES:-1}"
CT_RAM="${CT_RAM:-64}"
CT_DISK="${CT_DISK:-1}"
CT_BRIDGE="${CT_BRIDGE:-vmbr0}"
CT_NET="${CT_NET:-dhcp}"
CT_GW="${CT_GW:-}"
CT_VLAN="${CT_VLAN:-}"
CHANNEL="${CHANNEL:-release}"
AUTO_UPDATE="${AUTO_UPDATE:-yes}"

if [ -t 1 ]; then BL=$'\e[38;5;69m'; GN=$'\e[32m'; RD=$'\e[31m'; YW=$'\e[33m'; DIM=$'\e[2m'; CL=$'\e[0m'; else BL=""; GN=""; RD=""; YW=""; DIM=""; CL=""; fi
msg()  { printf ' %s›%s %s\n' "$BL" "$CL" "$*"; }
ok()   { printf ' %s✓%s %s\n' "$GN" "$CL" "$*"; }
warn() { printf ' %s!%s %s\n' "$YW" "$CL" "$*"; }
die()  { printf ' %s✗%s %s\n' "$RD" "$CL" "$*" >&2; exit 1; }

CREATED=""
REPORTED=""
on_error() {
  local line=$1
  [ -n "$REPORTED" ] && return; REPORTED=1
  printf '\n %s✗ Failed at line %s.%s\n' "$RD" "$line" "$CL" >&2
  if [ -n "$CREATED" ]; then
    printf '   Container %s was created. Remove it with:  pct stop %s; pct destroy %s\n' "$CREATED" "$CREATED" "$CREATED" >&2
  fi
}
trap 'on_error $LINENO' ERR

cat <<'BANNER'

   ██ ███  ██ ██  ██  ██████   ██████  ███  ██ ██ ████████  ██████
   ██ ████ ██ ██ ██  ██    ██ ██       ████ ██ ██    ██    ██    ██
   ██ ██ ████ ████   ██    ██ ██   ███ ██ ████ ██    ██    ██    ██
   ██ ██  ███ ██ ██  ██    ██ ██    ██ ██  ███ ██    ██    ██    ██
   ██ ██   ██ ██  ██  ██████   ██████  ██   ██ ██    ██     ██████
        privacy-first LinkedIn formatter · Alpine LXC for Proxmox VE

BANNER

# --- preflight -------------------------------------------------------------
[ "$(id -u)" -eq 0 ] || die "Run this as root on the Proxmox host."
command -v pct >/dev/null && command -v pveam >/dev/null || die "This must run on a Proxmox VE host (pct and pveam not found)."
PVE_VER="$(pveversion | grep -oE 'pve-manager/[0-9]+' | cut -d/ -f2 || echo 0)"
[ "${PVE_VER:-0}" -ge 8 ] || warn "Tested on Proxmox VE 8 and 9. You have $(pveversion | cut -d/ -f2)."

CTID="${CTID:-$(pvesh get /cluster/nextid)}"
if pct status "$CTID" >/dev/null 2>&1 || qm status "$CTID" >/dev/null 2>&1; then die "ID $CTID is already in use. Set CTID=<free id>."; fi

pick_storage() { # content type
  pvesm status -content "$1" 2>/dev/null | awk 'NR>1 && $3=="active" {print $1}' | head -n1
}
TPL_STORAGE="${TPL_STORAGE:-$(pick_storage vztmpl)}"
CT_STORAGE="${CT_STORAGE:-$(pick_storage rootdir)}"
[ -n "$TPL_STORAGE" ] || die "No active storage allows container templates (content: vztmpl)."
[ -n "$CT_STORAGE" ] || die "No active storage allows container disks (content: rootdir)."

NET="name=eth0,bridge=${CT_BRIDGE}"
if [ "$CT_NET" = "dhcp" ]; then NET+=",ip=dhcp"; else
  NET+=",ip=${CT_NET}"; [ -n "$CT_GW" ] && NET+=",gw=${CT_GW}"; fi
[ -n "$CT_VLAN" ] && NET+=",tag=${CT_VLAN}"

msg "Container ID     ${CTID}"
msg "Hostname         ${CT_HOSTNAME}"
msg "Resources        ${CT_CORES} core · ${CT_RAM} MB RAM · ${CT_DISK} GB disk on ${CT_STORAGE}"
msg "Network          ${CT_BRIDGE} · ${CT_NET}${CT_VLAN:+ · VLAN $CT_VLAN}"
msg "App source       ${REPO} (${CHANNEL}), nightly updates: ${AUTO_UPDATE}"
if [ -z "${INKOGNITO_YES:-}" ] && [ -t 0 ]; then
  read -r -p " Create it? [Y/n] " ans
  case "${ans:-y}" in [yY]*) ;; *) die "Cancelled." ;; esac
fi

# --- template --------------------------------------------------------------
msg "Looking for the newest Alpine template"
pveam update >/dev/null 2>&1 || warn "Could not refresh the template list, using the cached one."
TEMPLATE="$(pveam available --section system | awk '{print $2}' | grep -E '^alpine-3\.[0-9]+-default_' | sort -V | tail -n1 || true)"
[ -n "$TEMPLATE" ] || die "No Alpine template found in 'pveam available'."
if ! pveam list "$TPL_STORAGE" | grep -q "$TEMPLATE"; then
  msg "Downloading $TEMPLATE"
  pveam download "$TPL_STORAGE" "$TEMPLATE" >/dev/null
fi
ok "Template $TEMPLATE"

# --- container -------------------------------------------------------------
msg "Creating container $CTID"
pct create "$CTID" "${TPL_STORAGE}:vztmpl/${TEMPLATE}" \
  --hostname "$CT_HOSTNAME" --ostype alpine \
  --cores "$CT_CORES" --memory "$CT_RAM" --swap "$CT_RAM" \
  --rootfs "${CT_STORAGE}:${CT_DISK}" \
  --net0 "$NET" \
  --unprivileged 1 --features nesting=1 --onboot 1 \
  --tags "inkognito;privacy" \
  --description "<div align='center'><h2>Inkognito</h2><p>Privacy-first LinkedIn formatter.</p><p><a href='https://github.com/${REPO}'>github.com/${REPO}</a></p><p>Update: <code>inkognito-update</code> · Roll back: <code>inkognito-update --rollback</code></p></div>" \
  >/dev/null
CREATED="$CTID"
pct start "$CTID"
ok "Container started"

msg "Waiting for network"
IP=""
for _ in $(seq 1 60); do
  IP="$(pct exec "$CTID" -- ip -4 -o addr show dev eth0 2>/dev/null | awk '{print $4}' | cut -d/ -f1 | head -n1 || true)"
  if [ -n "$IP" ] && pct exec "$CTID" -- nslookup dl-cdn.alpinelinux.org >/dev/null 2>&1; then break; fi
  sleep 2
done
[ -n "$IP" ] || die "The container got no IPv4 address. Check the bridge and DHCP."
ok "Online at $IP"

# --- provision -------------------------------------------------------------
HERE=""
if [ -n "${BASH_SOURCE[0]:-}" ] && [ -f "$(dirname "${BASH_SOURCE[0]}")/lighttpd.conf" ]; then HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; fi

PROV="$(mktemp)"
cat > "$PROV" <<EOF
#!/bin/sh
set -eu
apk update -q
apk add -q --no-cache lighttpd ca-certificates
mkdir -p /var/www/inkognito /var/backups/inkognito /var/log/lighttpd /usr/local/bin
chown lighttpd:lighttpd /var/log/lighttpd
if [ ! -f /tmp/lighttpd.conf ]; then wget -q -O /tmp/lighttpd.conf "${RAW}/proxmox/lighttpd.conf"; fi
if [ ! -f /tmp/inkognito-update ]; then wget -q -O /tmp/inkognito-update "${RAW}/proxmox/inkognito-update.sh"; fi
install -m 644 /tmp/lighttpd.conf /etc/lighttpd/lighttpd.conf
install -m 755 /tmp/inkognito-update /usr/local/bin/inkognito-update
printf 'REPO=%s\nCHANNEL=%s\n' "${REPO}" "${CHANNEL}" > /etc/inkognito.conf
if [ -f /tmp/inkognito.html ]; then /usr/local/bin/inkognito-update --file /tmp/inkognito.html; else /usr/local/bin/inkognito-update; fi
rc-update add lighttpd default >/dev/null
rc-service lighttpd restart >/dev/null
if [ "${AUTO_UPDATE}" = "yes" ]; then
  grep -q inkognito-update /etc/crontabs/root 2>/dev/null || echo "17 3 * * * /usr/local/bin/inkognito-update >/dev/null 2>&1" >> /etc/crontabs/root
  rc-update add crond default >/dev/null
  rc-service crond restart >/dev/null
fi
rm -f /tmp/lighttpd.conf /tmp/inkognito-update /tmp/inkognito.html
EOF

if [ -n "$HERE" ]; then
  msg "Using setup files from $HERE"
  pct push "$CTID" "$HERE/lighttpd.conf" /tmp/lighttpd.conf
  pct push "$CTID" "$HERE/inkognito-update.sh" /tmp/inkognito-update
  if [ -f "$HERE/../inkognito.html" ] && [ -n "${USE_LOCAL_HTML:-}" ]; then pct push "$CTID" "$HERE/../inkognito.html" /tmp/inkognito.html; fi
fi
pct push "$CTID" "$PROV" /root/provision.sh
rm -f "$PROV"
msg "Installing the web server and the app"
pct exec "$CTID" -- sh /root/provision.sh
pct exec "$CTID" -- rm -f /root/provision.sh
ok "Inkognito is installed"

cat <<EOF

 ${GN}Open:${CL}  http://${IP}

 ${DIM}Update now:${CL}     pct exec ${CTID} -- inkognito-update
 ${DIM}Roll back:${CL}      pct exec ${CTID} -- inkognito-update --rollback
 ${DIM}What is live:${CL}   http://${IP}/version.txt
 ${DIM}Remove:${CL}         pct stop ${CTID} && pct destroy ${CTID}

 Tip: reserve ${IP} for this container in your router so the address never changes.

EOF
