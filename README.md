# Vaktpost

Vaktpost is an open-source iPhone and iPad app for monitoring and carefully
administering **pfSense CE and pfSense Plus**. It talks to pfSense's built-in
XML-RPC service, so nothing is installed on the firewall.

*Vaktpost* is Swedish for a sentry post: somewhere you watch the perimeter
from, report what you see, and take a small set of deliberate actions.

> **Status:** preparing the first public release, **1.0.0**. The feature set
> below is frozen while compatibility, safety and accessibility are finished.

> **Before you connect a production firewall,** read [SECURITY.md](SECURITY.md).
> Vaktpost's account needs the **System - HA node sync** privilege, which is
> administrator-equivalent.

## Features

### Monitoring

- Multiple firewalls, each with its own credential, certificate pin and
  refresh interval.
- A configurable overview of health, interfaces, gateways, resources,
  services, VPNs, logs and clients.
- One searchable client list from DHCP leases, ARP and static mappings, with
  offline vendor lookup.
- Live throughput and RRD-backed traffic history.
- OpenVPN, WireGuard and IPsec status with connected peers.
- Filter, system, authentication, DHCP and OpenVPN logs, live log following,
  and a combined incident timeline.
- On-device alerts for gateways, services, capacity, certificates, CARP, VPNs,
  updates and Dynamic DNS.
- Notices, certificates, ACME, Dynamic DNS, HAProxy, pfBlockerNG, packages and
  firmware.
- Network Tools: ping, traceroute, DNS lookup and a speed test run from the
  firewall itself, plus traffic investigation.
- Download of the firewall's `config.xml`.

### Administration

Every firewall starts in **monitor-only mode**. With administration enabled:

- Filter rules and NAT port forwards: create, edit, duplicate, delete and
  reorder.
- Filter and NAT separators, and host, network and port aliases.
- Quick Block, and new rules prefilled from a firewall-log entry.
- Service restart and state-table flush.
- pfSense base-system and installed-package updates.

### Not included

Vaktpost complements the pfSense WebUI rather than replacing it. Out of scope
for 1.0:

- Outbound NAT, 1:1 NAT, virtual IPs, schedules, traffic shaping and package
  settings.
- Installing or removing packages, restoring a configuration, and CARP
  synchronization.
- Bulk editing, templates, automation and unattended changes.
- Any Vaktpost server, cloud account or remote-access relay.

## Safety model

- **Staged changes.** Rule, NAT, separator and alias edits use pfSense's own
  pending-changes workflow and go live only after **Apply Changes**. That
  applies *every* pending change on the firewall, including ones made in the
  WebUI, so Vaktpost shows what is pending first.
- **Confirmed actions.** Restarts, state flushes and updates each need their
  own confirmation.
- **Sent once, then verified.** Every change is sent a single time and read
  back. If the response is lost, the outcome is reported as unknown and never
  retried automatically.
- **Recorded.** Changes appear in pfSense's configuration history, marked
  `Vaktpost:`, and in an on-device audit trail.
- **Declared surface.** Everything Vaktpost can change on a firewall is listed
  in one place, `PHPSnippet.writeOperations`.

## Accessibility

Text scales with Dynamic Type, status is never carried by colour alone,
icon-only controls are labelled for VoiceOver, and every animation is skipped
when Reduce Motion is on.

## Privacy

Vaktpost has no accounts, analytics, advertising or tracking, and talks to no
server other than the firewalls you add. Passwords are kept in the Keychain on
this device only. The optional speed test is run by the firewall itself
against Cloudflare's speed-test service. Read the full
[privacy policy](https://vaktpost.kladhest.se/privacy.php).

## Firewall setup

1. In **System → Advanced → Admin Access**, set **Max Processes** to at least
   5. XML-RPC shares PHP workers with the WebUI.
2. Under **System → User Manager**, create a dedicated local user. Don't reuse
   a personal or domain account.
3. Give that user the **System - HA node sync** privilege.
4. In Vaktpost, add the firewall's address, username and password.
5. Trust the certificate. pfSense's default certificate is self-signed, so on
   the first connection Vaktpost shows its SHA-256 fingerprint. Compare it
   with **System → Certificates** in the WebUI, then pin it. From then on only
   that certificate is accepted; a different one is blocked until you review
   it in the firewall's settings.
6. Leave monitor-only mode on unless you need administration.

Vaktpost asks for **local network** access the first time it connects to a
firewall on your network. Without it, local firewalls are unreachable.

### Try it without a firewall

The [project website](https://vaktpost.kladhest.se) hosts a synthetic firewall
for testing. Add `https://vaktpost.kladhest.se` as the firewall address, with
`review` as the username and `vaktpost-demo` as the password. The
[XMLAPI Lab](https://vaktpost.kladhest.se/lab.php) page lists the other
scenarios. To host it yourself, serve `public-web/` over HTTPS; see
[public-web/README.md](public-web/README.md).

## Requirements

- iOS or iPadOS 17 or later
- pfSense CE or pfSense Plus with the WebUI reachable over HTTPS

## Building from source

Requires Xcode 15 or later and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```sh
brew install xcodegen
make build
```

| Command | Does |
| --- | --- |
| `make` | List all commands |
| `make build` | Compile without starting a simulator |
| `make test` | Run the tests on a simulator |
| `make ios-run` / `make ipados-run` | Run on an iPhone or iPad simulator |
| `make install DEVICE=… TEAM_ID=…` | Install on a connected device |
| `make archive TEAM_ID=…` | Build an App Store archive |
| `make web` | Serve the website on port 8000 |

`make devices`, `make teams` and `make destinations` list the values those
commands need. Run `make set-team TEAM_ID=…` once to store your team in the
untracked `local.mk`, after which the signing commands need no argument. The Xcode project is generated from `project.yml` and
`Config/*.xcconfig`, and is not committed.

### Project layout

```text
Config/        build settings and release version
Resources/     Info.plist, privacy manifest, icons, OUI database
Sources/       the app: App, Core, Models, Net, Store, Theme, Views
Tests/         unit and transport tests
docs/          contribution terms, release and design notes
public-web/    the project website and test lab
```

## Contributing

See [docs/CONTRIBUTING.md](docs/CONTRIBUTING.md). Security problems are
covered in [SECURITY.md](SECURITY.md).

## Licence

Vaktpost is free software under the GNU General Public License, version 3 or
(at your option) any later version — see [LICENSE](LICENSE). An
[additional permission](docs/APP_STORE_EXCEPTION.md) allows distribution
through Apple's App Store, Mac App Store and TestFlight.

Vaktpost is not affiliated with Netgate or the Catppuccin project. pfSense is a
trademark of Netgate. Catppuccin palettes are used under their MIT licence.
