# public-web

The project site and its synthetic XMLAPI test lab. It uses small PHP entry
points, CSS, and browser scripts — no build step, framework, database, fonts,
analytics, or third-party runtime assets.

```sh
php -S 127.0.0.1:8000 -t public-web
```

For production, point a PHP-capable web server's document root at
`public-web/`. GitHub Pages cannot run the PHP entry point.

## XMLAPI Lab

`lab.php` is the public browser console and `xmlrpc.php` is the endpoint used
by Vaktpost. Enter the website origin as the firewall base URL; Vaktpost adds
`/xmlrpc.php` itself.

- Username `review`: healthy App Review data
- Username `updates`: outdated firmware and one outdated package
- Username `degraded`: gateway, VPN, and service problems
- Username `fault`: sign-in succeeds, then feature calls fail deliberately
- Administrative writes, including Quick Block, are answered with receipts and
  kept in the session, so the change shows up in the next read
- Username `noaccess`: the password is accepted, but the account is refused
  for lacking the XML-RPC privilege
- Any other username, or a wrong password: refused as a wrong sign-in
- Default password: `vaktpost-demo`

Set `VAKTPOST_DEMO_PASSWORD` in production to change the shared password.
Refused sign-ins are XML-RPC faults starting with "Authentication failed", as
pfSense sends them, not HTTP 401; only a request with no Basic Auth header gets
a 401. The endpoint never evaluates the submitted PHP or connects to a firewall. It
recognizes only known Vaktpost request signatures and returns synthetic data.
The Updates profile uses an expiring PHP session so the app can verify that a
simulated firmware or package update completed.

Rules, port forwards, aliases, and separators can be created, edited,
deleted, and reordered — the point of a public endpoint is to exercise the
app's write paths too, not just read a fixed fixture. Each PHP session gets
its own mutable copy of the fixtures, seeded from the same data every
read-only request already returns, so one visitor's changes never affect
another's. That copy resets to the original fixtures after 20 minutes of
inactivity, independent of the host's own session garbage collection —
GC is tuned for freeing memory on a busy host and gives no guarantee about
when, or whether, a low-traffic lab session actually gets cleaned up. So
emptying out the ruleset to see how the app handles it is expected use, not
something that needs undoing: it fixes itself on its own on the next visit
after a short wait, or immediately for a returning visitor once the
20 minutes have passed.

The fixtures populate the app's principal screens: WAN/LAN/VPN interfaces,
gateways and services; ARP and DHCP clients; filter rules, NAT and aliases;
installed and outdated packages; VPN status; system notices; all five logs;
pf tables, pfBlockerNG/DNSBL, HAProxy, ACME and RRD traffic history. The
browser console exposes representative probes so the response shapes can be
checked before connecting the app.

Every log is session-backed and grows as that session polls it. The filter log
rotates through parseable IPv4, IPv6, TCP, UDP and ICMP pass/block examples and
emits a deterministic three-event burst every fifth ordinary poll. Histories
are capped at 500 rows and the requested Vaktpost tail limit is honored. The
browser console can append one event, append a five-event burst, or reset its
own fixtures; an iOS connection has a separate session and advances
automatically, so testing the app never depends on keeping the browser open.

Put ordinary rate limiting in front of the public endpoint. The Basic Auth
password gates only public synthetic fixtures and is not a substitute for rate
limiting.

## Screenshots

`screenshots/` holds the page's images at 990 px wide, and
`screenshots/thumbs/` the gallery's at 460 px. The gallery loads only the
thumbnails; the lightbox opens the full file named in each image's
`data-full`. Regenerate the thumbnails whenever a screenshot changes, or the
gallery will show the old one while the lightbox shows the new.

## Before publishing

- Serve the site over HTTPS and confirm the host passes the `Authorization`
  header to PHP; the app refuses plain HTTP.
- Put ordinary rate limiting in front of `xmlrpc.php`.
- Keep `$releaseVersion` in `index.php` equal to `MARKETING_VERSION`;
  `vaktpost-tools` checks it. The hero badge shows the newest `X.Y.Z` (or
  `vX.Y.Z`) tag on GitHub instead, and falls back to `$releaseVersion` until a
  tag exists. The lookup is server-side and cached in the temp directory for
  an hour (ten minutes after a failure); delete
  `vaktpost-latest-release.json` there to refresh it immediately. It needs the
  curl extension or `allow_url_fopen`.
- Keep `privacy.php` true to the app. It is the privacy policy URL given to App
  Store Connect; update `$policyUpdated` when its substance changes.
- Replace the `href="#"` on the store badge with the App Store link once the
  app is live, and add an `og:image` when a release image exists.

## Theming

`styles.css` carries one Catppuccin flavour — Macchiato — with mauve as the
one accent, both applied unconditionally to `:root`. The site is not
switchable: earlier versions carried all four flavours and all fourteen
accents behind a picker (`theme.js`), removed since a marketing page gains
nothing from a control the app itself doesn't require. `--red` and `--green`
stay defined alongside the rest of the palette even though nothing on this
page uses them directly — the lab page's own stylesheet (`lab.css`) reads
them as functional error/success colours.
