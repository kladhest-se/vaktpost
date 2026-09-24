# AGENTS.md

Notes for an automated contributor. Short on purpose: the rules below are
enforced by scripts, and the scripts' messages say what to do. What this file
is for is getting you to run them, and telling you what not to helpfully
re-add.

## What this is

A SwiftUI app for monitoring and administering pfSense firewalls over
XML-RPC, plus the project website in `public-web/`. `vaktpost-tools/`, beside
this repository, holds the checks and the publish script; it is a separate
repository.

## Before you claim anything works

```sh
../vaktpost-tools/tests/run.sh --fast   # 15 suites; needs php for one of them
make lint && make test                  # needs a Mac with Xcode
```

`make lint` runs SwiftLint with `--strict`, so a warning fails it. The fast
suites catch a good deal without a Mac, including brackets, line length, file
and type length, and modifiers chained onto an `if` or `switch` — the mistakes
a text edit makes that then fail far from where they were made.

`../vaktpost-tools/publish-all.sh` compiles before it pushes and refuses a
broken tree. Use it rather than `git push`.

## Scope

1.0.0 is frozen and being prepared for the App Store. Fixes and verification
only; new features wait. See the status note at the top of `README.md`.

## The write boundary

Everything this app can change on a firewall is in
`Sources/Vaktpost/Net/PHPSnippets.swift`, and `SECURITY.md` explains why it is
shaped the way it is. Read that before touching it. In short:

- Snippets are constants. Nothing builds PHP at runtime.
- Arguments cross as one base64 JSON payload, never interpolated into PHP.
- New PHP functions must be added to `allowedFunctions` with a reason;
  `write-boundary.sh` fails otherwise.
- Writes go through `WriteCoordinator`, never a view directly, and are sent
  once. `write-coordinator.sh` and `lost-response.sh` check this.

## Removed on purpose

The gate fails if these come back, which is the point:

- **Configuration backup.** Removed, not hidden — code, docs and website.
- **Analytics** (`WriteAnalytics`, `AnalyticsView`). The audit trail covers it.
- **The audit trail's share sheet**, with the Settings section that held it.

## Invariants that are not obvious from the code

- Every animation goes through `Motion`, which returns none under Reduce
  Motion. A bare `withAnimation(.spring…)` fails `theme.sh`.
- Icon-only controls carry an `accessibilityLabel`.
- Status is never carried by colour alone.
- Website `href` and `src` must be literal: the deploy script resolves them
  statically and refuses to deploy an unresolved one.
- `vaktpost.kladhest.se`, the public website, is the only hostname allowed to
  appear anywhere. `secrets.sh` fails on any other name under that domain, and
  on any internal address — including in a sentence explaining this rule, which
  is how this line came to be worded the way it is.
- Interfaces are shown by the administrator's name, never pfSense's internal
  key (`opt4`). Use `store.addressLabel(for:)` and `store.interfaceLabel(for:)`.

## Where the rest is written down

| Topic | File |
| --- | --- |
| Features, setup, build commands | `README.md` |
| Credential, write surface, TLS | `SECURITY.md` |
| Contribution terms, DCO | `docs/CONTRIBUTING.md` |
| App Store metadata and review notes | `docs/APP_STORE_SUBMISSION.md` |
| Which writes have run against a lab | `docs/LAB_COMPATIBILITY_MATRIX.md` |
| Website, test lab, screenshots | `public-web/README.md` |
| What each check enforces | `../vaktpost-tools/README.md` |

Do not restate those here. Two descriptions of one rule become one wrong
description as soon as either changes.
