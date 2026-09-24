# Privacy comparison: Inkognito vs. hosted LinkedIn formatters

**Date:** 24 September 2026
**Author:** [Pedro Avelino](https://www.linkedin.com/in/pedroavelino)

## What was checked

The marketing/editor pages of the most-used LinkedIn writing tools, loaded in a fresh browser profile with no ad blocker and no prior cookies. For each site I:

- Counted every network request fired, from page load through typing a short canary phrase into the editor (where one existed)
- Counted distinct outside domains contacted (anything not the tool's own)
- Read `document.cookie` after that interaction
- Watched for known tracker globals and endpoints (Google Analytics/Ads, Meta Pixel, Microsoft Clarity, RudderStack, PostHog, LinkedIn Insight Tag, Crisp, Sentry) and noted anything that fired specifically after typing

## Results

| Tool | Requests | Outside domains | Cookies set | What's on the page |
|---|---|---|---|---|
| **Taplio** | 67 | 27 | 12 | Google Analytics and Ads, Meta Pixel, Microsoft Clarity (session recording), RudderStack analytics. No cookie banner shown. |
| **ConnectSafely** | 73 | 25 | 10 | Meta, X, Reddit and Google Ads pixels, Clarity, Crisp chat. It has a cookie banner, but ad cookies were already set before I answered it. Clarity sent data right after I typed. |
| **WaveGen** | 40 | 7 | 3 | Google Analytics, LinkedIn Insight Tag, PostHog. A call to PostHog's session-recording endpoint went out right after I typed. |
| **AuthoredUp** | 25 | 8 | 0 | Google, MailerLite, YouTube. No ad trackers. The page had no editor to type into; it points you to a Chrome extension or sign-up instead. |
| **Typefully** | 84 | 2 | 0 | Google Fonts and Sentry error monitoring. Most requests are its own. |
| **Poper** | 53 | 2 | 0 | Google Fonts and Cloudflare's analytics. |
| **Inkognito** | **1** | **0** | **0** | The page itself. The browser is told to block every other connection. |

## Caveats, stated plainly

- **This checks what a page does on load and on typing, not the full paid product.** Behavior after signup or deep in a paid workflow wasn't tested and may differ.
- **A request never showing your text in its URL doesn't prove nothing left the page.** Request bodies are opaque to a network-request listing; that's a limit of this method, not a clean bill of health.
- **Session-replay tools sometimes mask typed input by default**, so a tool like Clarity or PostHog being present is evidence of a recording capability, not proof this exact text was captured.
- **Sites change.** This is a snapshot from one date. Cookie banners, consent platforms and your region can all change what fires on a given visit. Re-run it yourself before relying on it.
- Inkognito's single request is the page's own HTML loading from wherever you opened it (disk, a release download, or a server if you chose to self-host). After that, its Content Security Policy makes a second request impossible, not just unlikely.

## Why this matters more than it looks

None of this makes these tools unusual, it makes them normal. A hosted SaaS product needs analytics to run a business, and analytics means a script watching the page you're typing into. That trade-off is fine for most software. It's a worse trade-off for the one text box where you draft things you haven't decided to say publicly yet.

Inkognito's answer isn't "we promise not to track you." It's "there is no server for your text to reach, so the question doesn't apply." That's a different, stronger and mechanically verifiable claim, which is exactly why it's worth re-running rather than taking on faith.
