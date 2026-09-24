# Contributing to Inkognito

Thanks for helping. Inkognito is deliberately small: one HTML file, no build step, no dependencies.

## The privacy promise

Every change must keep these true:

1. The app makes **zero network requests**. No CDNs, web fonts, analytics, error trackers or remote images.
2. The Content Security Policy in `inkognito.html` stays at `default-src 'none'` with `connect-src 'none'`.
3. User text never leaves the browser. Storage is `localStorage` only, under the `inkognito:` prefix.

`scripts/check.sh` enforces this, and CI runs it on every pull request.

## Working on the app

```bash
git clone https://github.com/<you>/inkognito.git
cd inkognito
open inkognito.html          # or xdg-open / start
```

Edit `inkognito.html` directly and reload. Before opening a PR:

```bash
bash scripts/check.sh
```

Please test on a desktop browser and a phone-width window (the mobile preview and the toolbar both wrap).

### Code style

- Plain ES2018 JavaScript, no frameworks, no transpiling. Keep it working in current Chrome, Safari and Firefox.
- Colors come from the CSS tokens at the top of the file, and every color needs a light and a dark value.
- Keep the UI copy plain and specific. No em dashes.

### Ideas that fit well

- New letter styles or list markers
- New voice or privacy checks (with a low false-positive rate, and a clear fix)
- Preview accuracy (fold measurement, fonts, LinkedIn layout changes)
- Translations of the interface
- Deploy options for other platforms (TrueNAS, Unraid, Kubernetes)

## Releases

Maintainers bump `var VERSION` in `inkognito.html`, add a line to `CHANGELOG.md`, then tag:

```bash
git tag v1.1.0 && git push origin v1.1.0   # or: GitHub > Releases > Draft a new release
```

Publishing a release in the GitHub UI works the same way. The release workflow checks the tag matches the version, runs the privacy guard, and publishes `inkognito.html` with a SHA-256 checksum. Self-hosted containers pick it up on their nightly check.

## Testing the Proxmox installer from your fork

```bash
INKOGNITO_REPO=<you>/inkognito INKOGNITO_REF=<branch> CHANNEL=main \
  bash -c "$(wget -qLO - https://raw.githubusercontent.com/<you>/inkognito/<branch>/proxmox/inkognito-lxc.sh)"
```
