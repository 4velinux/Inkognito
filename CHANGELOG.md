# Changelog

## v2.0.0 · 2026-11-16

- Greet first-time visitors with a short introduction: what Inkognito is, the zero-request guarantee, and a direct link to download the single file. It closes for good with one click, never shows inside an embedding frame, and reopens from "About and download" in the footer.
- Keep "Copy for LinkedIn" in the sticky header so the main action is always one click away. Both copy buttons confirm with "Copied ✓".
- Add a Help menu to the top bar explaining local drafts, templates as optional starting points, and the keyboard shortcuts.
- Refresh the look: brand gradient accent, softer depth behind the panels, a translucent header, gradient primary buttons and clearer hover states. Layout, editor boundaries and the LinkedIn preview geometry are unchanged.
- Shorten the header on phones: the byline and "Theme:" label fold away and the copy button moves next to the logo.
- Add link-preview metadata, so sharing inkognito.a-eye.cloud on LinkedIn shows a title, summary and screenshot. The metadata is text only; the page still loads nothing from any server.
- Still one self-contained HTML file with the same content security policy.

## v1.2.0 · 2026-11-02

- Let embedding hosts supply an optional collection position and receive previous/next events from the existing original viewer. Keep the standalone 20-photo limit and local navigation.
- Keep a host-loaded replacement image open, reset its zoom to fit and clear external navigation when closing, clearing media or changing drafts.
- Validate navigation metadata without changing editor text, zoom or browser drafts. Add browser checks for boundaries, keyboard actions, invalid values and reset behavior.

## v1.1.1 · 2026-11-02

- Give the writing area a visible label, stronger light/dark boundary and clear focus state. Keep native vertical resizing bounded to the screen with internal text scrolling.
- Outline formatting controls and keep long formatting menus inside the viewport, including after resizing the window.
- Make the fixed-size feed preview scrollable by keyboard, with a visible scrolling hint. Keep the LinkedIn post card, image gallery and original viewer styling unchanged.
- Add desktop, tablet and phone browser checks for editor boundaries, resizing, highlight alignment, keyboard scrolling and menu overflow.

## v1.1.0 · 2026-11-02

- Preview up to 20 ordered local images with image descriptions, reorder and remove controls. The first image determines the layout for larger galleries; original files remain unchanged.
- Open the uncropped original with post context, fit/original-size zoom, previous/next, keyboard navigation and Escape. Closing returns focus and keeps the selected images.
- Label the feed as an approximate LinkedIn preview. Use neutral preview metadata instead of illustrative engagement counts.
- Keep image pixels in memory, outside saved drafts and JSON exports. Changing drafts clears transient images; failed or oversized selections preserve the previous gallery.
- Add shared media/viewer functions and image-free card serialization for embedding without duplicating the gallery. Add synthetic browser regression checks while retaining the offline single-file app.


## v1.0.2 · 2026-09-29

- Inspect browser-observed resource requests from the bottom-left badge. Hover, click, tap or focus the badge to open a scrollable list of destination hosts, URLs, resource types and same-origin/other-origin labels.
- The request list updates as resources are observed and retains observer entries beyond the browser's timing buffer. URLs are displayed as text without contacting their destinations.
- Replaced the unsupported "from the page host" attribution with "resource requests observed" and explained cached resources, cross-origin restrictions and the limits of this view.
- Added an explicit unavailable state when resource timing is unsupported, instead of presenting an unverified zero.
- Still one self-contained HTML file, with no new dependencies or outbound connections. The existing content security policy remains intact.

## v1.0.1 · 2026-09-24

- New favicon and header mark: a fountain-pen nib doubling as a masked face, referencing Ink, Incognito and LinkedIn's blue in one icon. Embedded inline (no external file, no network request).
- "Sample post (demo)" added to the Templates menu, so the built-in demo post can be loaded back anytime without erasing your real drafts.
- README rewritten to lead with the core idea: Inkognito is one self-contained HTML file, download it and open it, nothing to install or host. Self-hosting is now a clearly optional, collapsed section.
- Added a real, dated privacy comparison against 6 competing LinkedIn formatters (`docs/privacy-comparison.md`), based on live network/cookie/tracker checks of their marketing pages.
- Added creator credit ("Created by Pedro Avelino", with LinkedIn and GitHub links) to the app header/footer and to the README.
- Moved the keyboard shortcuts button into the editor toolbar, next to the WYSIWYG controls.
- Hosted mirror added at [inkognito.a-eye.cloud](https://inkognito.a-eye.cloud) (Cloudflare Pages), redeploying automatically on every published release.

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
