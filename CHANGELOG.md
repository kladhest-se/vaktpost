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

### Fixed against a live firewall

First run against real hardware (pfSense Plus 26.07). Five field-name guesses
were wrong, and every one failed by rendering a plausible zero rather than an
error — which is the worst way for a dashboard to be wrong:

- Uptime is `"5 Days 01 Hour 37 Minutes 40 Seconds"`, not a count of seconds.
  Reading it as an integer took the leading 5 and stopped, so a box up for five
  days showed "up 0m".
- Load average is `cpu_load_avg`. None of the three names tried existed, so the
  row read "—".
- The state table fields have no underscores — `currentstates`, not
  `current_states` — and `maximumstates` is null unless overridden, so the
  enforced limit is `defaultmaximumstates`. Together those showed "Current
  states 0" on a firewall holding 11,169, with no meter.
- `status/interfaces` returns a dotted netmask, so addresses rendered as
  `178.174.216.246/255.255.255.224`.
- A live WAN reports `"enable": false`. That field tracks something other than
  administrative state, and treating it as authoritative greyed out a working
  uplink. Health now follows link state.

Interfaces now show `descr` ("WAN_1") rather than the internal `name` ("wan"),
and the Overview gained a hardware row from `platform` and `cpu_count`.

`Tests/VaktpostTests/LiveShapeTests.swift` pins all of this to payloads pasted
verbatim from `curl`. Hand-written fixtures only test the field names their
author already believed in, which is precisely what failed here.

### Added

- Installed packages under System, with versions and an alert when any has an
  update pending.
- Blocked hosts under System, read from the `sshguard` and `virusprot` pf
  tables. Loaded when that screen appears rather than on the refresh timer —
  the tables payload is dominated by `bogons`, which is large, static and of no
  interest here. Retained entries are capped per table; the count stays honest.
- Three more log sources: auth (webConfigurator, SSH and API login attempts),
  DHCP, and OpenVPN. The Logs tab now offers Filter, System, Auth, DHCP and
  VPN; the pass/block filter appears only for the filter log, since the others
  carry no action.

### Known gaps

- `system/update` and `routing/gateway/groups` both return null on 26.07 with
  nothing configured, so there was no shape to build against. Left alone rather
  than guessed at.
- No Dynamic DNS. The REST API package exposes no dyndns endpoints at all —
  `/api/v2/services/` covers acme, bind, cron, dhcp_server, dns_forwarder,
  dns_resolver, freeradius, haproxy, ntp, service_watchdog, ssh and
  wake_on_lan, and nothing else. Confirmed against the OpenAPI schema on
  26.07, not assumed.

- Swift 5 language mode with `minimal` concurrency checking, against a house
  default of 6.0 and `complete`. `TrustEvaluator` is `@unchecked Sendable`
  around a hand-rolled lock and needs rewriting before the setting can be
  raised. See `Config/Shared.xcconfig`.
- `services/dhcp_server/static_mappings` is fetched flat. On some REST API
  versions these are per-interface children needing a `parent_id`, in which
  case the Clients list shows no static entries.
- The two `href="#"` placeholders in `public-web/index.html` still need the
  repository URL.
