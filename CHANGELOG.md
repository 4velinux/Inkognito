# Changelog

## v1.1.0 · 2026-09-24

- README rewritten to lead with the core value: Inkognito is one self-contained HTML file, download it and open it, nothing to install or host. Self-hosting (Proxmox, Docker, always-on services) is now a clearly optional section, not the headline.
- Added a real, dated privacy comparison against competing LinkedIn formatters, based on live network/cookie/tracker checks of their marketing pages.
- Added creator credit ("Created by Pedro Avelino", with LinkedIn and GitHub links) to the app header and footer, and to the top of the README.
- Moved the keyboard shortcuts button from the top header into the editor toolbar, right next to the WYSIWYG controls, for more visibility while writing.

## v1.0.0 · 2026-09-24

First public release.

- Unicode formatting: bold, italic, bold italic, 22 letter styles, five line styles, lists, emoji, symbols, dividers, case, find and replace
- Paste from Google Docs, Word and Markdown with formatting kept
- Desktop and mobile LinkedIn feed previews with measured "…more" fold, light and dark feeds, image and author preview
- Character meter for six LinkedIn fields with sweet-spot band and fold markers
- Voice check with highlights and one-click fixes
- Privacy check for emails, phones, card numbers, Thai IDs, IBANs, API keys, internal addresses and tracking links
- Privacy lock (CSP), live network-request counter, erase all local data
- Drafts, templates, JSON export and import
- One-line installers for Windows (PowerShell), macOS and Linux: localhost server, browser launch, Start menu or `inkognito` command, autostart, verified updates, uninstall
- Smart host detection, no menus: desktops get a per-user localhost install; headless Linux, Windows Server and SSH sessions get an always-on network service; Proxmox VE gets an Alpine LXC (updated in place on re-run); TrueNAS, Unraid, Synology and QNAP get the Docker container
- Multi-arch container image on ghcr.io for every release
- Proxmox VE Alpine LXC installer with verified nightly updates and rollback
- Docker image (Alpine + lighttpd, non-root, read-only)
