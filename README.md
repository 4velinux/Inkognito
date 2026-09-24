<div align="center">

# 🕶️ Inkognito

### The LinkedIn formatter that never leaves your browser.

**One HTML file. No install. No account. No server. Your words stay on your machine.**

**by [Pedro Avelino](https://www.linkedin.com/in/pedroavelino)**

[![LinkedIn](https://img.shields.io/badge/LinkedIn-Pedro%20Avelino-0A66C2?logo=linkedin&logoColor=white)](https://www.linkedin.com/in/pedroavelino)
[![GitHub](https://img.shields.io/badge/GitHub-4velinux%2FInkognito-181717?logo=github&logoColor=white)](https://github.com/4velinux/Inkognito)
[![Privacy check](https://github.com/4velinux/Inkognito/actions/workflows/ci.yml/badge.svg)](https://github.com/4velinux/Inkognito/actions/workflows/ci.yml)
[![Latest release](https://img.shields.io/github/v/release/4velinux/Inkognito?label=release&color=3F51B5)](https://github.com/4velinux/Inkognito/releases/latest)
[![Network requests](https://img.shields.io/badge/network%20requests-0-2E7D32)](#-the-receipts)
[![License: MIT](https://img.shields.io/badge/license-MIT-673AB7)](LICENSE)

<img src="docs/screenshot.png" alt="Inkognito editor with toolbar, character meter, LinkedIn feed preview and voice check" width="900">

<br>

### ⬇️ [**Download inkognito.html**](https://github.com/4velinux/Inkognito/releases/latest/download/inkognito.html) → double-click it → start writing.

**That's it. That's the whole install guide.**

Just want to try it first? [**inkognito.a-eye.cloud**](https://inkognito.a-eye.cloud) runs the exact same file, hosted. Same CSP, same zero network requests once it loads, just one click instead of a download.

</div>

---

## 🕵️ Why this exists

Every LinkedIn formatter you've used lives on somebody else's server. You paste an unpublished post, a client's name, a half-formed opinion about your boss, and it travels through their infrastructure, next to their analytics and ad scripts, before you've even hit Publish.

Inkognito skips the server entirely. 

→ It's one self-contained file. Open it from Downloads, a USB stick, an offline laptop.
→ There's nothing to sign up for and nothing to trust, because there's nothing to talk to.
→ A strict browser policy blocks every outbound connection. Not a promise, a lock.

The footer shows a live counter of network requests. It stays at zero. Forever.

---

## 🔒 The receipts

Talk is cheap, so I checked. On 24 September 2026, I opened the most-used LinkedIn writing tools in a clean browser and watched exactly what left the page, before and after typing a test phrase.

| Tool | Requests | Outside domains | Cookies | What's on the page |
|---|:---:|:---:|:---:|---|
| Taplio | 67 | 27 | 12 | Google Analytics + Ads, Meta Pixel, Microsoft Clarity session recording, RudderStack. No cookie banner. |
| ConnectSafely | 73 | 25 | 10 | Meta/X/Reddit/Google Ads pixels, Clarity, Crisp chat. Ad cookies set *before* the banner was answered. |
| WaveGen | 40 | 7 | 3 | Google Analytics, LinkedIn Insight Tag, PostHog. Fired a session-recording call right after I typed. |
| AuthoredUp | 25 | 8 | 0 | Google, MailerLite, YouTube. No editor to type into, it funnels you to sign-up. |
| Typefully | 84 | 2 | 0 | Google Fonts, Sentry. Mostly its own traffic. |
| Poper | 53 | 2 | 0 | Google Fonts, Cloudflare analytics. |
| **Inkognito** | **1** | **0** | **0** | **The page itself. Everything else is blocked at the browser level.** |

✅ Full methodology, caveats and the "why" behind the one request Inkognito does make: **[`docs/privacy-comparison.md`](docs/privacy-comparison.md)**.

> Re-run this check yourself. That's the entire point of a claim like this: don't take my word for it, verify it.

---

## ✨ What's inside

**🖋️ Formatting**
- Bold, italic, bold-italic, that toggle and combine
- 22 Unicode letter styles (script, gothic, double-struck, small caps, and more)
- Underline, strikethrough, overline, stackable on any style
- Emoji, symbols, dividers, case changes, find & replace
- Paste from Google Docs, Word or Markdown, formatting survives

**👀 Preview**
- Desktop (555px) and mobile (390px) feed, side by side, light or dark
- The "…more" fold, measured on your actual text, not a guess

**✅ Checks**
- Character meter for posts, comments, headlines, About, invite notes
- Voice check: em dashes, AI-slop words, missing hooks, dead hashtags
- **Privacy check:** emails, phone numbers, card numbers, API keys and tokens, tracking links, with one-click strip

**💾 Drafts**
- Saved in your browser only, unlimited, export/import as JSON, one-click erase

---

## 🚀 Get it

1. Download **[`inkognito.html`](https://github.com/4velinux/Inkognito/releases/latest/download/inkognito.html)**
2. Double-click it, or drag it into any browser tab
3. Write

Keep it in Downloads, on a USB stick, wherever. It works the same offline as online. Bookmark the local file for one-click access next time.

Prefer the source? `git clone` the repo, open `inkognito.html`. No build step, ever.

---

## 🛠️ Optional: run it as a service

Everything above is the whole product for almost everyone. Only need this if you want Inkognito always-on at a fixed address, reachable from your phone, or auto-updating.

<details>
<summary><b>Show self-hosting options</b> (Proxmox, Docker, Windows/macOS/Linux services)</summary>

### One-line install

**Windows** (PowerShell):
```powershell
irm https://raw.githubusercontent.com/4velinux/Inkognito/main/install.ps1 | iex
```

**macOS, Linux, Proxmox VE, NAS** (Terminal or SSH):
```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/4velinux/Inkognito/main/install.sh)"
```

It auto-detects your machine and picks the setup, no menus involved:

| Detected | Sets up | Reachable at |
|---|---|---|
| Windows/macOS/Linux desktop | Per-user install, opens your browser, no admin needed | `localhost:8765` only |
| Headless Linux / SSH session | Sandboxed always-on service | `<machine-ip>:8765` |
| Windows Server / Server Core | Low-privilege startup task + scoped firewall rule | `<machine-ip>:8765` |
| Proxmox VE host | 64 MB Alpine LXC (re-run to update it) | `<container-ip>` |
| TrueNAS, Unraid, Synology, QNAP | Hardened Docker container | `<nas-ip>:8765` |

Every choice prints its reason first, and anything network-facing waits 5 seconds so you can cancel. Force it with `--desktop` / `--server` / `--docker` / `--proxmox` (Windows: `-Desktop` / `-Server`), skip the wait with `--yes`, or see the plan without installing with `--detect`.

### Everyday use

| | macOS / Linux | Windows |
|---|---|---|
| Open | `inkognito` | Start menu → Inkognito |
| Stop | `inkognito --stop` | `... inkognito.ps1 -Stop` |
| Autostart | `inkognito --autostart on` | `... inkognito.ps1 -Autostart on` |
| Update | `inkognito --update` | `... inkognito.ps1 -Update` |
| Status | `inkognito --status` | `... inkognito.ps1 -Status` |
| Remove | `inkognito --uninstall` | `... inkognito.ps1 -Uninstall` |

Desktop installs listen on `127.0.0.1` only. Server installs listen on your network, by design. Only the first install and `--update` fetch anything, from a GitHub release, checksum-verified.

### Proxmox VE, in detail

```bash
bash -c "$(wget -qLO - https://raw.githubusercontent.com/4velinux/Inkognito/main/proxmox/inkognito-lxc.sh)"
```

Creates an unprivileged Alpine container (1 core, 64 MB RAM, 1 GB disk), checks for updates nightly.

```bash
CTID=150 CT_NET=192.168.1.50/24 CT_GW=192.168.1.1 \
  bash -c "$(wget -qLO - https://raw.githubusercontent.com/4velinux/Inkognito/main/proxmox/inkognito-lxc.sh)"
```

| Variable | Default | What it does |
|---|---|---|
| `CTID` | next free ID | Container ID |
| `CT_HOSTNAME` | `inkognito` | Hostname |
| `CT_CORES` / `CT_RAM` / `CT_DISK` | `1` / `64MB` / `1GB` | Resources |
| `CT_BRIDGE` / `CT_VLAN` | `vmbr0` / none | Network bridge, VLAN tag |
| `CT_NET` / `CT_GW` | `dhcp` | Static IP + gateway |
| `INKOGNITO_REPO` | `4velinux/Inkognito` | Install from your fork |
| `CHANNEL` | `release` | `release` = verified, `main` = every commit |
| `AUTO_UPDATE` | `yes` | Nightly check |

```bash
pct exec <CTID> -- inkognito-update              # update now
pct exec <CTID> -- inkognito-update --rollback   # previous version
pct exec <CTID> -- inkognito-update --status     # what is live
```

### Docker

```bash
docker compose up -d        # http://localhost:8080
```

Alpine + lighttpd, non-root, read-only filesystem, zero capabilities.

</details>

---

## 💡 Good to know

- **Drafts are per address.** Disk, `localhost:8765`, and a LAN IP each keep separate drafts. Export/Import moves them.
- **Copy just works,** even on `file://` and plain `http://`, via an automatic fallback.
- **Styled letters are Unicode look-alikes**, the same trick every formatter uses. Screen readers spell them out and LinkedIn search skips them, so style a few key phrases, not whole posts.
- **Want it reachable away from home?** Use Tailscale or WireGuard, not an open port.

---

## 🤝 Contributing

PRs welcome, forks encouraged. Read [CONTRIBUTING.md](CONTRIBUTING.md). One rule is non-negotiable: **zero network requests**, enforced by `scripts/check.sh` on every commit.

## 📄 License

[MIT](LICENSE). Built in Thailand by [Pedro Avelino](https://www.linkedin.com/in/pedroavelino) ([GitHub](https://github.com/4velinux)).

<div align="center">

⭐ **If Inkognito is useful, a star helps other people find it.**

</div>
