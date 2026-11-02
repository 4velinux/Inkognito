# Image preview browser checks

The application still has no dependencies or build step. These development-only checks use Node's test runner and maintained `playwright-core` outside the repository. The harness generates only synthetic PNG images in memory and a temporary HTML copy exposing the same IIFE functions used by an embedding adapter. It removes that copy after the run.

Install a test helper outside the source checkout:

```bash
npm install --prefix /tmp/inkognito-media-tests --cache /tmp/inkognito-npm-cache playwright-core@1.56.1 --no-save --ignore-scripts
```

Use an installed Chromium binary (tested with Chrome for Testing 156 and `playwright-core` 1.56.1):

```bash
INKOGNITO_PLAYWRIGHT=/tmp/inkognito-media-tests/node_modules/playwright-core \
INKOGNITO_CHROMIUM=/path/to/chrome \
node --test tests/media.cjs
bash scripts/check.sh
```

No browser, generated images, screenshots, package lock or runtime dependency belongs in the repository. Set `INKOGNITO_SCREENSHOTS=/tmp` to optionally inspect synthetic desktop/phone screenshots.

The UI checks cover ordered picking and reordering, quoted descriptions and the following Remove/reorder/Tab action, proportional pairs, first-image gallery orientation, larger galleries, feed-only crops, original inspection/navigation/zoom, Escape/focus restoration, removed media, draft isolation, malformed images, payload limits, phone/dark layout, image-free exports and zero outbound requests. The adapter seam checks exercise `setPreviewMedia(items)`, `openMediaViewer(index)` and `cardHTML(device, body, true)` in the temporary copy, without adding a production test API.

## Shared embedding contract

The functions live inside the existing IIFE. `setPreviewMedia(items)` accepts ordered `{id, src, alt, width, height}` records and returns `true` on acceptance, `false` on rejection while preserving existing media. The caller supplies already-decoded positive integer dimensions and owns supplied blob URLs. The standalone picker decodes local files and revokes only its own object URLs. Limits: 20 unique IDs, 256 characters per ID, 2,000 characters per description, 16 MiB characters per source, 64 MiB source characters total, 40 million decoded pixels per image and 80 million total. Sources must be image data URLs or blob URLs. No remote asset loading is allowed. The local picker decodes one image at a time, includes the existing gallery in its pixel budget, and stops starting more decodes on overflow, failure or cancellation. Staged object URLs are revoked when a batch is rejected or cancelled. Controlled native Image wrappers in the test copy verify scheduling and cleanup without allocating large images.

`openMediaViewer(index)` returns whether the selected index is valid. A document `inkognito:viewer` CustomEvent carries `{open: true}` on activation and `{open: false}` on close. The close notification follows internal state cleanup, so an adapter may restore a temporary inspection selection from that listener. Media replacement preserves the viewer's image identity when present and closes when removed. The host may provide viewport space while keeping the same frame. Saved formatting uses `cardHTML(device, body, true)` to omit transient media. Media updates do not write editor text or browser drafts.

The 3:1 to 4:5 single-image framing and orientation-dependent layout follow [LinkedIn's documented organic-photo behavior](https://www.linkedin.com/help/linkedin/answer/a527229). The five-visible-tile limit, overflow counter, precise multi-image geometry and expanded-view controls remain explicit approximations pending authenticated visual comparison. Two images use a common height and proportional columns, with each image constrained to the supported feed ratio range. The original viewer always retains the original pixels.
