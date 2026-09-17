# Changelog

All notable changes to Vaktpost are listed here. Versions follow
[Semantic Versioning](https://semver.org/).

## 1.0.0 — Unreleased

First public release.

### Monitoring

- Multiple pfSense CE and pfSense Plus firewalls, each with its own credential,
  certificate pin and refresh interval.
- A configurable overview of health, interfaces, gateways, resources, services,
  VPNs, logs and clients, with local history.
- One searchable client list built from DHCP leases, ARP and static mappings,
  with offline vendor lookup and live traffic per device.
- Interface throughput and RRD-backed traffic history.
- OpenVPN, WireGuard and IPsec status with connected peers.
- Filter, system, authentication, DHCP and OpenVPN logs, live firewall-log
  following, and a combined incident timeline.
- On-device alerts for gateways, services, capacity, certificates, CARP, VPNs,
  updates and Dynamic DNS.
- System notices, certificates, ACME, Dynamic DNS, HAProxy, pfBlockerNG,
  package and firmware status.
- Ping, traceroute, DNS lookup, a speed test and traffic investigation.
- Download of the firewall's configuration file.

### Administration

- Monitor-only by default; administration is enabled per firewall.
- Filter rules and NAT port forwards: create, edit, duplicate, delete and
  reorder.
- Filter and NAT separators, and host, network and port aliases.
- Changes are staged and take effect only after Apply Changes, with a review of
  pending edits first.
- Quick Block, and new rules prefilled from a firewall-log entry.
- Service restart and state-table flush, each separately confirmed.
- pfSense base-system and package updates.
- Every change is sent once, verified by reading it back, and recorded in
  pfSense's configuration history and an on-device audit trail.

### Security and privacy

- Passwords stored in the Keychain, available only on this device.
- Certificate pinning with an explicit trust decision for self-signed
  certificates; a changed certificate is blocked until reviewed.
- Face ID or Touch ID lock.
- No accounts, analytics, tracking or third-party services.

### Platforms and design

- iPhone and iPad, with split-view layouts on iPad.
- Apple Silicon Macs, as a Designed for iPad app with a ⌘R refresh command.
- All four Catppuccin flavours, accent colours and alternate app icons.
- Dynamic Type, and status never shown by colour alone.

### Licence

- Free software under `GPL-3.0-or-later`, with an additional permission for
  distribution through Apple's stores.
