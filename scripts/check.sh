#!/usr/bin/env bash
# Privacy guard for Inkognito. Fails if the app could talk to any server.
# Run locally before a PR:  bash scripts/check.sh
set -euo pipefail
cd "$(dirname "$0")/.."
F=inkognito.html
fail=0
bad() { printf '✗ %s\n' "$*"; fail=1; }
good() { printf '✓ %s\n' "$*"; }

[ -f "$F" ] || { echo "missing $F"; exit 1; }

grep -q '<meta charset="utf-8">' "$F" && good "charset declared" || bad "missing <meta charset=\"utf-8\">"
grep -q "http-equiv=\"Content-Security-Policy\"" "$F" && good "CSP meta present" || bad "CSP meta tag missing"
for d in "default-src 'none'" "connect-src 'none'" "form-action 'none'" "base-uri 'none'"; do
  grep -q "$d" "$F" && good "CSP has $d" || bad "CSP lost: $d"
done

# No external resources of any kind (links to open in a new tab are allowed)
if grep -nE '<(script|link|img|iframe|source|video|audio|embed|object|track)[^>]*(src|href|srcset)="(https?:)?//' "$F"; then bad "external resource tag found (above)"; else good "no external scripts, styles, fonts or images"; fi
if grep -nE '@import|url\(["'"'"']?(https?:)?//' "$F"; then bad "external CSS import or url() found (above)"; else good "no external CSS"; fi

# No network APIs in the code
if grep -nE '\bfetch\(|XMLHttpRequest|sendBeacon|new WebSocket|EventSource|importScripts|serviceWorker|RTCPeerConnection' "$F"; then bad "network API used (above)"; else good "no network APIs in the code"; fi

# Version string present (used by the updater and releases)
grep -qE "var VERSION='[0-9]+\.[0-9]+\.[0-9]+'" "$F" && good "version $(sed -n "s/.*var VERSION='\([^']*\)'.*/\1/p" "$F" | head -n1)" || bad "var VERSION='x.y.z' not found"

# JavaScript syntax
if command -v node >/dev/null; then
  tmp="$(mktemp --suffix=.js)"
  awk '/<script>/{f=1;next}/<\/script>/{f=0}f' "$F" > "$tmp"
  node --check "$tmp" && good "JavaScript parses" || bad "JavaScript syntax error"
  rm -f "$tmp"
fi

# Shell scripts
if command -v shellcheck >/dev/null; then
  shellcheck -S warning proxmox/*.sh scripts/*.sh && good "shellcheck clean" || bad "shellcheck warnings"
fi

exit $fail
