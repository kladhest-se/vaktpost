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

## What stops the app writing

The transport can write. Nothing about `exec_php` prevents it. The guarantee
comes instead from the contents of one file,
`Sources/Vaktpost/Net/PHPSnippets.swift`, and from the checks that hold it
there:

- Every snippet is a `static let` constant. None is assembled at runtime, so
  every line of PHP that can reach a firewall is in the repository and has been
  reviewed.
- No snippet may contain `write_config`, `mwexec`, `exec`, `shell_exec`,
  `system`, `passthru`, `popen`, `proc_open`, `unlink`, `file_put_contents`,
  `rename`, `mkdir`, `rmdir`, `chmod`, `chown` or `eval`.
- Every PHP function called must appear on the allowlist in that file.
- `pfsense.exec_php` is the only XML-RPC method used. pfSense also exposes
  `restore_config_section` and `merge_config_section`, which write.
- Two snippets call pfSense functions that shell out internally —
  `wg_get_status()` runs `wg show`, `get_pkg_info()` runs pkg. That is
  deliberate and worth stating: the rules forbid *this app* from sending
  `exec`, `mwexec` or a shell, not pfSense from using one inside its own
  functions. What the rules protect is that every line of PHP this app sends is
  reviewable and cannot write, which holds for both.
- No snippet copies a secret. `wg_get_status()` returns the private key of
  every WireGuard tunnel and the preshared key of every peer alongside the
  status the app wants; snippets copy the fields they need by name and never
  return a structure whole. Checked, and checked again on the output of
  `check-snippets.sh --save`, which writes payloads to disk.
- The one snippet taking parameters — the log reader — draws its path from a
  closed enum and clamps its line count. Nothing a person types reaches PHP.

`vaktpost-tools/tests/readonly.sh` enforces all of it and runs before every
publish. `Tests/VaktpostTests/XMLRPCTests.swift` covers the same rules in Xcode.

## How this compares to the REST build

Weaker, and worth being plain about.

The REST build's read-only claim was **structural**. The client contained no
`POST`, `PUT`, `PATCH` or `DELETE`; adding a write meant inventing a method that
did not exist, and a grep could prove its absence. The pfSense REST package also
has its own **Read Only** setting, which enforced it at the firewall where no
change to this app could undo it.

This build's claim is an **allowlist**. Adding a write means adding a line to a
file — the check will fail and the publish will stop, but a maintainer who
edits both has defeated it. That is a meaningfully different promise.

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
