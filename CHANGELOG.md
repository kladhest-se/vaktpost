# Changelog

## Unreleased

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
