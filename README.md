# Vaktpost

Vaktpost is an open-source iOS app for monitoring and carefully administering
**pfSense CE and pfSense Plus**. It is built with SwiftUI, requires iOS 17 or
later, and uses pfSense's built-in XML-RPC service; nothing is installed on the
firewall.

*Vaktpost* is Swedish for a sentry post: somewhere you watch the perimeter
from, report what you see, and take a small set of deliberate actions.

> Vaktpost is preparing its first public release, version **0.1.0**. The feature
> set below is frozen while compatibility, safety, accessibility, and release
> quality are finished.

Read [SECURITY.md](SECURITY.md) before connecting it to a production firewall.
The XML-RPC account needs the **System - HA node sync** privilege, which is
administrator-equivalent.

## Version 0.1 scope

### Monitoring

- Multiple firewalls, each with separate credentials, TLS settings, refresh
  interval, and monitoring history.
- A configurable overview of health, interfaces, gateways, system resources,
  services, VPNs, logs, and clients.
- DHCP leases, ARP entries, and static mappings combined into one searchable
  client list with offline MAC-vendor lookup.
- Interface counters, live throughput, and RRD-backed history where pfSense
  exposes it.
- OpenVPN, WireGuard, and IPsec status with connected peers.
- Filter, system, authentication, DHCP, and OpenVPN logs, plus a combined
  incident timeline.
- Alerts derived on the phone for gateway, service, capacity, certificate,
  CARP, VPN, update, and Dynamic DNS conditions.
- System notices, certificates, ACME, Dynamic DNS, HAProxy, pfBlockerNG,
  package status, and firmware status.
- Ping, traceroute, DNS lookup, traffic investigation, and configuration
  diagnostics.

### Administration

- Monitor-only mode by default, enabled separately for each firewall.
- Create, edit, duplicate, delete, and reorder filter rules and NAT port
  forwards.
- Create, edit, delete, colour, and reorder filter and NAT separators.
- Create and edit host, network, and port aliases; delete unused aliases.
- pfSense-style staged changes: edits are saved first and become active only
  after **Apply Changes**.
- A review of identifiable Vaktpost edits before applying the firewall's global
  pending ruleset.
- Quick Block as a staged filter rule; service restart and state-table flush as
  separately confirmed immediate actions.
- Single-attempt writes, read-back verification, pfSense Configuration History
  attribution, and a protected per-firewall audit trail.

### Deliberately deferred

Version 0.1 does not aim to replace the entire pfSense WebUI. The following are
out of scope for the first release:

- Outbound NAT, 1:1 NAT, virtual IP, schedule, traffic-shaper, and package
  configuration editors.
- Firmware or package installation, configuration backup/restore, and CARP
  synchronization controls.
- Bulk rule editing, templates, automation, and unattended writes.
- A server-side Vaktpost component, cloud account, or remote-access relay.

Until 0.1 ships, new features should be accepted only when they are needed to
make the scope above safe, understandable, or compatible with supported
pfSense versions.

## Safety model

Every firewall starts in monitor-only mode. When administration is enabled,
all mutations pass through one coordinator that validates the operation,
records a pending audit entry, sends the request once, and reads the affected
state back. A lost response is reported as an unknown outcome and is never
automatically repeated.

Filter, NAT, separator, and alias edits use pfSense's native pending markers.
The live ruleset changes only when an administrator opens **Apply firewall
changes** and selects **Apply Changes**. That applies every pending firewall
change on the appliance, including changes made in the WebUI or by another
administrator.

Passwords are stored in separate `WhenUnlockedThisDeviceOnly` Keychain items.
TLS certificate pinning is available and strongly recommended. The complete
mutation surface is declared in `PHPSnippet.writeOperations` and audited by the
companion test suite.

## Firewall setup

1. In **System → Advanced → Admin Access**, set **Max Processes** to at least 5.
   XML-RPC polling shares PHP workers with the WebUI.
2. Create a dedicated local user under **System → User Manager**. Avoid reusing
   a personal or domain account.
3. Grant **System - HA node sync**. This privilege is required by XML-RPC and is
   administrator-equivalent.
4. Add the firewall address, username, and password in Vaktpost.
5. Connect once, then select **Pin last seen certificate** in the firewall
   settings. Re-pin after intentionally replacing the certificate.
6. Leave monitor-only mode enabled unless administration is needed.

Administrative revisions retain `Vaktpost:` in their description and use the
already-authenticated XML-RPC identity for pfSense Configuration History.
Vaktpost never accepts an audit username from an operation payload.

## Build

Requirements:

- Xcode 15 or later
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)
- iOS 17 or later

```sh
brew install xcodegen
make build
```

Common targets:

```sh
make                 # list available commands
make build           # compile without starting a simulator
make test            # run tests on an installed iOS simulator
make run             # build and launch on a simulator
make open            # generate and open the Xcode project
make archive TEAM_ID=ABCDE12345
make install DEVICE=00008132-… TEAM_ID=ABCDE12345
make web             # serve public-web/ on port 8000
```

Use `make devices`, `make teams`, and `make destinations` to discover the
values needed for device builds. The generated `.xcodeproj` and the local
`build.number` counter are intentionally not committed; `project.yml` and
`Config/*.xcconfig` are the sources of truth.

## Verification and publishing

The private companion repository `vaktpost-tools` contains structural,
transport, security-boundary, and disposable-firewall compatibility checks.
It is expected beside this repository:

```sh
cd ../vaktpost-tools
./tests/run.sh --fast
./publish-all.sh --dry-run
```

The destructive CE/Plus compatibility matrix is documented in
[`docs/LAB_COMPATIBILITY_MATRIX.md`](docs/LAB_COMPATIBILITY_MATRIX.md). Run it
only against a disposable firewall.

## Project layout

```text
Config/                    build settings and release version
Resources/                 app metadata, icons, entitlements, OUI database
Sources/Vaktpost/App/      app entry point and navigation
Sources/Vaktpost/Core/     profiles, validation, audit, write coordination
Sources/Vaktpost/Models/   decoded pfSense state
Sources/Vaktpost/Net/      XML-RPC transport and reviewed PHP snippets
Sources/Vaktpost/Store/    dashboard state, refresh, history, alerts
Sources/Vaktpost/Theme/    Catppuccin themes and shared components
Sources/Vaktpost/Views/    SwiftUI screens
Tests/VaktpostTests/       unit and transport tests
public-web/                dependency-free PHP public website
```

## Design and accessibility

Vaktpost includes all four Catppuccin flavours, automatic light/dark mode,
accent choices, and alternate app icons. Status is not communicated by colour
alone, text follows Dynamic Type, and iPad uses a split-view layout where it
improves navigation.

## Website

`public-web/` is a dependency-free PHP site. Serve it with `make web` or point
a PHP-capable web server at the directory. See
[public-web/README.md](public-web/README.md).

## License and trademarks

Vaktpost is not affiliated with Netgate or the Catppuccin project. pfSense is
a trademark of Netgate. Catppuccin palettes are used under their MIT licence;
the application code and design are original to this project.
