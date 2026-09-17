# Contributing

Thanks for looking. Read this before opening a merge or pull request.

## Licence of contributions

Vaktpost is licensed under `GPL-3.0-or-later`, with the
[additional permission for Apple distribution](APP_STORE_EXCEPTION.md).
Contributions are accepted on the same terms: by submitting one, you license it
under `GPL-3.0-or-later` **including that additional permission**.

Sign off every commit (`git commit -s`). The `Signed-off-by:` line certifies the
[Developer Certificate of Origin 1.1](https://developercertificate.org/): that
you wrote the change or otherwise have the right to submit it under these terms.
Unsigned commits cannot be merged.

Do not submit code copied from projects whose licence does not allow this,
including code from pfSense itself unless its licence permits it.

## Scope

Vaktpost is preparing 1.0.0 and its feature set is frozen; see the scope in
[../README.md](../README.md). Until it ships, changes are accepted when they
make that scope safer, clearer, more accessible or compatible with a supported
pfSense release.

A change that adds a write to the firewall is a security change. It must be
declared in `PHPSnippet.writeOperations`, go through `WriteCoordinator`, and be
explained in the request. Read [../SECURITY.md](../SECURITY.md) first.

## Before submitting

```sh
make project
make lint
make build
make test
```

Keep secrets out of the change: no real hostnames, addresses, fingerprints or
credentials. Use RFC 5737 addresses and `example` domains in tests and docs.

## Reporting security problems

Anything that could be exploited against a firewall should not start as a
public issue. Follow the reporting section of [../SECURITY.md](../SECURITY.md).
