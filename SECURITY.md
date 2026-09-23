# Security

Vaktpost talks to pfSense's built-in XML-RPC service. Read this before pointing
it at a production firewall.

## The credential is administrator-equivalent

XML-RPC needs the **System - HA node sync** privilege, and there is no narrower
one that works. It exists so one firewall can push configuration to another,
and through `exec_php` it can run PHP as root. The password on the phone is
therefore not a scoped, read-only key: it opens the webConfigurator, and on
most configurations SSH as well.

The password is also replayed on every request, because XML-RPC has no session
or token — roughly twice a minute at the default refresh interval.

**Use a dedicated local account.** LDAP and RADIUS accounts do work here, which
makes reusing your own login tempting; a domain password replayed from a phone
is one you must change everywhere if the phone is lost. A dedicated account
still holds administrator-equivalent power, but you can disable it on its own.

## How the password is stored

Each firewall's password is a separate Keychain item with
`WhenUnlockedThisDeviceOnly`: unavailable while the device is locked, and it
does not migrate to another device. Opening the firewall editor does not read
it. With the optional Face ID or Touch ID lock enabled, revealing or replacing
a saved password needs a fresh biometric check with no passcode fallback.

Removing a firewall deletes its password and its encrypted history. If that
cleanup fails, the firewall stays visible and the failure is reported, so it
can be retried rather than silently left behind.

A refused sign-in stops automatic refreshing until you change the settings or
retry by hand, so repeated failures don't trip pfSense's login protection.

## What it can change

Seventeen operations, named in `PHPSnippet.writeOperations`:

| Area | Operations |
| --- | --- |
| Filter rules | `save_rule`, `delete_rule`, `reorder_filter_rules` |
| NAT port forwards | `save_nat_rule`, `delete_nat_rule`, `reorder_nat_rules` |
| Separators | `save_filter_separator`, `delete_filter_separator`, `save_nat_separator`, `delete_nat_separator` |
| Aliases | `save_alias`, `delete_alias` |
| Immediate actions | `reload_firewall`, `restart_service`, `flush_states`, `quick_block` |
| Updates | `start_update` |

Every one of them goes through `WriteCoordinator`, never a view directly. It
binds the change to the selected firewall, consumes a rate limit, captures the
pre-state and commits a pending audit entry before anything is sent. Afterwards
it reads the change back: exact edits and deletes must match. A lost response
is recorded as an unknown outcome and never resent, and administrative calls
use a one-attempt transport, unlike reads, which may retry once.

Audit records are per firewall, encrypted with AES-GCM under a Keychain key
with the same protection as the passwords. A write is refused if its pending
audit entry cannot be saved.

## What stops it changing anything else

`exec_php` runs whatever it is given, so the boundary is one file,
`Sources/Vaktpost/Net/PHPSnippets.swift`, and the checks that hold it there:

- **Every snippet is a constant.** Nothing builds PHP at runtime, so every line
  that can reach a firewall is in the repository and has been reviewed.
- **Values never become code.** Arguments cross as one base64 payload, decoded
  with `json_decode(base64_decode(...), true)`. Base64's alphabet cannot end a
  PHP string, so no description or address can change the shape of a snippet.
  Escaping would have to be right every time; this does not.
- **Only named operations write,** and only through an allowlist per operation:
  `write_config`, `filter_configure_sync`, `pfctl_clear_states`,
  `pfctl_clear_states_by_if` and `restart_service`. The check runs both ways, so
  the list can neither grow quietly nor rot.
- **No shells.** `mwexec`, `exec`, `shell_exec`, `system`, `eval`,
  `file_put_contents` and similar are refused everywhere except `start_update`,
  which may launch only pfSense's own updater, with fixed flags and a validated
  package name, after creating a restore point.
- **No secrets are copied.** `wg_get_status()` returns WireGuard private and
  preshared keys alongside the status; snippets copy fields by name and never
  return a structure whole.
- **Parameters come from closed sets.** Log paths from an enum with a clamped
  line count, RRD spans from an enum, the host-traffic sampler from two enums
  and an index clamped to 0...63.
- **Only `pfsense.exec_php` is used.** pfSense also exposes
  `restore_config_section` and `merge_config_section`, which write.

One read deserves naming: per-host traffic uses pfSense's `printBandwidth()`,
which takes a one-second packet capture, because no counter for it exists. It
runs only while a traffic screen is open, never on the refresh timer, and the
branch that kills processes is unreachable from here. It is still the heaviest
thing this app asks of a firewall.

`vaktpost-tools` enforces all of it before every publish: `write-boundary.sh`
for the rules above, `write-coordinator.sh` for the ordering and for views
calling mutations directly, `lost-response.sh` for the single-attempt rule, and
`credential-lifecycle.sh` for password handling.

## TLS

HTTPS only; plain HTTP is refused. pfSense's default certificate is
self-signed, so on the first connection Vaktpost shows its SHA-256 fingerprint
for you to compare with **System → Certificates** and pin. After that only that
certificate is accepted, and a changed one blocks the connection until you
review and re-pin it in the firewall's settings.

## Reporting

Open an issue, or for anything you would rather not file publicly, contact the
maintainer directly.
