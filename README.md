# Vaktpost

Vaktpost is an open-source iPhone and iPad app for monitoring and carefully
administering **pfSense CE and pfSense Plus**. It talks to pfSense's built-in
XML-RPC service, so nothing is installed on the firewall.

*Vaktpost* is Swedish for a sentry post: somewhere you watch the perimeter
from, report what you see, and take a small set of deliberate actions.

> **Status:** preparing the first public release, **1.0.0**.

> **Before you connect a production firewall,** read [SECURITY.md](SECURITY.md).
> Vaktpost's account needs the **System - HA node sync** privilege, which is
> administrator-equivalent.

## Monitoring

- Several firewalls, each with its own credential, certificate pin and refresh
  interval.
- A configurable overview of health, interfaces, gateways, resources, services,
  VPNs, logs and clients.
- One searchable client list from DHCP leases, ARP and static mappings, with
  offline vendor lookup and live traffic per device.
- Live throughput and RRD-backed traffic history.
- OpenVPN, WireGuard and IPsec status with connected peers.
- Filter, system, authentication, DHCP and OpenVPN logs, live log following,
  and a combined incident timeline.
- The overview's blocked, rejected and passed counts open the log they count,
  and a log entry opens the rule that decided it.
- A client's matching log entries open the log entry behind them.
- Starred interfaces and gateways choose what the overview shows.
- On-device alerts for gateways, services, capacity, certificates, CARP, VPNs,
  updates and Dynamic DNS. The certificate alert also schedules expiry
  warnings, which arrive whether or not the app is open.
- Notices, certificates, ACME, Dynamic DNS, HAProxy, pfBlockerNG, packages and
  firmware.
- Network Tools: ping, traceroute, DNS lookup and a speed test run from the
  firewall itself. Investigate searches rules, aliases, leases and logs for one
  address, and each result opens the rule, alias, port forward or client it
  found.

## Administration

Every firewall starts in **monitor-only mode**. With administration enabled:

- Filter rules and NAT port forwards: create, edit, duplicate, delete and
  reorder.
- Filter and NAT separators, and host, network, port and URL-table aliases.
- Quick Block, prefilled from wherever it was opened, and new rules prefilled
  from a firewall-log entry.
- Service restart and state-table flush.
- pfSense base-system and installed-package updates.

Changes are staged and go live only after **Apply Changes**, which shows what
is pending first. Restarts, flushes and updates are confirmed individually.
Every change is sent once and read back; a lost response is reported as an
unknown outcome and never retried. Changes appear in pfSense's configuration
history, marked `Vaktpost:`, and in an encrypted on-device audit trail.
Everything Vaktpost can change is listed in one place,
`PHPSnippet.writeOperations`.

## Privacy and accessibility

No accounts, analytics, advertising or tracking. Vaktpost talks to no server
other than the firewalls you add, and passwords stay in the Keychain on your
device. The optional speed test is run by the firewall, against Cloudflare's
speed-test service. The full
[privacy policy](https://vaktpost.kladhest.se/privacy.php) is on the website.

Text scales with Dynamic Type, status is never carried by colour alone,
controls are labelled for VoiceOver, and animations are skipped under Reduce
Motion.

## Setup

1. In **System → Advanced → Admin Access**, set **Max Processes** to at least
   5. XML-RPC shares PHP workers with the WebUI.
2. Under **System → User Manager**, create a dedicated local user — not your
   own login — and give it the **System - HA node sync** privilege.
3. In Vaktpost, add the firewall's address, username and password. Allow
   **local network** access when asked, or a firewall on your own network
   cannot be reached.
4. Trust the certificate. pfSense's default one is self-signed, so Vaktpost
   shows its SHA-256 fingerprint on first connection: compare it with
   **System → Certificates**, then pin it. A different certificate is blocked
   until you review it.
5. Leave monitor-only mode on unless you need administration.

### Try it without a firewall

The [project website](https://vaktpost.kladhest.se) hosts a synthetic firewall.
Add `https://vaktpost.kladhest.se` as the address, with `review` as the
username and `vaktpost-demo` as the password; the
[XMLAPI Lab](https://vaktpost.kladhest.se/lab.php) page lists the other
scenarios.

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
| `make lint` / `make test` | Lint, or run the tests on a simulator |
| `make ios-run` / `make ipados-run` | Run on an iPhone or iPad simulator |
| `make install DEVICE=… TEAM_ID=…` | Install on a connected device |
| `make archive TEAM_ID=…` | Build an App Store archive |
| `make web` | Serve the website on port 8000 |

`make devices`, `make teams` and `make destinations` list the values those
commands need; `make set-team TEAM_ID=…` stores your team once in the untracked
`local.mk`. The Xcode project is generated from `project.yml` and
`Config/*.xcconfig`, and is not committed.

```text
Config/        build settings and release version
Resources/     Info.plist, privacy manifest, icons, OUI database
Sources/       the app: App, Core, Models, Net, Store, Theme, Views
Tests/         unit and transport tests
docs/          contribution terms, release and design notes
public-web/    the project website and test lab
```

## Contributing

See [docs/CONTRIBUTING.md](docs/CONTRIBUTING.md), and
[AGENTS.md](AGENTS.md) if the contributor is automated. Security problems are covered
in [SECURITY.md](SECURITY.md).

## Licence

Free software under the GNU General Public License, version 3 or (at your
option) any later version — see [LICENSE](LICENSE). An
[additional permission](docs/APP_STORE_EXCEPTION.md) allows distribution
through Apple's App Store, Mac App Store and TestFlight.

Vaktpost is not affiliated with Netgate or the Catppuccin project. pfSense is a
trademark of Netgate. Catppuccin palettes are used under their MIT licence.
