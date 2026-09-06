# Changelog

## 0.1.0 — Unreleased

First working version. Nothing has shipped, so this is the whole feature set
rather than a list of changes.

### The app

- Five tabs: Overview, Clients, Network, Logs, and More, with Alerts, VPN,
  Firewall, System, Firewalls and Settings behind the last one.
- Clients assembled by joining DHCP leases, the ARP table and static mappings
  on MAC, with an IP fallback. Tapping through shows the filter-log lines
  mentioning that address.
- Throughput sparklines derived from lifetime byte counters by differencing
  consecutive samples. Sixty points per interface, cleared when the counter
  resets or the firewall is switched.
- An alerts feed computed on device: gateways, stopped services, disk, memory,
  swap and mbuf pressure, state-table fill, available updates, certificate
  expiry, CARP maintenance mode and IPsec state.
- VPN status for OpenVPN, IPsec and WireGuard.
- A read-only browser for firewall rules, NAT port forwards and aliases.
- CARP status, configuration revision history and certificate expiry.
- Multiple firewalls, each with its own keychain item, TLS settings and
  refresh interval.
- A home screen widget in the small and medium families, fed by a snapshot the
  app writes to the App Group rather than by its own networking.
- All four Catppuccin flavours and all fourteen accents, with separate
  light-appearance and dark-appearance choices.
- TLS: SHA-256 leaf pinning, with untrusted-certificate acceptance as the
  weaker fallback.

### Fixed before first build

- `APIClient` still called the single-server `Keychain.apiKey()` after the
  multi-firewall rewrite. Every request threw `noAPIKey`; the compiler caught
  it, but only once something built.
- No test target and no declared scheme, so `make test` failed with "Scheme
  Vaktpost is not currently configured for the test action". `project.yml` now
  declares the scheme rather than leaving Xcode to invent a non-shared one.
- `SUPPORTED_PLATFORMS` was left to fall back, which xcodebuild reported as
  "Supported platforms for the buildables in the current scheme is empty".
- `project.yml` used XcodeGen's `info:` and `entitlements:` keys, which
  *generate* the files they point at. Every `xcodegen` run overwrote the
  hand-written Info.plists and entitlements: the app lost `UILaunchScreen` and
  its ATS exception, both entitlements became empty dicts taking the App Group
  with them, and the widget lost its `NSExtension` dictionary. Nothing failed
  to build — the simulator just refused to install, with "extensionDictionary
  must be set in placeholder attributes". Now `INFOPLIST_FILE` and
  `CODE_SIGN_ENTITLEMENTS` under `settings`, with a check in
  `vaktpost-tools/tests/layout.sh` so it cannot recur silently.
- `Health.color(_:)` was nonisolated while reading `@MainActor` state off
  `ThemeManager`. Older toolchains warned; the one in Xcode 26 errors. Now
  `@MainActor`, which costs nothing because every caller is a SwiftUI view and
  `View` is itself main-actor isolated.

### Known gaps

- Swift 5 language mode with `minimal` concurrency checking, against a house
  default of 6.0 and `complete`. `TrustEvaluator` is `@unchecked Sendable`
  around a hand-rolled lock and needs rewriting before the setting can be
  raised. See `Config/Shared.xcconfig`.
- `services/dhcp_server/static_mappings` is fetched flat. On some REST API
  versions these are per-interface children needing a `parent_id`, in which
  case the Clients list shows no static entries.
- The two `href="#"` placeholders in `public-web/index.html` still need the
  repository URL.
