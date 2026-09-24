# Inkognito — project notes for Claude

Read this before making changes. It captures conventions, known gotchas, and
the state of things as of v1.0.1, so a fresh session doesn't have to
rediscover them.

## What this is

A single self-contained HTML file (`inkognito.html`) that formats LinkedIn
posts entirely client-side: Unicode text styling, a feed preview, a
character/fold meter, a voice linter, and a PII/secrets scanner. Zero
network requests, ever, enforced by a strict CSP (`connect-src 'none'`) and
by `scripts/check.sh`, which runs in CI on every push and fails the build if
that guarantee ever regresses.

**The core pitch, always lead with this:** download `inkognito.html`, open it
in any browser, done. No install, no server, no account. Everything else
(installers, Proxmox, Docker, the Cloudflare mirror) is optional convenience
for people who specifically want it hosted or always-on, not a requirement.
Don't let the README or any messaging drift back toward installer-first.

Built by Pedro Avelino ([LinkedIn](https://www.linkedin.com/in/pedroavelino),
[GitHub](https://github.com/4velinux)). Public repo, MIT license, PRs
welcome.

## House style (applies everywhere: code comments, docs, commit messages, release notes)

- **Never use an em dash.** Use a comma, colon, or restructure the sentence.
- Plain, direct language. Short paragraphs. No corporate filler.
- When writing LinkedIn-post content *about* this project (announcements,
  launch posts), follow the "Digital Writing DNA" voice: pattern-interrupt
  hook, short paragraphs, →/✓/• hierarchy, no AI-slop words (crucial,
  dynamic, seamlessly, unlock, vibrant), ends on one open question. That
  voice is for marketing copy *about* Inkognito, not for the repo's own
  docs, which should just be clear and to the point.

## Versioning and releases

- Bump `var VERSION='x.y.z'` near the bottom of `inkognito.html`, add a
  matching entry to `CHANGELOG.md` (newest on top).
- **The release workflow requires the git tag to exactly equal `v` +
  VERSION.** Tag `1.0.0` (no `v`) will fail the "Tag matches app version"
  check and silently skip attaching any assets, this has happened before.
  Always tag as `v1.0.1`, `v1.0.2`, etc.
- To cut a release: push the version bump to `main`, then either
  `git tag vX.Y.Z && git push --tags` or use the GitHub UI (Releases → Draft
  a new release → tag `vX.Y.Z`, target `main` → Publish). Either should work
  from a real authenticated `gh`/`git` session. (Note: the cloud session this
  project was originally built in had release/tag-push/repo-settings writes
  blocked by an org policy on the GitHub API proxy, "not permitted for this
  session type", not a GitHub permissions issue. A locally-run Claude Code
  session using the user's own `gh auth` should not hit this and can just run
  `gh release create vX.Y.Z inkognito.html inkognito.html.sha256 --generate-notes`
  directly.)
- There's a stray orphaned tag `1.0.0` (no `v` prefix) left over from an
  early mistake, no release is attached to it, harmless but could be deleted
  for tidiness.
- Compute the checksum before manual releases: `sha256sum inkognito.html`.

## CI/CD (all in `.github/workflows/`)

- **`ci.yml`** ("Privacy check"): runs `scripts/check.sh` on every push.
  Checks CSP directives, forbidden network APIs (fetch/XHR/WebSocket/etc.),
  no external scripts/styles/fonts, JS parses, shellcheck on all shell
  scripts. Treat any failure here as a hard blocker, never weaken this.
- **`release.yml`**: triggers on `release: published` or `push: tags:
  v*.*.*`. Verifies tag == version, runs the privacy guard, computes the
  SHA-256, attaches `inkognito.html` + `.sha256` to the release, then builds
  and pushes a multi-arch container image to `ghcr.io`.
- **`cloudflare-pages.yml`**: triggers on `release: published` (or manual
  `workflow_dispatch`). Deploys `inkognito.html` (as `index.html`) to
  Cloudflare Pages, live at **inkognito.a-eye.cloud**. Uses
  `cloudflare/wrangler-action@v3` with `command: pages deploy _site
  --project-name=inkognito --branch=main`.
  **Do not use `cloudflare/pages-action`, it was deprecated and removed from
  GitHub entirely ("Unable to resolve action" error).** Requires repo
  secrets `CLOUDFLARE_API_TOKEN` and `CLOUDFLARE_ACCOUNT_ID` (already set),
  and a Cloudflare Pages project named exactly `inkognito` with that custom
  domain attached (already set up).
- Dependabot is configured (`.github/dependabot.yml`) and periodically opens
  PRs bumping action versions, these are safe to merge after CI passes.

## Repo layout quick reference

- `inkognito.html` — the entire app, single file, no build step.
- `install.sh` / `install.ps1` — optional smart installers (auto-detect
  desktop/server/Proxmox/NAS/Windows-Server, no menus, 5s cancellable
  countdown before anything network-facing).
- `proxmox/` — Proxmox VE Alpine LXC helper script + in-container updater
  (`inkognito-update.sh`, supports `--rollback`, `--status`).
- `docker/`, `Dockerfile`, `compose.yaml` — hardened Alpine+lighttpd
  container for NAS boxes.
- `docs/privacy-comparison.md` — dated, methodology-documented comparison of
  Inkognito's zero-network-request design against competing LinkedIn
  formatters. Re-run this kind of check rather than trusting stale numbers
  if it's ever updated, it's a factual claim, not marketing copy.
- `docs/screenshot.png` — README hero image. Regenerate with Playwright
  (`chromium.launch()`, load `file://.../inkognito.html`, viewport
  1800x1125 @ deviceScaleFactor 1.2 for the existing 2160x1350 size)
  whenever the header/toolbar UI changes, so it doesn't go stale.
- `scripts/check.sh` — the privacy guard, described above.

## Known gaps / untested paths

- The smart installers have been tested via CI simulation (GitHub Actions
  matrix across ubuntu/macos/windows) and locally, but never on real
  hardware: real Proxmox VE, real NAS appliances (TrueNAS/Unraid/Synology/
  QNAP), or a real Windows Server box. Treat bug reports there as plausible.
- GHCR package visibility, repo topics/description, and branch protection
  are set manually via the GitHub UI, not from any workflow.

## Things this session could never do (org policy, GitHub API proxy)

If you're a fresh Claude Code session with the user's own credentials, you
likely won't hit these, they were specific to the sandboxed cloud session
this project was built in:
- Creating a GitHub repo, creating/editing/deleting a GitHub release,
  pushing a git tag, and PATCHing repo settings (description/topics) all
  returned "not permitted for this session type" or proxy 403s. Don't
  assume the same limits apply to you, just try the normal `gh`/`git`
  commands first.
