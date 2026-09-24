#!/bin/sh
# inkognito-update: fetch the newest Inkognito and publish it, keeping backups.
# Runs inside the Alpine container (busybox sh), also works on any Linux with wget or curl.
#
#   inkognito-update                 install the latest release (or main, see CHANNEL)
#   inkognito-update --file X.html   publish a local file you copied in
#   inkognito-update --rollback      go back to the previous version
#   inkognito-update --status        show what is live
#
# Settings live in /etc/inkognito.conf:
#   REPO=4velinux/Inkognito   use your fork here
#   CHANNEL=release           release = tagged versions (checksum-verified), main = every commit
set -eu

REPO="4velinux/Inkognito"
CHANNEL="release"
WEB="/var/www/inkognito"
BACKUPS="/var/backups/inkognito"
KEEP=10
# shellcheck disable=SC1091
[ -f /etc/inkognito.conf ] && . /etc/inkognito.conf

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT INT TERM
mkdir -p "$WEB" "$BACKUPS"

say() { printf '%s\n' "$*"; }
fetch() { # url dest
  if command -v curl >/dev/null 2>&1; then curl -fsSL --max-time 60 -o "$2" "$1"
  else wget -q -T 60 -O "$2" "$1"; fi
}
sha() { sha256sum "$1" | cut -d' ' -f1; }
version_of() { sed -n "s/.*var VERSION='\([^']*\)'.*/\1/p" "$1" | head -n1; }

check_file() { # refuse anything that is not a privacy-locked Inkognito build
  grep -q '<title>Inkognito</title>' "$1" || { say "Refusing: not an Inkognito file."; exit 1; }
  grep -q "connect-src 'none'" "$1" || { say "Refusing: the privacy lock (CSP) is missing from this build."; exit 1; }
}

publish() { # file source-label
  check_file "$1"
  if [ -f "$WEB/index.html" ] && [ "$(sha "$1")" = "$(sha "$WEB/index.html")" ]; then
    say "Already up to date (v$(version_of "$1"))."; return 0
  fi
  if [ -f "$WEB/index.html" ]; then cp "$WEB/index.html" "$BACKUPS/index-$(date +%Y%m%d-%H%M%S).html"; fi
  cp "$1" "$WEB/index.html.new" && chmod 644 "$WEB/index.html.new" && mv "$WEB/index.html.new" "$WEB/index.html"
  printf 'v%s  %s  %s  %s\n' "$(version_of "$WEB/index.html")" "$(date -u +%Y-%m-%dT%H:%MZ)" "$(sha "$WEB/index.html" | cut -c1-12)" "$2" > "$WEB/version.txt"
  # shellcheck disable=SC2012
  ls -1t "$BACKUPS"/index-*.html 2>/dev/null | tail -n +$((KEEP + 1)) | while read -r f; do rm -f "$f"; done
  say "Published v$(version_of "$WEB/index.html") from $2."
}

case "${1:-}" in
  --status)
    cat "$WEB/version.txt" 2>/dev/null || say "Nothing published yet."; exit 0 ;;
  --rollback)
    # shellcheck disable=SC2012
    prev="$(ls -1t "$BACKUPS"/index-*.html 2>/dev/null | head -n1 || true)"
    [ -n "$prev" ] || { say "No backup to roll back to."; exit 1; }
    cp "$prev" "$WEB/index.html" && chmod 644 "$WEB/index.html" && rm -f "$prev"
    printf 'v%s  %s  rollback\n' "$(version_of "$WEB/index.html")" "$(date -u +%Y-%m-%dT%H:%MZ)" > "$WEB/version.txt"
    say "Rolled back to v$(version_of "$WEB/index.html")."; exit 0 ;;
  --file)
    [ -f "${2:-}" ] || { say "Usage: inkognito-update --file /path/inkognito.html"; exit 1; }
    publish "$2" "local file"; exit 0 ;;
  ""|--update) ;;
  *) say "Unknown option: $1"; exit 1 ;;
esac

if [ "$CHANNEL" = "release" ]; then
  base="https://github.com/$REPO/releases/latest/download"
  if fetch "$base/inkognito.html" "$TMP/new.html" 2>/dev/null; then
    if fetch "$base/inkognito.html.sha256" "$TMP/new.sha256" 2>/dev/null; then
      [ "$(cut -d' ' -f1 "$TMP/new.sha256")" = "$(sha "$TMP/new.html")" ] || { say "Checksum mismatch, not publishing."; exit 1; }
    else
      say "Release has no checksum file, not publishing."; exit 1
    fi
    publish "$TMP/new.html" "release of $REPO"; exit 0
  fi
  say "No release found for $REPO yet, using the main branch."
fi
fetch "https://raw.githubusercontent.com/$REPO/main/inkognito.html" "$TMP/new.html" || { say "Download failed. Is the container online?"; exit 1; }
publish "$TMP/new.html" "main branch of $REPO"
