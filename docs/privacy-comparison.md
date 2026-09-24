# Privacy comparison: Inkognito vs. hosted LinkedIn formatters

**Date:** 24 September 2026
**Author:** [Pedro Avelino](https://www.linkedin.com/in/pedroavelino)

## What was checked

Marketing/landing pages of the most-used LinkedIn writing tools, loaded in a fresh browser profile with no ad blocker, no prior cookies, and no interaction beyond the page load itself. For each site:

- Every network request fired on load (`Browser pane → read_network_requests`)
- `document.cookie` immediately after load
- Presence of known tracker globals (`gtag`, `ga`, `fbq`, `hj`, `clarity`, `posthog`, `Intercom`, `_linkedin_partner_id`)
- Third-party `<script src>` tags queued on the page, including those gated behind a cookie-consent banner

## Results

| Tool | Trackers observed on load | Cookies set | Notes |
|---|---|---|---|
| **Taplio** | Google Analytics (2 separate GA4 measurement IDs), Meta Pixel, Microsoft Clarity | 12 | GA and Meta beacons fire, and a Clarity session-replay recorder starts, before any interaction with the page. |
| **AuthoredUp** | Google Tag Manager, MailerLite, an affiliate-tracking script, reCAPTCHA | 0 until consent given | 16 third-party scripts queued behind a cookie-consent banner. Nothing fires before consent, but the affiliate tracker and Tag Manager are ready the moment it's given. |
| **Typefully** | None found | 0 | The marketing page loaded clean: 74 requests, all first-party (`typefully.com`). Included here because a clean result deserves reporting exactly as much as a dirty one. |
| **Inkognito** | None. Ever. | 0 | `default-src 'none'; connect-src 'none'` in the page's Content Security Policy makes an outbound request from the app impossible, not merely absent. This is enforced by the browser itself, and `scripts/check.sh` fails the build in CI if the policy, or the zero-network guarantee, ever regresses. |

## Caveats, stated plainly

- **This checks marketing pages, not the paid product.** What happens inside a tool after signup, once you're pasting real drafts into it, was not tested here and may look different (better or worse) than the landing page.
- **A request never showing a canary phrase in its URL doesn't prove your text never left the page.** Request bodies are opaque to a network-request listing; only reading server-side logs (which nobody outside these companies can do) would settle that fully.
- **Session-replay tools sometimes mask typed input by default** (password-style fields, or configured exclusions), so "Clarity is present" is evidence of a recording capability, not proof that this specific draft text was captured.
- **Sites change.** This is a snapshot from one date, not a permanent verdict. Cookie banners, consent-management platforms and geographic variation (EU vs. US IP, for instance) can change what fires on a given visit. Re-run the check yourself before relying on it.
- **Absence of evidence isn't evidence of absence** for Typefully specifically: a clean marketing-page load is a genuinely good sign, but it's one snapshot, not an audit of their product or their backend.

## Why this matters more than it looks

None of this makes Taplio or AuthoredUp unusual. It makes them normal: a hosted SaaS tool needs analytics to run a business, and analytics means a script watching the page you're typing into. That trade-off is reasonable for most software. It's a worse trade-off for the one text box where you draft things you haven't decided to say publicly yet.

Inkognito's answer isn't "we promise not to track you." It's "there is no server for your text to reach, so the question doesn't apply." That's a different, stronger, and mechanically verifiable claim, and it's why the check above is worth re-running rather than taking on faith.
