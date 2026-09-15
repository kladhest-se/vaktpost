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
- Default password: `vaktpost-demo`

Set `VAKTPOST_DEMO_PASSWORD` in production to change the shared password. The
endpoint never evaluates the submitted PHP or connects to a firewall. It
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

Put ordinary rate limiting in front of the public endpoint. The Basic Auth
password gates only public synthetic fixtures and is not a substitute for rate
limiting.

## Before publishing

- Add the canonical public repository URL when it has been chosen. The current
  page contains no placeholder or dead source link.
- Add an `og:image` when a public release image is available.
- The device rendering in the hero is built from the same design tokens as
  the app. It is a rendering, not a product screenshot.
- Keep the version 0.1 feature and deferred-scope lists aligned with the root
  `README.md` before publishing.
- Confirm that the public host passes the `Authorization` header to PHP and
  serves the site over HTTPS before using the lab from iOS.

## Theming

`styles.css` carries all four Catppuccin flavours as custom-property sets
selected by `:root[data-flavor]`, and all fourteen accents by
`:root[data-accent]`. `theme.js` sets those attributes and remembers the
choice in `localStorage`, defaulting to Latte for visitors whose system is in
light mode and Mocha otherwise.

Because the whole page reads from those variables, adding a flavour means
adding one block to the top of the stylesheet and one entry to the `FLAVORS`
array — nothing else changes.
