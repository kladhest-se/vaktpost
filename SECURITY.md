# Security

Vaktpost talks to pfSense's built-in XML-RPC service. Read this before pointing
it at a firewall.

## What the credential can do

The account needs the **System - HA node sync** privilege. That privilege is
administrator-equivalent: it exists so one firewall can push configuration to
another, and via `exec_php` it can run arbitrary PHP as root. There is no
narrower privilege that makes XML-RPC work.

So the password stored on the phone is not a scoped, read-only credential. It
opens the webConfigurator, and on most configurations SSH as well. Losing the
phone means changing that password everywhere it is used, not revoking one key.

The password is also sent on every request. XML-RPC has no session and no
token, so HTTP Basic replays it — roughly twice a minute at the default refresh
interval, for as long as the app is open.

**Use a dedicated account**, not your own login. Unlike the REST API, XML-RPC
goes through the webConfigurator's normal authentication path, so LDAP and
RADIUS accounts *do* work here — which makes this more tempting and more
dangerous. A domain password on a phone, replayed twice a minute, is a domain
password you have to change everywhere if the phone is lost. A dedicated local
account still holds administrator-equivalent power, but you can disable it
without affecting anything else.

## How the password is stored

Each firewall password is held in a separate Keychain item using
`WhenUnlockedThisDeviceOnly`. It is unavailable while the device is locked,
does not migrate to a replacement device, and is excluded from backup restore.
Vaktpost does not export credentials or connection profiles.

Opening the firewall editor does not read the password. Revealing a saved
password or replacing one requires a fresh Face ID or Touch ID evaluation with
no passcode fallback. Passwords saved by earlier builds used an
`AfterFirstUnlock` item. Migration copies the exact value into the protected
service, reads the destination back byte-for-byte, and deletes the old item
only after that succeeds. A failed write or verification leaves the original
intact for a later retry.

Removing a firewall, including the logout path, removes both current and
pre-migration Keychain items plus that firewall's encrypted administrative
history. If protected cleanup fails, the profile remains visible and the app
reports the failure so removal can be retried.

## What this app can change

**It can change a firewall.** For most of its life it could not, and this
document said so. That stopped being true when the editor arrived, and the
sentence stayed — which is worse than either state, because the document people
read before pointing this at a production box was describing a different app.

The write surface is exactly nine operations, named in
`PHPSnippet.writeOperations`:

| Operation | What it does |
|---|---|
| `reload_firewall` | `filter_configure_sync()` — reloads the ruleset in place |
| `quick_block` | adds a block rule for one address |
| `delete_rule` | removes one filter rule by tracker |
| `delete_nat_rule` | removes one NAT rule by tracker |
| `save_rule` | replaces or creates one filter rule |
| `save_nat_rule` | replaces or creates one NAT rule |
| `restart_service` | restarts one named service |
| `flush_states` | drops the state table, or one interface's |
| `reorder_filter_rules` | rearranges one interface's rules and separators |

That list was six when it was first written. `readonly.sh` found two more that
were already there, and a ninth — `reorder_filter_rules` — existed in this same
file, fully written and fully tested against real PHP execution, for some time
before anything called it. A write operation nothing can reach is not a
smaller risk than one missing from this table; it is the same omission, the
wrong way round. This table describes what the app can do, not what its
snippet file happens to contain.

There is no NAT equivalent of `reorder_filter_rules`, on purpose. pfSense
assigns no tracker at all to a NAT rule saved through its own web interface —
confirmed against `firewall_nat.php` and `firewall_nat_edit.php`, neither of
which references one — so a reorder keyed on tracker would silently exclude,
and therefore delete, every real NAT rule on a typical firewall. One was
written, found to have exactly that flaw, and removed before it was wired to
anything.

Each operation is called only by `WriteCoordinator`, which serializes the
transaction and binds it to the selected firewall. The coordinator validates
the target, consumes the rate limit, captures pre-state, and commits a pending
audit entry before calling the client. Views do not call mutation methods
directly.

After pfSense accepts a change, the coordinator reads the affected rules,
port forwards, service state, ruleset, or state table back. Exact edits and
deletes must match; reload and state flush operations are marked as read back
because their effect cannot be proven from a stable identity. A transport
failure after sending is recorded and shown as an unknown outcome, never as a
safe retry.

Read-only calls may retry once after a transient transport failure.
Administrative calls use a separate one-attempt transport and are never
automatically resent. This distinction is enforced for all eleven operations by
`vaktpost-tools/tests/lost-response.sh`.

Audit records are separated by firewall and encrypted with AES-GCM. The audit
key is stored in the Keychain as `WhenUnlockedThisDeviceOnly`, and the files
also use complete file protection. Full records remain on the device; exports
omit firewall identity, targets, previews and verification details. A write is
refused if its pending audit entry cannot be saved.

## What stops it changing anything else

The transport can write. Nothing about `exec_php` prevents it. The guarantee
comes instead from the contents of one file,
`Sources/Vaktpost/Net/PHPSnippets.swift`, and from the checks that hold it
there:

- Every snippet is a constant. The parameterised ones build themselves from a
  closed enum, a clamped integer, or a base64 payload, so every line of PHP
  that can reach a firewall is in the repository and has been reviewed.
- A snippet may write **only** if its name is in `writeOperations`, and then
  only through `write_config`, `filter_configure_sync`, `pfctl_clear_states`,
  `pfctl_clear_states_by_if` and `restart_service`. The check runs in both
  directions: a snippet that writes without being named fails, and a name whose
  snippet no longer writes fails too, so the list can neither grow quietly nor
  rot into permissions nothing uses.
- No snippet, including the write ones, may contain `mwexec`, `exec`,
  `shell_exec`, `system`, `passthru`, `popen`, `proc_open`, `unlink`,
  `file_put_contents`, `rename`, `mkdir`, `rmdir`, `chmod`, `chown` or `eval`.
  A write snippet may change the configuration; none may reach a shell.
- `unset` is allowed, because removing an element from a local array is how a
  rule is dropped from a copy before the copy is assigned back. Pointed at
  `$config` it is checked separately and refused.
- Before `write_config()`, write snippets copy pfSense's already-authenticated
  `PHP_AUTH_USER` into the request-local revision context so Configuration
  History records the person instead of `(system)`. The source address remains
  pfSense's observed peer and the provider label comes from pfSense's own auth
  configuration; none of these values comes from an app payload, and Vaktpost
  does not start or persist a webConfigurator session.

### Values never become code

This is the part worth reading twice, because it was wrong until recently.

The write snippets used to interpolate their arguments directly into PHP
source. A rule's description went into the middle of a double-quoted PHP
string; three of the optional fields were assembled as *fragments of PHP*, so
the snippet's own shape depended on the values it carried. A description
containing a double quote ended that string. A description containing the right
quote, a semicolon and a call ran on the firewall, as root, typed into a text
field in the editor.

Arguments now cross as one base64 payload, decoded on the other side with
`json_decode(base64_decode(...), true)`. Base64's alphabet is `A-Z a-z 0-9 + /
=`, none of which can terminate a PHP string literal, so the snippet text is
fixed no matter what anybody types. Escaping was the obvious alternative and is
the wrong one: it has to be right every time, in a language whose string rules
differ from Swift's, and getting it wrong looks like working code.
- Every PHP function called must appear on the allowlist in that file.
- `pfsense.exec_php` is the only XML-RPC method used. pfSense also exposes
  `restore_config_section` and `merge_config_section`, which write.
- Three snippets call pfSense functions that shell out internally —
  `wg_get_status()` runs `wg show`, `get_pkg_info()` runs pkg, and
  `printBandwidth()` runs `/usr/local/bin/rate`. That is deliberate and worth
  stating: the rules forbid *this app* from sending `exec`, `mwexec` or a
  shell, not pfSense from using one inside its own functions. What the rules
  protect is that every line of PHP this app sends is reviewable, and that only
  the named operations write, which holds for all three.
- `printBandwidth()` deserves its own paragraph, because it is the weakest
  entry on the allowlist and the only one that is not a value read. It is how
  `status_graph.php` fills its Host IP table, and there is no other source of
  per-host rates on pfSense — there is no counter to read, so the firewall
  takes a one-second packet capture to answer. Three things bound it. The
  branch this app reaches only reads; the branch that kills processes and
  unlinks logs is reachable only through a `mode` argument the snippet never
  passes, and `Tests/VaktpostTests/HostTrafficTests.swift` asserts it stays
  empty. The interface is chosen by an index clamped to 0...63 into pfSense's
  own interface list, so no runtime string reaches the PHP. And it runs only
  while a screen asking for it is open, never on the refresh timer.

  It is still a process spawn rather than a counter read, and it is the
  heaviest thing this app asks of a firewall. Anybody weighing whether to run
  Vaktpost against a production box should know that opening its traffic
  screens makes pfSense capture packets for a second at a time, on an interval
  the person chooses, for as long as the screen is open.
- No snippet copies a secret. `wg_get_status()` returns the private key of
  every WireGuard tunnel and the preshared key of every peer alongside the
  status the app wants; snippets copy the fields they need by name and never
  return a structure whole. Checked, and checked again on the output of
  `check-snippets.sh --save`, which writes payloads to disk.
- The three snippets taking parameters are constrained at the source. The log
  reader draws its path from a closed enum and clamps its line count; the RRD
  reader renders a span from an enum as an integer; the host-traffic sampler
  takes two closed enums and an index clamped to 0...63. Nothing a person types
  reaches PHP.

`vaktpost-tools/tests/write-boundary.sh` enforces all of it and runs before every
publish. `Tests/VaktpostTests/XMLRPCTests.swift` covers the same rules in Xcode.
`vaktpost-tools/tests/write-coordinator.sh` separately fails if any view calls a
mutation directly or if the coordinator no longer follows pre-state → pending
audit → execution → read-back → completed audit ordering.
`vaktpost-tools/tests/credential-lifecycle.sh` fails if password accessibility,
copy/verify/delete migration, biometric reveal/replacement, or removal cleanup
regresses.

## How this compares to the REST build

Weaker, and worth being plain about.

The REST build was **read-only, structurally**. The client contained no `POST`,
`PUT`, `PATCH` or `DELETE`; adding a write meant inventing a method that did not
exist, and a grep could prove its absence. The pfSense REST package also has its
own **Read Only** setting, which enforced it at the firewall where no change to
this app could undo it.

This build **is not read-only**, and the comparison has to start there rather
than with how the difference is checked. It can delete a firewall rule. What it
offers instead is an **enumerated** surface: eleven operations, named in one
file, each one a line somebody had to add on purpose, with a check that fails if
a twelfth appears or if one of the eleven quietly stops being used.

Every newly added or migrated firewall nevertheless starts in **monitor-only
mode**. The client rejects all eleven mutation methods before transport in that
mode. Enabling administration is stored per firewall and requires an explicit
risk acknowledgement, but no Face ID or Touch ID evaluation. Biometric checks
remain in place for revealing or replacing a stored password and for the
optional whole-app lock.
This is an application safety boundary, not a reduction in the credential's
pfSense privileges.

That is a meaningfully weaker promise in two directions. A maintainer who edits
the snippet and the manifest together has defeated it. And an enumerated write
surface is still a write surface — the credential this app holds is
administrator-equivalent either way, so the question a reader should ask is not
"can it write" but "do I want a phone in my pocket that can".

What you get for it: RRD-backed history, system notices, per-filesystem usage,
real mbuf figures, dynamic DNS, and anything a package writes to disk. None of
that is reachable over the REST API.

If you do not need those, the REST transport is the better security posture and
this project's history has it.

## TLS

pfSense ships a self-signed certificate. Pin it — connect once, then use **Pin
last seen certificate** in the firewall's settings. After that the connection is
accepted only if that exact certificate is presented. Accepting untrusted TLS
without a pin means anything on the path can offer its own certificate and read
an administrator password out of the first request.

## Reporting

Open an issue, or for anything you would rather not file publicly, contact the
maintainer directly.
