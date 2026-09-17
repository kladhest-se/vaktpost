# Disposable pfSense compatibility matrix

Vaktpost's administrative PHP uses pfSense internals, not a versioned API.
Every supported CE and Plus release therefore needs an end-to-end check on a
disposable VM before the app claims compatibility.

## Safety boundary

This matrix reloads the firewall, restarts a service, adds and edits a filter
rule, creates a disabled port forward, flushes an interface's state table, and
deletes the temporary objects. It must never be aimed at production.

## Coverage

The runner exercises eight of the seventeen declared write snippets:
`reload_firewall`, `restart_service`, `quick_block`, `flush_states`,
`save_rule`, `save_nat_rule`, `delete_rule` and `delete_nat_rule`.

Rule and NAT reordering, filter and NAT separators, aliases and
`start_update` are **not yet lab-tested**. They are listed in
`NOT_YET_IN_MATRIX` in `bin/admin-matrix.py`, printed on every dry run, and
`tests/admin-matrix.sh` fails if a declared write is in neither list. Until
they move into the matrix, compatibility for those operations rests on
`write-contract` and manual testing only.

Use a newly restored VM snapshot with no clients behind it. Keep the pfSense
console open. The runner requires all of the following before it reads a
password or opens a connection:

- an HTTPS base URL;
- `--edition CE` or `--edition Plus` plus the exact displayed version;
- a lab interface and a service that may be restarted;
- `--confirm-disposable-lab` matching the URL hostname exactly;
- `--accept-state-loss` acknowledging the state-table flush.

Self-signed TLS is rejected unless `--allow-self-signed` is explicitly added.
The password is prompted without echo (or read from `VAKTPOST_PASSWORD`) and is
never written to the report.

## Run each release

From `vaktpost-tools`, first inspect the no-network plan:

```sh
PT_APP=../vaktpost bin/admin-matrix.py https://ce-lab.example lab-user \
  --edition CE --version 2.x --interface lan --service dnsresolver \
  --confirm-disposable-lab ce-lab.example --accept-state-loss --dry-run
```

Remove `--dry-run` only after restoring the disposable snapshot. Add
`--allow-self-signed` only when the lab certificate cannot be validated. Use
`--output` to choose the JSON report path. Repeat from a clean snapshot for the
Plus VM.

## Pass criteria

Each lab-covered row must say `passed`, each write must show `attempts: 1`,
and its read-back must confirm the resulting object or subsystem is readable.
The temporary rule and disabled NAT rule must be absent at the end.

Any timeout, disconnect, malformed response, or unexpected HTTP response is an
unknown outcome. The runner performs read-only inspection where possible but
never repeats the write. If cleanup cannot be verified, it prints the exact
tracker that must be inspected from the pfSense console. Restore the VM
snapshot rather than rerunning against uncertain state.

## Release record

Keep both JSON reports with the release evidence and record:

| Edition | Exact version | All covered writes passed | Lost-response drill | Report |
|---|---|---:|---:|---|
| CE | pending lab run | no | pending | — |
| Plus | pending lab run | no | pending | — |

A lost-response drill requires a proxy or network-control layer that drops the
response after forwarding one write. Verify that the report records one
attempt and an unknown outcome, then inspect the tracker without resending.
