<div align="center">

# Inkognito

**The LinkedIn formatter that never leaves your browser.**
One HTML file. No install, no account, no server, no data leaving your machine, ever.

**by [Pedro Avelino](https://www.linkedin.com/in/pedroavelino)** · [![LinkedIn](https://img.shields.io/badge/LinkedIn-Pedro%20Avelino-0A66C2?logo=linkedin&logoColor=white)](https://www.linkedin.com/in/pedroavelino) [![GitHub](https://img.shields.io/badge/GitHub-4velinux%2FInkognito-181717?logo=github&logoColor=white)](https://github.com/4velinux/Inkognito)

[![Privacy check](https://github.com/4velinux/Inkognito/actions/workflows/ci.yml/badge.svg)](https://github.com/4velinux/Inkognito/actions/workflows/ci.yml)
[![Latest release](https://img.shields.io/github/v/release/4velinux/Inkognito?label=release&color=3F51B5)](https://github.com/4velinux/Inkognito/releases/latest)
[![Network requests](https://img.shields.io/badge/network%20requests-zero-2E7D32)](#the-privacy-comparison)
[![License: MIT](https://img.shields.io/badge/license-MIT-673AB7)](LICENSE)

<img src="docs/screenshot.png" alt="Inkognito editor with toolbar, character meter, LinkedIn feed preview and voice check" width="900">

### ⬇️ [**Download inkognito.html**](https://github.com/4velinux/Inkognito/releases/latest/download/inkognito.html) → double-click it → start writing.

That's the whole install process.

</div>

---

## The idea

Every LinkedIn formatter you've used is somebody else's server. You paste an unpublished post, a client's name, a half-formed opinion about your CEO, and it travels through their infrastructure, next to their analytics and ad scripts, before you've even hit publish.

Inkognito skips the server. It's a single self-contained HTML file: the editor, the feed preview, the character counter and the privacy scanner are all inside it. Open it from your Downloads folder, from a USB stick, from an offline laptop on a plane. There is nothing to sign up for and nothing to trust, because there is nothing to talk to.

A strict Content Security Policy makes this a guarantee, not a promise: `connect-src 'none'` blocks every outbound connection at the browser level, so even a bug in the code couldn't leak your text. The footer shows a live counter of network requests, and it never leaves zero.

## The privacy comparison

I checked. On 24 September 2026, I opened the marketing pages of the most-used LinkedIn writing tools in a fresh, cookie-free browser tab and watched what left before I typed a single word.

| Tool | Trackers on page load | Cookies set | What I saw |
|---|---|---|---|
| **Taplio** | Google Analytics (2 measurement IDs), Meta Pixel, Microsoft Clarity (session replay) | 12 | Fires GA and Meta beacons and starts a Clarity session-replay recorder before you've done anything |
| **AuthoredUp** | Google Tag Manager, MailerLite, an affiliate-tracking script, reCAPTCHA | 0 until consent | 16 third-party scripts queued behind the cookie banner, including an affiliate tracker |
| **Typefully** | None found | 0 | Marketing page loaded clean: 74 requests, all first-party. Worth calling out, since it's the exception here |
| **Inkognito** | **None. Ever.** | **0** | `connect-src 'none'` makes outbound requests impossible, not just absent. Verified automatically on every commit |

**Method:** fresh browser profile, no ad blocker, network requests and `document.cookie` read via the browser's own dev tools before any interaction with the page. This checks what a marketing site does on load, not what happens inside the paid product after signup, and sites change without notice, so treat this as a snapshot, not a permanent verdict. Full methodology and caveats: [`docs/privacy-comparison.md`](docs/privacy-comparison.md). Re-run it yourself; that's the point.

The gap isn't really about any one tool being sloppy. It's that a hosted formatter has to send your draft somewhere to format it, and once your text has left your machine, every script sitting on that page gets a chance to see it too.

## Features

**Formatting**
- Bold, italic and bold italic that toggle and combine. Press Bold with nothing selected and everything you type comes out bold.
- 22 Unicode letter styles with live previews: serif, monospace, script, gothic, double-struck, small caps, circled, squared, superscript, upside-down and more. Risky ones are flagged because they render as boxes on older phones.
- Underline, double underline, strikethrough, slash and overline, stackable on any style.
- List markers (• → ✓ ▸ ◆ ✅ 👉 1. 1️⃣), emoji and symbol pickers, dividers, case changes, find and replace that matches styled letters.
- Paste from Google Docs or Word and bold, italic, strikethrough and lists survive. Paste Markdown and it converts automatically.

**Preview**
- Desktop feed (555 px) and mobile app (390 px) side by side, in light or dark mode.
- The "…more" fold is measured on your actual text, showing exactly how many characters show before it.
- Attach an image, set the author name and headline, preview a profile headline.

**Checks**
- Character meter for posts, comments, headlines, About, invite notes and article titles, with a 1,300–2,000 character sweet spot and fold positions marked.
- Voice check: em dashes, AI-slop words and stock phrases, long paragraphs, a hook cut off on mobile, a missing closing question, styled hashtags that won't link, plain @names that won't tag.
- **Privacy check:** emails, phone numbers, card numbers (Luhn), Thai national IDs (checksum), IBANs, API keys and tokens, private IPs and internal hostnames, and tracking parameters in links, with a one-click strip.

**Drafts**
- Unlimited drafts saved in your browser only, templates, export and import as JSON, one-click erase of all local data.

## Get it

Download **[`inkognito.html`](https://github.com/4velinux/Inkognito/releases/latest/download/inkognito.html)** from the latest release. Open it:

- **Double-click it**, or drag it into any browser tab.
- Keep it anywhere: Downloads, Desktop, a USB stick, a synced folder. It works the same offline as online.
- Bookmark the local file (`file:///...`) so it's one click next time.

Drafts save to that browser via `localStorage`, tied to the file's exact location. Move the file, and use Drafts → Export/Import to bring your drafts with it.

Want the source instead of a release build? [`git clone`](https://github.com/4velinux/Inkognito) the repo and open `inkognito.html` directly, no build step required.

## Optional: run it as a local service

Everything above is the whole product for almost everyone. If you specifically want Inkognito always-on at a fixed address, reachable from your phone on the same network, or auto-updating in the background, an optional installer can set that up. It self-detects whether it's landed on a desktop, a headless server, a Proxmox host or a NAS, and picks a sane setup without a menu.

<details>
<summary><b>Show the self-hosting options</b> (Proxmox, Docker, Windows/macOS/Linux services)</summary>

### One-line install

**Windows** (PowerShell):
```powershell
irm https://raw.githubusercontent.com/4velinux/Inkognito/main/install.ps1 | iex
```

**macOS, Linux, Proxmox VE, NAS** (Terminal or SSH):
```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/4velinux/Inkognito/main/install.sh)"
```

| It detects | So it sets up | Reachable at |
|---|---|---|
| **Windows 10/11, macOS, Linux with a screen, WSL** | A per-user install, Start menu entry or `inkognito` command, opens your browser. No admin rights. | `http://localhost:8765`, this computer only |
| **Headless Linux** (server, Raspberry Pi, VM, LXC) or an **SSH session** | An always-on service: sandboxed systemd service as a throwaway user when root, a user service or cron without root, OpenRC on Alpine | `http://<machine-ip>:8765` on your network |
| **Windows Server, Server Core, or SSH into Windows** | An always-on startup task as the low-privilege LOCAL SERVICE account, plus a firewall rule for private networks only (needs admin) | `http://<machine-ip>:8765` on your network |
| **Proxmox VE host** | A helper script that creates a 64 MB Alpine LXC. Run it again later and it updates that container instead of making a second one | `http://<container-ip>` |
| **TrueNAS SCALE, Unraid, Synology, QNAP** | The hardened Docker container (read-only, no capabilities) with a restart policy | `http://<nas-ip>:8765` |

Every choice is printed with its reason before anything changes, and any setup that opens your network waits 5 seconds so you can cancel. If the guess is wrong: `--desktop`, `--server`, `--docker`, `--proxmox` (Windows: `-Desktop`, `-Server`). Add `--yes` to skip the wait in scripts, `--detect` to see the plan without installing.

### Everyday use

| | macOS / Linux | Windows |
|---|---|---|
| Open | `inkognito` | Start menu → Inkognito |
| Stop | `inkognito --stop` | `... inkognito.ps1 -Stop` |
| Start at login | `inkognito --autostart on` | `... inkognito.ps1 -Autostart on` |
| Update | `inkognito --update` | `... inkognito.ps1 -Update` |
| Status | `inkognito --status` | `... inkognito.ps1 -Status` |
| Remove | `inkognito --uninstall` | `... inkognito.ps1 -Uninstall` |

Options: `--port 9000` / `-Port 9000`, `--no-browser` / `-NoBrowser`, `--lan` to open a desktop install to your network, `--local-only` to keep a server install local.

**Desktop installs listen on `127.0.0.1` only.** Server installs listen on your network by design. Launching never touches the internet; only the first install and `--update` fetch anything, from a GitHub release, with a SHA-256 checksum verified before use.

### Proxmox VE, in detail

```bash
bash -c "$(wget -qLO - https://raw.githubusercontent.com/4velinux/Inkognito/main/proxmox/inkognito-lxc.sh)"
```

Creates an unprivileged Alpine Linux container (1 core, 64 MB RAM, 1 GB disk) with lighttpd and the app, checking for new releases nightly.

```bash
CTID=150 CT_NET=192.168.1.50/24 CT_GW=192.168.1.1 \
  bash -c "$(wget -qLO - https://raw.githubusercontent.com/4velinux/Inkognito/main/proxmox/inkognito-lxc.sh)"
```

| Variable | Default | What it does |
|---|---|---|
| `CTID` | next free ID | Container ID |
| `CT_HOSTNAME` | `inkognito` | Hostname |
| `CT_CORES` / `CT_RAM` / `CT_DISK` | `1` / `64` MB / `1` GB | Resources |
| `CT_BRIDGE` / `CT_VLAN` | `vmbr0` / none | Network bridge and VLAN tag |
| `CT_NET` / `CT_GW` | `dhcp` | Static address in CIDR form, plus gateway |
| `CT_STORAGE` / `TPL_STORAGE` | auto | Storage for the container and the template |
| `INKOGNITO_REPO` | `4velinux/Inkognito` | Install from your fork |
| `CHANNEL` | `release` | `release` = tagged, checksum-verified versions; `main` = every commit |
| `AUTO_UPDATE` | `yes` | Nightly update check |
| `INKOGNITO_YES` | unset | `1` skips the confirmation prompt |

```bash
pct exec <CTID> -- inkognito-update              # update now
pct exec <CTID> -- inkognito-update --rollback   # previous version
pct exec <CTID> -- inkognito-update --status     # what is live
```

The updater refuses any file whose checksum doesn't match the release, and any build that has lost its privacy lock.

### Docker

```bash
docker compose up -d        # http://localhost:8080
```

Alpine plus lighttpd, non-root, read-only filesystem, no capabilities.

</details>

## Good to know

- **Drafts are stored per address.** The file on disk, `http://localhost:8765`, `http://192.168.1.50` and `http://localhost:8080` each keep separate drafts. Use Drafts → Export all / Import to move them.
- **Copy works everywhere.** On plain `http://` and `file://` addresses the browser clipboard API is often disabled; Inkognito falls back to the classic copy command automatically.
- **About styled letters:** they're Unicode look-alikes, the technique every formatter uses. Screen readers may spell them out, and LinkedIn search doesn't index them, so style a few key phrases, not whole posts. The checker warns you past 25% styled.
- **Want it reachable away from home?** Use Tailscale or WireGuard rather than opening a port to the internet.

## Contributing

Pull requests are welcome, forks are the point. Read [CONTRIBUTING.md](CONTRIBUTING.md). The one rule that's never negotiable: **no network requests**, ever. `scripts/check.sh` enforces it on every commit.

## License

[MIT](LICENSE). Built in Thailand by [Pedro Avelino](https://www.linkedin.com/in/pedroavelino) ([GitHub](https://github.com/4velinux)).
