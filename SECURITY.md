# Security and privacy policy

## Reporting

If you find a way for Inkognito to send data anywhere, run code from a pasted draft, or break the installer's integrity checks, please report it privately through
[GitHub security advisories](https://github.com/4velinux/inkognito/security/advisories/new) rather than a public issue. You should get a reply within a week.

## What Inkognito protects

- **No outbound traffic.** A Content Security Policy (`default-src 'none'; connect-src 'none'`) is set in the page and again as a server header in the Proxmox and Docker builds.
- **No third-party code.** No CDN, font, analytics or tracking script is loaded.
- **Local storage only.** Drafts and settings stay in the browser's `localStorage` for the address you opened. "Erase all local data" removes them.
- **Verified updates.** The container updater downloads tagged releases from GitHub, checks the published SHA-256 checksum, and refuses any build without the privacy lock. The last 10 versions are kept for rollback.

## What it does not protect

- Anyone with access to your browser profile can read drafts in `localStorage`.
- The self-hosted server uses plain HTTP on your LAN. Put it behind a VPN or a reverse proxy with TLS if you need more.
- Once you paste a post into LinkedIn, LinkedIn's own privacy terms apply.
