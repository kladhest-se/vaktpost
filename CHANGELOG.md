# Changelog

## Unreleased

- Make the synthetic XMLAPI lab generate bounded, session-isolated live logs
  with valid rotating filter events, deterministic bursts, tail limits, and
  browser probes for poll, burst, and reset testing.
- Replace the last stale untrusted-TLS recovery instruction with the secure
  per-firewall certificate review and fingerprint comparison workflow.
- Add pause/follow controls, unseen-event counts, stable row identity, scoped
  refresh, failure backoff, and optional address/port redaction to live logs.
- Confirm transient fleet health and connectivity problems across two readings
  before alerting, and exponentially back off repeatedly unavailable firewalls.
- Expand the existing per-firewall health overview and fleet dashboard with
  interface, gateway latency/loss, state-table, update, and notice signals.
- Add per-firewall certificate identity, validity, fingerprint, trust, expiry,
  mismatch, and explicit re-pin controls while enforcing HTTPS-only endpoints.
- Add bounded live firewall-log polling with structured filters and safe
  parsing of prefixed, raw, malformed, and partial filterlog records.
- Allow an inbound firewall-log event to prefill a disabled staged rule for
  review through the existing write coordinator and Apply Changes workflow.
- Treat a short-lived updater as accepted or completed instead of reporting a
  false launch failure merely because pfSense's WebUI PID file is absent.
- Use pfSense's ordinary package-update flags rather than its forced reinstall
  flag, while retaining explicit exit-code failure reporting.

## 0.1.0 — First public release

### Added

- Multiple pfSense CE and pfSense Plus firewall profiles with monitor-only mode
  by default, separate Keychain credentials, and TLS certificate pinning.
- Configurable health overview with interfaces, gateways, resources, services,
  VPNs, logs, clients, freshness, and local history.
- Searchable client inventory combining DHCP, ARP, and static mappings with
  offline MAC-vendor names and related traffic.
- Live and historical interface traffic, host traffic, analytics, and network
  diagnostics.
- OpenVPN, WireGuard, and IPsec status with connected peers.
- Searchable firewall, system, authentication, DHCP, and OpenVPN logs with a
  combined incident timeline.
- On-device alerts for connectivity, services, capacity, certificates, CARP,
  VPNs, updates, and Dynamic DNS.
- Views for system notices, certificates, ACME, Dynamic DNS, HAProxy,
  pfBlockerNG, packages, firmware, and CARP.
- Confirmed, admin-only initiation of pfSense base-system and individual
  package updates through pfSense's native background updater, with fresh
  version checks, restore points, updater locking, and audit records.
- Filter rule and NAT port-forward creation, editing, duplication, deletion,
  ordering, and detailed pfSense field display.
- Filter and NAT separator creation, editing, deletion, colour selection, and
  drag ordering.
- Host, network, and port alias creation and editing, with safe deletion of
  aliases that are not in use.
- pfSense-style staged firewall edits with a pending-change review and one
  explicit Apply Changes action.
- Staged Quick Block rules, confirmed service restarts, and full or
  per-interface state flush actions.
- Single-attempt administrative writes with validation, read-back verification,
  pfSense user attribution, and a protected per-firewall audit trail.
- Four Catppuccin themes, automatic appearance, accent choices, alternate app
  icons, Dynamic Type, and iPad layouts.
