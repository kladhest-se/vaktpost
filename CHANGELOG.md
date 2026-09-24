# Changelog

All notable changes to Vaktpost are listed here. Versions follow
[Semantic Versioning](https://semver.org/).

## 1.0.0 — Unreleased

First public release, for iPhone and iPad.

### Monitoring

- Several pfSense CE and pfSense Plus firewalls, each with its own credential,
  certificate pin and refresh interval.
- A configurable overview of health, interfaces, gateways, resources, services,
  VPNs, logs and clients, with local history.
- One searchable client list from DHCP leases, ARP and static mappings, with
  offline vendor lookup and live traffic per device.
- Interface throughput and RRD-backed traffic history.
- OpenVPN, WireGuard and IPsec status with connected peers.
- Filter, system, authentication, DHCP and OpenVPN logs, live firewall-log
  following, and a combined incident timeline.
- The overview's blocked, rejected and passed counts open the log they count,
  and a log entry opens the rule that decided it.
- A client's matching log entries open the log entry behind them.
- Starred interfaces and gateways choose what the overview shows.
- Alerts for gateways, services, capacity, certificates, CARP, VPNs, updates
  and Dynamic DNS. The certificate alert also schedules expiry warnings, which
  arrive whether or not the app is open.
- System notices, certificates, ACME, Dynamic DNS, HAProxy, pfBlockerNG,
  package and firmware status.
- Network Tools: ping, traceroute, DNS lookup and a speed test, plus
  Investigate for searching everything that references one address, with each
  result opening what it found.

### Administration

- Monitor-only by default; administration is enabled per firewall.
- Filter rules and NAT port forwards: create, edit, duplicate, delete and
  reorder.
- Filter and NAT separators, and host, network, port and URL-table aliases,
  where the firewall fetches the list itself on the interval you set.
- Quick Block, prefilled from wherever it was opened, and new rules prefilled
  from a firewall-log entry.
- Service restart and state-table flush, each separately confirmed.
- pfSense base-system and package updates.
- Changes are staged and take effect only after Apply Changes, which reviews
  what is pending first.
- Every change is sent once, verified by reading it back, and recorded in
  pfSense's configuration history and an encrypted on-device audit trail.

### Security and privacy

- Passwords stored in the Keychain, available only on this device, with an
  optional Face ID or Touch ID lock.
- Certificate pinning with an explicit trust decision for self-signed
  certificates; a changed certificate is blocked until reviewed.
- Sign-in failures say whether the password was wrong or the account lacks the
  required privilege, and are not retried automatically.
- No accounts, analytics, tracking or third-party services.

### Design

- iPhone and iPad, with split-view layouts on iPad.
- All four Catppuccin flavours, accent colours and alternate app icons.
- Dynamic Type, status never shown by colour alone, VoiceOver labels, and
  animations that honour Reduce Motion.

### Licence

- Free software under `GPL-3.0-or-later`, with an additional permission for
  distribution through Apple's stores.
