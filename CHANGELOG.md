# Changelog

## NAT reorder identity and separator colour edits are unblocked

NAT drag validation now reads the public destination port from pfSense's
native nested `destination/port` field instead of looking only for a flat
filter-rule field. This removes the false “NAT rule changed” rejection for
ordinary WebUI-created forwards. NAT forward saves now write that native shape
and migrate the earlier Vaktpost spelling.

Existing NAT separators no longer fail filter-only interface validation, so
choosing a different colour enables Save. Filter separators continue to
require their concrete interface.

## Separator editors preview their colours

Filter and NAT separator editors now show four selectable colour squares
instead of a text menu. Each swatch uses the same semantic tint and opacity as
the separator bar it creates, with a visible selection outline and checkmark
plus accessible colour names.

## NAT separators participate in drag ordering

The NAT list now treats port forwards and separator bars as one ordered table.
Both row types have a drag handle, and saving a mixed order rebuilds pfSense's
native `frN` separator positions while preserving complete rule and separator
dictionaries. Adjacent separators retain their relative order, and the result
remains staged under `natconf` until Apply Changes.

## NAT separators are managed beside port forwards

The NAT add menu now offers both Port Forward Rule and Separator. Existing NAT
separator bars open a detail screen and can be renamed, recolored, repositioned,
or deleted. These operations use pfSense's native flat `nat/separator/sepN`
shape and `frN` row positions, preserve unknown fields, carry authenticated
configuration-history attribution, and remain staged under `natconf` until
Apply Changes.

## Firewall management controls survive Rules-to-NAT switching

The navigation-bar add control is now one persistent menu instead of a
conditional toolbar item that could be created empty on All or Floating and
remain absent after switching to NAT. On a selected Rules interface it always
offers both Rule and Separator; on NAT it offers Port Forward Rule regardless
of the previous Rules chip. NAT drag handles remain available across the
complete unfiltered port-forward table.

`make install` now runs Xcode's clean action before building for a physical
device. This prevents an extracted source archive with older file timestamps
from reinstalling stale DerivedData—the failure mode visible when an installed
screen still showed the old Local port label and read-only NAT separator text.

## Redirect target ports use pfSense's native field

NAT rules now read Redirect target port from pfSense's native `local-port`
configuration key and show it in the rule list, detail screen, and editor.
Saving writes that same native key, while still reading and removing the
incorrect `local_port` spelling produced by affected Vaktpost builds. Read-back
verification and NAT reorder identity include the corrected value so target
ports are preserved rather than silently disappearing.

## NAT adding, ordering, and forward actions are complete

The NAT add button no longer depends on the filter-rule interface selection,
so it remains available after switching from All or Floating to NAT. New
forwards start on the selected configured interface when possible, otherwise
WAN or the first configured interface, and the editor still allows changing
it.

The NAT list now supports drag ordering across pfSense's complete flat port
forward table. Reorders validate every original row against a fresh read,
including trackerless rules created in the WebUI, preserve each complete rule
dictionary, stage the NAT configuration without activating it, and verify the
saved order before reporting success. NAT separators retain their existing
ordinal positions.

Port-forward details now present Edit Forward Rule, Duplicate Forward Rule,
and Delete Forward Rule as full-width actions in that order.

## Staged-write safety tests match the current response contract

The save-response fixtures now include the required `apply_pending` marker,
which every successful staged firewall save returns. The tracker-allocation
test also reflects that NAT uses its trackerless-row guard for both new
forwards and legacy forwards being healed, while filter rules use the direct
create guard. This removes the three stale assertion failures in `make test`
without weakening the production checks.

## Server migration tests compile under Swift 6 isolation

The migration tests no longer send their `XCTestCase` instance and its
`UserDefaults` property into `MainActor.run`. Tests which construct the
main-actor-isolated `ServerRegistry` now run on the main actor directly. This
removes the five Swift 6 data-race errors that stopped `make test` during test
target compilation.

## Clean build and test output

Removed two obsolete `@discardableResult` annotations from async editor saves.
The iPad plist now declares all four supported orientations, preserving iPad
multitasking without the build warning. Alias-expansion tests now exercise the
current `resolveAlias` and `expandedAlias` APIs instead of the removed
`resolvedValue` helper, so `make test` compiles again.

## Filter separators can be added, edited, moved, and deleted

The Firewall screen's plus action is now a menu with Rule and Separator.
Choosing Separator opens a focused editor for its label, pfSense colour, and
position relative to the selected interface's rules.

Existing filter separators are tappable. Their detail screen supports rename,
colour and position changes, plus deletion. Every separator write uses the
same administration guard, protected audit record, single-attempt transport,
fresh-state preflight, and read-back verification as rule writes. Saving only
marks pfSense's filter configuration dirty; it remains inactive until the
shared Apply Changes screen is used.

## Successful Apply returns to the rules screen

After Apply Changes succeeds, Vaktpost now refreshes the firewall objects and
checks pfSense's global dirty marker. When nothing remains pending, the review
screen closes automatically. It stays open if a concurrent WebUI or other
administrator change left more work waiting, or if applying reports an error.

## Rule details use the standard back button

Firewall-rule and port-forward detail screens no longer add a redundant Close
action beside the navigation title. The standard back button is now the single
way to return to the rules list.

## Apply Changes is now the confirmation, not a route to another one

The Apply firewall changes page now uses the ordinary navigation back button;
its duplicate Done action and nested navigation stack are gone. The page no
longer opens another confirmation popup after the user has already reviewed
the pending changes and deliberately pressed Apply Changes.

The layout is more compact: rules, forwards, and aliases are presented as a
single summary row, the pending-change review remains the focus, only three
recent applies are shown, and the apply action is a centred, full-width primary
button without a second surrounding card repeating the same explanation.

## Disabled rules, staged editing, and Apply review now match pfSense

pfSense represents configuration presence flags such as `<disabled/>` and
`<log/>` as empty strings over XML-RPC. Vaktpost now treats those present
markers as true, so disabling a rule no longer succeeds on the firewall and
then raises a false read-back mismatch in the app. Disabled filter rules and
port forwards use a muted, grey presentation and an explicit Disabled badge.

Rule details now expose the pfSense fields used by the WebUI rules table,
including status, action, protocol, gateway, queues, schedule, state type,
logging, and tracker. Duplicate Rule is a full-width action between Edit Rule
and Delete Rule instead of an item in the toolbar menu.

Saving, deleting, duplicating, Quick Block, and reordering no longer show a
second confirmation before staging. Apply Changes is the single confirmation
boundary. Its screen itemises verified Vaktpost edits since the previous apply,
labels changes it cannot identify as external, and explains that pfSense's
dirty marker is global. All post-write paths force a targeted rules/NAT refresh
before returning, avoiding the delayed list update of a coalesced dashboard
refresh.

## Saved firewall edits now wait for Apply Changes

Quick Block, filter-rule save/delete/reorder, and port-forward save/delete no
longer reload the live ruleset. They write the configuration and set pfSense's
native `filter` or `natconf` dirty marker, like the corresponding WebUI pages.
The Firewall screen reads those markers, shows a pending-changes banner, and
links to **Apply firewall changes**. The review page warns that applying
activates every pending filter and NAT edit on the appliance, including WebUI
changes from another administrator.

## XML-RPC attribution survives pfSense Plus session startup

The first attribution fix populated `$_SESSION` before `write_config()`, but
pfSense Plus can start its own session inside that function and replace those
values. Each configuration write now starts a temporary, cookie-free session
first, derives the username from the authenticated `PHP_AUTH_USER`, sets the
configured authentication source, and destroys the temporary session after
the revision is recorded. The executable contract simulates the old
session-clobbering behavior.

## Duplicate is an exact new rule, not a renamed edit

Rule and port-forward detail screens now key their editor sheet to the actual
draft. The previous Boolean presentation could retain an ordinary edit's
state and reuse it for a later Duplicate, which updated the source rule.
Duplicating a filter rule preserves its description and enabled state, sends
no source tracker, and can be saved unchanged with a new tracker.

## pfSense configuration history names the authenticated Vaktpost user

Configuration writes made through `pfsense.exec_php` appeared in pfSense as
`(system)@address: Vaktpost: ...`, even though XML-RPC had authenticated a real
user before executing the snippet. pfSense's XML-RPC handler reads
`PHP_AUTH_USER`, while its configuration-revision formatter reads the separate
webConfigurator session fields; the handler does not connect those two paths.

Every Vaktpost operation which calls `write_config()` now supplies that missing
request-local audit context first. The username comes from pfSense's
already-authenticated `PHP_AUTH_USER`, the address remains pfSense's observed
remote address, and the authentication-source label comes from the firewall's
configured provider. No username or provider is accepted from an app payload,
and the temporary attribution session is never persisted. An LDAP write reads
like `user@address (LDAP/provider): Vaktpost: reordered rules on opt5` in
Configuration History. Quick Block, rule and port-forward save/delete, and rule
reorder all use the same attribution.

## Rule reorders refresh immediately and reload failures stay visible

After a verified reorder, the Rules screen called the full dashboard refresh.
That path is deliberately conditional and returns immediately when an
automatic refresh is already running; even when it runs, several unrelated
status calls happen before the rules are replaced. The screen then discarded
its optimistic drag order first, so the rows could visibly snap back and remain
stale until a later cycle.

Reorder now force-loads rules, port forwards and separators directly, and only
then discards the pending drag order. The failure path performs the same
targeted read so a partially completed or conflicting write cannot leave the
screen showing the order it started with. If an older object load is already
in flight, the post-write path waits for it and then starts its own forced
read; `force: true` alone still returns early while another load is active and
would leave precisely the race this change is meant to remove.

The later staged-apply change above supersedes the original immediate-reload
behavior: only the explicit Apply Changes operation calls the synchronous
filter reload now.

## Ruleset reloads now call pfSense's actual filter API

The live `probes/7-write-filter-existence.php` result settled the second
failure exposed by the `$config` scope fix: `/etc/inc/filter.inc` loaded
successfully, but `write_filter()` did not exist. This was not caused by the
length of the reorder snippet or by loading `util.inc` first. The app was
calling the wrong function.

The explicit Apply Changes call uses `filter_configure_sync()`, the function
declared by pfSense's `filter.inc`. Save operations now use pfSense's WebUI
dirty markers and do not call the reload function.

The snippet function allowlist, write-boundary audit and executable PHP
contract fixture now name the real function too. This matters beyond making
the tests pass: the old fixture supplied its own fake `write_filter()` to every
write snippet, so it accidentally hid the exact production incompatibility it
was supposed to catch.

The same follow-up audit found that Quick Block still lacked `global $config;`.
It was not among the five rule and NAT writes fixed by the live A/B test, but it
reads and updates the same global configuration and therefore shared the same
failure condition. It now declares the global too. The write-boundary suite
also requires that declaration in every snippet which references `$config`, so
the local test harness no longer has to reproduce pfSense's unexplained eval
scope behaviour to catch this class of mistake.

## The actual cause, found by a live A/B test rather than reasoning about scope

`reorderFilterRules` never declared `global $config;` anywhere in its body.
Neither did `saveRule`, `deleteRule`, `saveNatRule`, or `deleteNatRule` — every
administrative write in this app shared the identical gap. Every read-only
snippet, including both diagnostic probes written during this investigation,
declared it.

This was found empirically, not by reading pfSense's own `exec_php` source
and reasoning about it — that reasoning was tried first, concluded the
declaration shouldn't matter (`eval()` executes in its caller's scope, and
that caller already declares `global $config` one level up), and was wrong,
or at least incomplete for whatever this specific pfSense version actually
does. What settled it was a direct, controlled experiment: the reorder
snippet's exact validation logic, given a hardcoded, definitely-correct
interface and item list — bypassing the payload entirely — run live against
the real firewall. It failed, identically to every previous attempt. An
otherwise near-identical read-only probe, differing only in explicitly
declaring `global $config;`, succeeded against the same firewall at the same
moment. That is about as close to a controlled experiment as this kind of
investigation gets, and it pointed at the one line every failing snippet
was missing and every working one had.

All five now declare it, in the same place every other snippet in this file
already does: right after the `require_once` lines, before `$config` is
first read.

This should also explain the earlier, never-resolved failure editing an
unrelated rule several rounds ago — "the rule tracker no longer exists,"
attributed at the time to a probable race with something else on the
firewall. That explanation was a guess made without this evidence. `saveRule`
had the identical gap the whole time.

## The raw base64 diagnostic is replaced with the parsed items directly

Decoding the previous round's base64 payload by hand suggested the
submission contained one rule tracker twice and never included the other
one at all — a real, plausible bug shape. But checking that specific
scenario directly against `array_diff`'s actual behaviour predicted a
different error message than the one actually shown, which means the
transcription — dense, wrapped, multi-line base64 read out of a screenshot
by hand — most likely introduced an error of its own along the way. A
single misread character in base64 produces a plausible-looking but wrong
reconstruction, with nothing about the reconstruction itself to reveal
that it happened.

Rather than ask for the same transcription again and risk the identical
failure mode, the diagnostic itself is fixed: the mismatch error now shows
`$vaktpost_items`, already parsed by this snippet's own code, directly —
kind and id for every entry, in the order submitted. Nothing about reading
this can introduce a transcription error, because there is nothing left to
transcribe.

`decoded interface as hex` stays, since it already gave a clean, direct
answer last round — `6f707435` decoded to exactly `opt5`, byte for byte,
which is real and did not depend on reading anything dense by hand.

Verified against the real PHP interpreter: the existing `write-contract`
case now asserts the exact parsed-items string a known submission produces,
rather than asserting on the base64 encoding of it.

## The validation logic itself is confirmed correct — the payload is now visible directly

A probe run against the real firewall proved the underlying data was never
the problem: both rules exist, on the correct interface, as plain strings,
exactly matching what config.xml itself shows — reading `$config` the exact
way this snippet reads it. A second probe went further: the reorder
snippet's own validation logic, copied verbatim and given a hardcoded input
matching exactly what the app's own confirmation dialog said it was
submitting, succeeded — no mismatch, against a synthetic copy of this
firewall's real ruleset. That isolates the disagreement to one specific
place: somewhere between what Swift encodes and what this snippet decodes,
not the data, and not the logic that checks it.

The mismatch error now shows both directly rather than inferring one from
the other: the exact base64 payload this attempt received, and the interface
value decoded from it, rendered as hex rather than text — since a value that
prints identically to `opt5` could still differ from it byte for byte, and
text rendering is exactly the thing that would hide that.

Two mistakes caught before this shipped, both in the new code itself rather
than in what it was diagnosing:

- The labels were originally stored as array keys, joined into the final
  message with `implode()` — which joins only values and discards keys
  silently. The two labels would have vanished from the actual output,
  leaving two unexplained bare values in their place. Rewritten as plain
  indexed strings with the label written into the text itself, matching
  every other line in this same array.
- The label `"raw payload ("` tripped the identical false positive from two
  rounds ago — the publish gate reads PHP string contents the same as PHP
  syntax, and cannot tell a label containing an open parenthesis from an
  actual function call. Reworded rather than escaped.

`bin2hex` is now on the function allowlist — a pure, built-in string
conversion with no file, network, or config access, added and reviewed
rather than silently included.

Verified against the real PHP interpreter: a new `write-contract` case
confirms both new fields appear in a mismatch response, and that the hex
shown is a genuine encoding of that response's own interface value rather
than a fixed placeholder.

## Removing the requires changed nothing: ruled out, cleanly

The experiment came back conclusive. Identical error, identical wording,
the same two trackers -- removing `reorderFilterRules`'s `require_once`
lines had no effect on the failure whatsoever. That rules the requires out
as the cause, with actual evidence rather than another guess left standing.

## Checking pfSense's own config cache directly

pfSense caches its parsed configuration at `/tmp/config.cache` and reads
from that cache rather than reparsing `config.xml` on every request,
refreshing it only when `write_config()` properly invalidates it. If that
cache were stale on this firewall for any reason, `global $config` could be
reading old data consistently across every attempt -- which would explain
precisely what's been observed: the *same* two trackers, failing the *same*
way, no matter what changed on the app's side between attempts.

Rather than propose this as an eleventh hypothesis, the mismatch error now
checks it directly and reports what it finds: whether `/tmp/config.cache`
exists, how old it is in seconds, and whether the specific trackers this
attempt says are missing appear anywhere in that file as plain text. If they
do, that is about as close to a smoking gun as this investigation is likely
to get without shell access to the firewall itself. If they don't, that
rules out the cache too, and narrows what's left to look at considerably.

This is read-only and unconditional -- it only runs after a mismatch has
already happened, costs one file check and one string search, and cannot
itself change anything about the outcome.

## Experiment: removed reorderFilterRules's require_once statements

Not a confirmed fix — an experiment, run because the array-interface theory
in the previous entry turned out to be wrong. The rule the reorder kept
failing against, checked against the actual config.xml, has a completely
ordinary `<interface>opt5</interface>` — a plain value, not an array. That
diagnosis didn't hold up, even though the fix itself remains a valid,
separate improvement.

What's actually being tried now: `reorderFilterRules` requires
`/etc/inc/util.inc` and `/etc/inc/filter.inc`, identically to `saveRule` and
`deleteRule`. The read-only `firewallRules` snippet requires neither and has
never shown a rule reported as missing when it plainly still exists — and
the earlier, never-resolved "the rule tracker no longer exists" failure
editing a different rule was `saveRule`, which shares these same two
requires. That pattern doesn't prove the requires are the cause; direct
inspection of both files found no code that touches `$config` at the top
level at all. But the two pfSense functions this snippet actually calls,
`write_config()` and `write_filter()`, are defined in neither file, and
pfSense's own config bootstrap runs before any snippet executes regardless
of what that snippet itself requires — so there's a real chance these lines
were never necessary here in the first place.

Removed, and clearly labelled in the snippet itself as an experiment rather
than a diagnosis. If they were genuinely unneeded, this changes nothing
about correctness. If something did depend on them, the failure mode is an
immediate, unambiguous fatal error — not another silent, well-formed
mismatch — which would itself be informative.

Worth being direct about the limits of what's verified here: the local test
harness strips every `require_once` line and substitutes its own stub
`write_config()`/`write_filter()` for every snippet, unconditionally — so
this exact scenario has been running in every test from the start, and
passing tests here confirms nothing new about real pfSense's behaviour. The
only way to actually learn something is trying it against the real firewall.

## Found it: pfSense stores some rules' interface as an array, not a string

The error read: currently on opt5, nothing. That single line settled it. The
firewall itself confirmed zero rules and zero separators exist on opt5 at
all — so the two rules shown as OPENVPN1 in this app genuinely do not have
`interface === "opt5"` as a plain string, on the live config, full stop.

`FirewallRule.interfaceName` already knew this could happen — its very first
line tries reading `interface` as a list before falling back to a plain
string, specifically because some rules store it as an array. For a rule on
exactly one interface, that array has one element, and joining a one-element
array with commas produces that element back with no comma at all — so the
app's own display, and `isFloating`'s comma-count check, could never tell
the difference between a genuine single-interface rule and this array-backed
one. Only the *display* path knew about it.

Five PHP comparison sites across two snippets never did. Each did a bare
`strval($rule["interface"] ?? "")` — and PHP's `strval()` on an array
produces the literal string `"Array"`, silently, with the warning suppressed
by this project's own `display_errors` setting. `"Array"` never equals
`"opt5"`. Every one of those five comparisons is now fixed to do what
`FirewallRule.interfaceName` already does: check for an array first, join it
the same way, then compare.

- **`reorderFilterRules`**, three sites: which rules belong to the interface
  at all (this is the one that was actually failing), the diagnostic lookup
  that reports where a rule really is, and — most important of the three —
  the reassembly step that decides which array slots to overwrite. That last
  one mattered even for a rule that *would* have passed a fixed validation:
  without fixing the reassembly too, a correctly-recognised rule could still
  have been silently skipped when the new order was actually written.
- **`saveRule`**, two sites, found by pattern rather than by a new report:
  the "before" placement anchor check, and the "keep is interface-local"
  check run on every ordinary edit. The second one means an entirely
  unrelated, everyday edit — descriptionchange, disable toggle, anything — of
  a rule whose interface happens to be array-backed would have been rejected
  outright with "the selected rule position is no longer available," with
  no connection visible between that message and its real cause.

Both fixes are covered by new `write-contract` cases run against the real
PHP interpreter, not only traced by hand: a reorder that includes a
one-element-array-interface rule now completes and repositions it correctly,
and an ordinary edit of such a rule with "keep" placement now succeeds
instead of being rejected.

A `save_nat_rule` legacy-identity comparison has the identical shape and was
not touched this round — NAT rules are far less likely to carry this
representation, given they lack the floating-rule multi-interface concept
that seems to be why pfSense reaches for an array at all, and fixing it
without a live case pointing at it risks changing behaviour nobody has
actually hit. Worth the same fix if a report ever does trace back to it.

## The mismatch error now shows both sides of the disagreement

The alert fix worked — the real error finally surfaced, and it is genuinely
reproducible: the same two trackers, every attempt, reported as not existing
anywhere in the ruleset, now joined by a third fact — the separator key
itself doesn't match either. That rules out the silent-failure theory
entirely. What it does not yet say is which side is actually wrong: whether
this app is reading incorrect or stale trackers for these two rules, or
whether it has a genuinely different picture of what's on this interface
than the firewall does, for a reason not yet found.

Rather than propose a ninth hypothesis, the error now shows both sides
directly. Every previous round reported what was *missing* or *extra* in the
submission, one tracker or key at a time, relative to what the interface
already had — useful when most of a submission was right and one item was
wrong, useless when nothing overlaps at all, which is exactly what's
happening here. It now also states plainly what the interface currently
has, in full, regardless of what was submitted: every rule's tracker and
description, every separator's key and text. The next failure should show
directly whether the app's own two trackers appear in that list under
different values, or whether the interface's real rules turn out to be two
completely different rules the app isn't showing at all.

Verified against the real PHP interpreter: a new `write-contract` case
submits an order with zero overlap with the interface's actual state and
asserts the response reports the interface's true current contents in full.

## A reorder failure could never actually show its error

Found by re-reading my own reasoning rather than proposing another guess: I
had concluded "no error appeared, so the write and its verification must have
succeeded" — and that conclusion was wrong, because the alert that would have
shown a failure could not physically present, regardless of whether the
write failed or not. The absence of an error proved nothing.

`.writeErrorAlert` for a failed reorder was attached to `orderChangedBar` —
the "Order changed / Discard / Save order" bar itself, which only renders
`if ruleOrderIsDirty`. `rulePendingOrder = nil` runs in *both* the success
and the failure branch of `saveRuleOrder()` — success, correctly, and
failure, from the round that fixed "stuck resubmitting a doomed payload
forever." Either way, the moment that line runs, `ruleOrderIsDirty` becomes
false and the bar disappears — taking its attached alert with it. On
failure specifically, that removes the alert at the exact instant it needed
to appear: a SwiftUI alert cannot present on a view that is no longer part
of the hierarchy.

This is the identical shape of bug `RuleEditSheet` and `PortForwardEditSheet`
were already fixed for, earlier in this project — an error caught on a view
that is not the one left on screen when the failure happens. This feature
was built without carrying that lesson forward into new code, which is worse
than not knowing the lesson existed.

The alert is now attached to the screen's own stable container — the same
one `.task`, `.navigationTitle`, and `.toolbar` already live on — which
exists regardless of pane, interface selection, or whether a pending order
exists. Every other `.writeErrorAlert` in this file was already anchored
this way; this one was the sole exception, and is not anymore.

**What this means for the actual reorder problem**: unresolved. The write
may have been failing with a real, specific error this whole time, silently,
because the alert meant to show it could not appear. The next attempt should
finally surface whatever that error actually is — which may be the tracker
mismatch already investigated, or may be something this bug has been hiding
entirely. Everything concluded from "no error was shown" in the last two
rounds should be treated as unproven rather than ruled out.

## Rule and forward rows resolved aliases pfSense shows by name

pfSense's own rules list shows "alias_host_nas003" — the alias, clickable,
by name. This app was showing what that alias resolves to, "172.16.1.33",
in the same field. Same for port aliases: pfSense's own list shows
"alias_port_hyper_backup"; this app showed "6281, 5000, 5001". A rule was
never lying — the values are exactly what the alias contains — but the list
was answering a different question than pfSense's own list answers, and
looked wrong sitting next to it for that reason.

Source, destination, target, and both ports on both the rule row and the
port-forward row now show the literal stored value, matching pfSense's own
list exactly. `resolvedValue`, the function that resolved them, is now
called from nowhere in the app and has been removed rather than left as
dead code inviting a future "helpful" reintroduction.

One correction to my own comment while making this change: the fix's first
draft justified itself by pointing at `expandedAlias` as "the explicit
drill-down used in the detail view" — checked, and it is not called from
anywhere either. Fixed the comment rather than let a confident, false claim
about the codebase stand uncorrected next to the change it was explaining.

## Filter rules and port forwards were never refreshed, ever

The two rules a reorder kept failing against were not the victims of a race.
They genuinely no longer exist on the firewall — the error now confirms this
directly ("no longer exists anywhere in the ruleset") — and the same two
trackers failed identically on every retry because nothing had re-fetched
`store.rules` since long before they were removed. This is the actual cause,
traced to its root rather than patched at the symptom.

`store.refresh()` — what every successful write in the Firewall feature calls
afterward, and now what a failed reorder calls too — has never refreshed
filter rules or port forwards, at all, under any circumstance. Not a stale
window, not an occasional miss: **the general refresh cycle simply never
requested them.** Every other section — clients, VPN, system, the firewall
log — has a line launching its fetch; rules and forwards did not. The only
paths that ever populated `store.rules`/`store.portForwards` were a screen's
first appearance (guarded against repeating itself, by design, for exactly
that case) and a handful of call sites passing `force: true` directly for
their own narrow reasons. Once a screen had loaded rules the first time in a
session, nothing — not a pull to refresh, not an automatic refresh timer, not
a `store.refresh()` after any other successful write — ever asked again.

Two changes, at the two different levels this bug lived on:

- `store.refresh()`'s own cycle now includes rules and port forwards as one
  of its concurrent fetches, the same way it already fetches the firewall
  log, clients, and VPN status. One fetch, not two: `.firewall` and
  `.portForwards` both resolve to the identical `loadFirewallObjects(force:
  true)` call, so requesting both as separate concurrent tasks would have
  raced that one call against itself. Requesting `.firewall` alone refreshes
  rules, forwards, and separators together, exactly as it already does
  everywhere else this function is called from.
- The shared per-section fetcher that both `store.refresh()` and the
  Diagnostics retry button route through now passes `force: true` rather
  than the default — `loadFirewallObjects()`'s own once-per-session guard is
  correct for a screen opening for the first time, and is exactly backwards
  for a refresh, whose entire purpose is superseded by it.
- The reorder failure path specifically now also triggers a refresh and
  discards the stale pending order, rather than leaving a person free to keep
  resubmitting the identical doomed payload against the identical stale data
  forever. A "Save order" built from data just proven wrong is not worth
  preserving; a fresh drag against current data is the only version of the
  next attempt that can mean anything.

I made a mechanical mistake putting the first of these together — a second
edit to the same file was built from a copy of the file read before the first
edit was written, so writing it back discarded the first change silently.
Caught by checking that the change was actually present in the result rather
than trusting that two edits which each reported success necessarily left
both changes behind.

## The mismatch error now says where a rule actually is

The previous round named the specific trackers a reorder disagreed about —
"not currently on this interface: 1788431726, 1788371063" — which was real
progress and immediately raised the next question: where does the firewall
think they are instead? A bare tracker number does not distinguish "this rule
moved to another interface since it was fetched" from "this rule no longer
exists at all," and those call for different responses.

For every such tracker, the snippet now searches the entire ruleset and
reports what it finds: `1788431726 (actually on "ovpns5")` if the rule
exists elsewhere, `(no longer exists anywhere in the ruleset)` if it does
not. One or the other will name the actual disagreement directly rather than
leaving it to be inferred from a bare number a second time.

If the report comes back naming a different raw interface value that the app
also displays under the same "OPENVPN1" label — the leading theory, since
`interfaceLabel` already matches a rule's interface field against three
different stored names for one configured interface (`device`,
`internalName`, `name`), any of which could appear in different rules
depending on how or when they were created — that confirms the cause
precisely rather than leaves it a guess. If it instead reports the rule as
gone entirely, that points at deletion elsewhere between fetch and save
rather than a naming mismatch, which is a different problem with a different
fix.

Verified against the real PHP interpreter: a `write-contract` case reorders
using a rule tracker that genuinely belongs to a different interface in the
fixture, and asserts the response names that interface specifically.

A second backslash-escape rejection came out of building this one, for the
same reason as the first: PHP double-quoted strings needed an embedded literal
quote character, which needs a backslash to write with double quotes but
needs nothing at all with single quotes. Rewritten with PHP's own single-quote
syntax rather than adding another backslash for the gate to refuse.

## The reorder mismatch error said nothing about what actually mismatched

Reordering OPENVPN1 — two rules, no separators, none of them untracked —
still failed with the same generic "does not match this interface's current
rules and separators exactly." No untracked rule was the cause here, which
was the previous fix's hypothesis; something else disagreed, and the message
gave no way to tell what without guessing again.

The message now says which. On a mismatch, the snippet computes the actual
difference — which trackers or separator keys the firewall has that the
submission didn't include, and which the submission included that the
firewall doesn't currently have — and reports them by name. A missing rule,
an extra one, a stale separator key: each now reads as what it is instead of
one interchangeable "mismatch."

Verified against the real PHP interpreter, not only traced by hand: a new
`write-contract` case submits an order missing one rule and asserts the
returned error names that exact rule.

One rephrasing came out of building this: the message originally read
"...exactly (" immediately before the detail — and the publish gate's
function-call scanner reads PHP string contents the same as PHP syntax, so
"exactly (" inside a string was indistinguishable from a call to a function
named `exactly`. Rephrased with a colon rather than loosening what the gate
checks.

The next attempt on OPENVPN1 should return a message specific enough to
finally show what disagreed, rather than another round of guessing.

## Reordering failed with no way to tell why

`reorder_filter_rules` has always silently skipped any same-interface rule
with no tracker when it builds what it considers that interface's current
set — the same shape as `save_rule` and `delete_rule`, both of which already
refuse an empty tracker outright. If even one rule on the selected interface
has none, a submission built from every visible rule can never match the
firewall's own count, and every drag on that interface fails the same
"mismatch" — dragged sensibly or not — with nothing said about why.

This is now checked before the drag UI is ever offered. A rule with no
tracker is named specifically — "One rule here has no stable ID: <its
description>" — and reordering is not offered on that interface at all until
it changes, rather than letting someone drag, wait, and get an error that
gives no indication which rule was the problem or that a rule was the
problem at all.

Stated plainly alongside it, since it is a real limit and not a minor one:
this app cannot edit, delete, or reorder a filter rule pfSense has not given
a tracker. Nothing here heals one the way an edit already heals an untracked
port forward — filter rules almost always get a tracker through pfSense's
own mechanism, unlike NAT rules which never do through the ordinary web GUI,
so there has been no equivalent fallback built for this side. A rule ending
up untracked at all is itself unusual on a normal firewall; a package that
injects rules by some path other than the ordinary edit form is a plausible
source, though this does not depend on knowing which one it is here — it
only needs to notice the rule has nothing stable to move it by.

## Floating rules were bleeding into individual interface tabs

A floating rule's interface field holds several interface names at once —
that plurality is the actual definition of `isFloating`. Selecting a specific
interface tab checked whether that interface was *one of* a rule's names, so
a floating rule scoped to several interfaces appeared under every one of
their tabs, when pfSense shows a floating rule only under Floating, regardless
of which interfaces it applies to.

This was already handled correctly elsewhere: `RulePlacement` and
`reorderFilterRules` both compare a rule's interface field for exact
equality, which excludes a multi-valued field with no special case needed.
The visible rules list was the one place still reasoning about it differently
from the rest of the app. It now excludes a floating rule from a specific
interface's list explicitly, the same way those two already do.

This also removes a failure mode the reorder feature could otherwise have
hit without anyone reporting it yet: a floating rule visible under a specific
interface's tab would have been draggable there, but `reorderFilterRules`'s
own exact-match validation already excludes floating rules from that
interface's reorderable set — so submitting an order that included one would
have been rejected as a mismatch the moment someone tried to save it.

## Editing an untracked port forward was rejected before it could heal itself

`saveNatRule`'s own PHP has had a complete answer to "this forward has no
tracker" for a while: match it by its original interface, destination, port
and target instead, and assign it a fresh tracker on save so it is healable
going forward. `PortForwardEditForm` already sends those original fields.
`WriteCoordinator.validate()` already knew about the fallback. Two things
between them did not:

- **`FirewallClient.saveNatRule`'s own guard rejected the edit outright** —
  "Port-forward editing requires a tracker ID" — before the payload, which
  already carried everything the snippet needed, ever left the phone. It now
  also accepts an edit whose forward has no tracker but does carry its
  original identity.
- **`validatedSaveResponse` would then have rejected the healed result
  anyway.** It compared the tracker pfSense returned against the one that was
  requested, and for a healed forward those are never equal — there was no
  tracker to request in the first place, so a freshly assigned one is the
  correct result, not a mismatch. The comparison is now skipped when nothing
  was requested. A filter rule edit never reaches this with an empty tracker
  at all — `validate()` already requires one before the request is sent — so
  this changes nothing for that path.

## Separator colours were all rendering the same

`SeparatorBar` matched a separator's stored colour with an exact switch —
`"warning"`, `"danger"`, `"success"`, everything else falls to the same
default. `color` is read correctly from the payload, confirmed by re-reading
the snippet, but pfSense's actual convention for that field was only ever
confirmed as "used directly as a CSS class name"
(`display_separator()`'s own `<td class="' . $cellcolor . '">`) — not
confirmed as the bare word. If the real value is a compound class built
around it, an exact match never fires. The comparison is `contains` now:
correct for the bare word, and also correct for any class name built around
it, without needing pfSense's exact convention pinned down first. Worth
checking on a real firewall — this is the tolerant fix, not a confirmed one.

## Investigated: a filter rule save failing "the rule tracker no longer exists"

Traced completely and found no bug in this app's own handling. The tracker
sent on save is `rule.tracker` — the same value the rule's own detail screen
was opened with — carried through `RuleEditForm` and `toDict` unchanged; noteworthy since
`WriteCoordinator.snapshotBefore` already re-reads the live ruleset immediately
before the write and did not itself reject this at that point. A specific,
checkable hypothesis — that a numeric tracker picks up a `.0` suffix somewhere
in JSON decoding and silently stops matching the firewall's own string — was
checked directly against `JSONValue.stringValue` and ruled out; it already
converts a whole-number value through `Int(n)` rather than raw string
interpolation.

What is left, given `snapshotBefore`'s own fresh read still passed moments
before the write failed, is a narrow window in which something else changed
that interface's rules between those two calls. The visible pfBlockerNG
activity on this firewall — its own cron-driven rule regeneration — is the
most plausible candidate, and "not_found" is the correct, safe response to
that race rather than a wrong one: refusing beats guessing. If this recurs on
the *same* rule specifically rather than varying, that would point to
something this investigation has not found yet and is worth reporting back.

## NAT reordering: not built yet, and now better scoped

Still not implemented — dragging a port forward has no effect, as before. But
the investigation above into the NAT tracker-healing path clarifies exactly
what a safe version needs: the same hybrid identity `saveNatRule` already
uses and already ships with — tracker when one exists, the original
interface/destination/port/target tuple when it does not — extended from a
single edit to a whole-list permutation. That is real, bounded work now that
the identity question has an answer, rather than the open one it was last
time.

## Drag to reorder rules and separators

A leading drag handle (≡) on every rule and separator row, when exactly one
interface is selected with nothing searched or floating — the same condition
already required to show a separator's position at all, because reordering
needs the identical well-defined, complete view of that interface's ruleset
that showing a position does.

- **The backend already existed.** `reorderFilterRules`, in `PHPSnippets.swift`
  — fully written, fully verified against real PHP execution and a synthetic
  multi-interface fixture in `write-contract.sh` — had been sitting unused,
  the same way `RuleSimulationEngine` and `RuleConflictDetector` once were.
  What was missing was everything between it and a person's finger: no
  `WriteCoordinator` case, no `FirewallClient` method, no UI. This wires it up
  rather than writing a second, competing implementation, which is what
  nearly happened before the existing one was found.
- Dragging rearranges an in-memory order only. A **Save order** bar appears
  once it differs from the firewall's own order, with **Discard** beside it —
  matching pfSense's own drag-reorder UI, which does not write on every drop
  either. Saving goes through the same confirmation, rate limit, audit trail
  and read-back verification as every other write; the read-back specifically
  confirms the interface reads back in the exact order that was requested,
  not merely that the write did not error.
- Only the handle starts a drag. The rest of a row is untouched — tapping a
  rule still opens it — because "pick this up" and "open this" need to stay
  two different gestures on the same row.
- A drag whose result no longer matches the firewall's current rules and
  separators — because a refresh happened, or something changed elsewhere —
  is discarded silently rather than shown or saved. Showing a stale order as
  if it were current would be a wrong answer dressed as a live one.

### A near-duplicate caught before it shipped

The first attempt at this wrote a brand new pair of snippets,
`reorder_rules`/`reorder_nat_rules`, from scratch — before running the write
audit, which immediately reported `reorder_filter_rules` as an *undeclared*
write: a snippet already existed under that exact name, already in
`writeOperations`, already covered by seven `write-contract` test cases. The
duplicate was deleted; this feature wires up the original.

### The NAT half is not included, and will not be built the same way

pfSense assigns **no tracker at all** to a NAT rule saved through its own web
interface — confirmed directly against `firewall_nat.php` and
`firewall_nat_edit.php`, neither of which references one anywhere. A NAT
reorder snippet was written to mirror the filter one exactly, keyed on
tracker the same way, and caught before it was wired to anything: on a typical
firewall, where every port forward was created through pfSense's own GUI,
every forward would have been excluded from the rebuilt array and silently
deleted on first use. It was deleted rather than left in the tree unreachable
— unreachable is not durable insurance against a later turn wiring it up
without rediscovering the same problem.

A safe version needs a different identity for a NAT rule than "its tracker,"
since most real ones do not have one. `saveNatRule` already establishes what
that identity looks like for a single edit — interface, destination, port and
target together — and a reorder built the same way is real, separate work
covering more cases (two forwards that happen to share all four of those, a
forward that changed underfoot between fetch and drop) than adapting seven
lines of validation.

## Separators: two structural bugs fixed against pfSense's actual source

The first version of this feature guessed at two things it should not have
guessed at, and both guesses were wrong. Fixed by reading `filter.inc` itself
rather than inferring further.

- **`row` is an array, not a string.** pfSense stores a separator's position
  as `row/0` — e.g. `["fr3"]` — and reads it with
  `array_get_path($separator, 'row/0')`. The snippet read `row` as a plain
  value, so `strval()` on the array produced the literal string `"Array"`,
  which has no digits and could never be parsed. Every separator's position
  was silently unrecoverable.
- **Filter and NAT separators are not the same shape.** Filter really is
  grouped by interface, at `filter/separator/<interface>`. NAT is a single
  flat list at `nat/separator` with **no interface grouping at all** —
  confirmed from `firewall_nat.php`, which reads `nat/separator` directly and
  numbers every forward with one counter that runs across the whole list
  regardless of interface. The snippet had assumed NAT mirrored filter's
  per-interface grouping, so it iterated NAT's flat `sepN` keys as if they
  were interface names, and iterated each separator's own fields (`row`,
  `text`, `color`) as if each one might itself be a separate separator. That
  is where "Separator — sep0" came from: `sep0` is the separator's own key,
  read out as though it were an interface.
- The row prefix is confirmed as exactly two characters, `"fr"`, from
  `separator_rows()`'s own `substr(..., 2)` — no longer a tolerant guess at
  an unknown prefix.

### Interleaving now follows pfSense's own rule order

- On the Rules pane, unchanged in principle: a separator renders at its
  recorded position among that interface's own rules, only when exactly one
  interface is selected and nothing is being searched.
- On the NAT pane, separators are now interleaved at their real position in
  the full forward list — not, as before, dumped as an unordered summary
  above the list. Because NAT's position is a global count rather than a
  per-interface one, this only needs "nothing is being searched" as its
  condition; there is no interface selector on this pane to begin with.
- Both panes read the identical `precedingRuleCount` field on
  `RuleSeparator`; what differs, and what each pane's own code now says
  explicitly, is what that count is taken *against* — one interface's rules
  for filter, the whole list for NAT.

### What is still open: dragging to reorder

Not implemented in this round, and not attempted, because the risk sits behind
one specific gap. The editor already has a rule-reordering primitive —
`saveRule` accepts a `placement: "before"` with a stable tracker anchor, used
today when saving an edited or newly created rule at a chosen position — but
that is a single, deliberate move made through the editor, not a drag gesture,
and nothing equivalent exists for port forwards yet.

Separators have no reposition mechanism at all, and that is the part that
cannot be added safely without more work first. pfSense keeps a dedicated
function, `shift_separators()`, purely to renumber every separator's `row`
value when a rule is inserted or removed at a given index — the direction and
amount of the shift depends on whether a rule is being added or removed and
where, relative to each separator. Moving a rule (by drag or otherwise)
without reproducing that renumbering leaves every separator below the moved
point pointing at the wrong rule from that moment on — which, worth noting, is
a real, unresolved bug in pfSense's own web UI today, reported by its own
users. Writing to this app's second, independent copy of the same fragile
mechanism without first porting that renumbering faithfully would only add a
second way for it to happen.

## pfSense's own separators are now visible

The rule and port-forward lists never showed the coloured grouping bars
pfSense's own web GUI draws between rules — "Teamspeak" in a port-forward
list, for instance. They were simply invisible: this app never read that part
of the configuration at all.

- Read-only. There is no write path for this and none is planned on what could
  be confirmed. pfSense stores a separator's position as a bare count of
  preceding rules rather than anchoring it to a rule's tracker, and pfSense's
  own users report separators drifting out of place after an ordinary
  insert or delete performed from pfSense's *own* web UI — a known,
  unfixed fragility in a feature that changes nothing about what traffic is
  allowed. Writing this from a second piece of software without the exact
  placement semantics confirmed would risk making a real, if cosmetic,
  pfSense bug worse, for no functional gain.
- What's confirmed against pfSense's actual source: separators live at
  `filter/separator/<interface>`, one entry per separator, keyed under an
  interface name. What is **not** confirmed — because nothing short of a live
  firewall or pfSense's own rendering code would confirm it — is the exact
  key holding a separator's label, or the precise meaning of its position
  field once decoded. The snippet reads every plausible label key rather than
  betting on one, and passes the position through as the untouched string
  pfSense wrote, for the model to interpret rather than the snippet asserting
  a meaning it cannot verify.
- NAT's separators are read from the equivalent path one level down, on the
  working assumption that it mirrors the filter side. That assumption itself
  is unconfirmed; if it's wrong, NAT separators simply don't appear, which is
  a quiet miss rather than a wrong answer.
- On the Rules pane, a separator renders in its recorded position **only**
  when exactly one interface is selected, nothing is being searched, and
  floating rules aren't shown — a position is a claim about one interface's
  unfiltered rule order, and interleaving it into "All interfaces" or a
  search result would be answering a question that no longer has the shape
  the position was recorded against. The screen says the position is inferred
  and to check the web GUI if a bar looks out of place.
- On the NAT pane, which shows every forward regardless of interface and has
  no single rule order to place a bar against, separators are listed by name
  next to the interface they belong to instead — visible, without a position
  claim this pane can't support.
- Fetched alongside rules and forwards, but failing quietly if it fails: this
  is read-only decoration on data that already loaded successfully, so a
  problem here doesn't raise an error banner or block a retry of the section
  that actually matters.

## Editor save errors were invisible

Editing and saving a rule or a port forward could silently do nothing: the
confirmation popup would close and nothing would change on the firewall, with
no error shown and nothing in the firewall's own log.

- **The cause was structural, not a bad value.** The confirmation dialog is a
  sheet nested inside the edit sheet. On failure, the error was being caught
  and stored on the screen *two levels back* — the rule list or the rule
  detail view — which was still covered by the edit sheet, since a failed save
  deliberately did not dismiss it. An alert attached to a view that is covered
  by an active sheet cannot appear until that sheet closes, and nothing closed
  it, so the failure was real and simply never seen.
- This affected all four write paths through the editor: editing or creating a
  rule, editing or creating a port forward. Deleting was unaffected — its
  confirmation is a single sheet, not nested inside another.
- `RuleEditSheet` and `PortForwardEditSheet` now own their save error state
  and show their own alert, since each is the view actually on screen at the
  moment its own confirmation dismisses. `onSave` changed from
  `async -> Bool` to `async throws -> Void` so the real error propagates
  instead of being collapsed into a boolean before it can be displayed.
- The top-level Firewall list's error state, which the create flow used to
  write to, is now unused there and has been removed rather than left as dead
  state that looks wired up but never fires.
- Verified against the project's `write-contract` suite, which executes the
  actual generated write PHP against synthetic pfSense configuration: editing
  a port forward — including toggling `disabled` on one whose destination is
  an interface address like `wanip` — round-trips correctly. The PHP was never
  the problem; the error it was correctly returning could not reach the screen.

## Quick Block theme, honest diagnostics and visible blocks

- Quick Block now uses the active Catppuccin background, cards, fields,
  accent and semantic colours instead of an unthemed system form. The shared
  write confirmation follows the same palette.
- Diagnostics now reports the number of current issues without presenting all
  36 lazy/on-demand features as if every one had been attempted. Performance
  history counts only sections that were actually attempted and failed.
- A pfSense build without a safe live-table PHP accessor is shown as a
  capability limitation on the System screen, not as a permanent failed
  Diagnostics section.
- Enabled literal-source block rules—including rules created by Quick
  Block—are now shown under Blocked hosts. Quick Block forces a ruleset reload
  after verification so its new rule appears immediately.

## Administration enablement without biometrics

- A defined firewall can now be switched from monitor-only to administration
  after its explicit risk confirmation, without Face ID or Touch ID.
- The setting remains scoped to one firewall, remains off by default, and does
  not take effect until that firewall profile is saved.
- Biometric protection is unchanged for revealing or replacing a stored
  administrator-equivalent password and for the optional whole-app lock.

## Swift 6 concurrency safety

- The app now builds in Swift 6 language mode with complete concurrency
  checking instead of Swift 5.9 with minimal checking.
- Certificate trust state and one-shot callbacks use compiler-recognized
  locked storage; the remaining `@unchecked Sendable` declarations are gone.
- Certificate prompts, UIKit feedback and app-icon access are explicitly
  confined to the main actor, while history values must be safe to transfer
  between tasks.
- Concurrent dashboard refresh bookkeeping now has a main-actor owner. The
  independent network waits still overlap, but their shared success and error
  state can no longer be accessed outside its serialized boundary.
- Tests use synchronized counters where callbacks can run concurrently, and
  both the production module and the complete test source set pass a Swift 6
  compiler check without diagnostics.

## Searchable, type-aware alias selection

- Rule and port-forward editors now receive the complete alias catalogue
  already fetched for the active firewall rather than only a set of names.
- Address and target fields offer address-capable aliases; source,
  destination and local port fields offer port aliases. Incompatible alias
  types are not mixed into the wrong picker.
- The alias sheet searches name, type, description, member values and member
  notes, and shows type, description and member count before selection.
- Choosing an alias fills the existing editable field using its exact name.
  Literal IPv4, IPv6, CIDR and port values remain available as free text, and
  opening an existing rule never rewrites its value.

## Quick Block and administrative confirmation hardening

- Quick Block now writes the pfSense internal interface key (`wan`, `lan`,
  `optN`) rather than the physical device name used for traffic counters.
- IPv4, IPv6 and CIDR input is preserved and validated locally and again on
  the firewall. Literal networks use the native `address` shape; the
  `network` shape remains reserved for pfSense system selectors.
- Unknown interfaces, malformed addresses and invalid prefix lengths are
  rejected before configuration changes. Scoped state flushing also rejects a
  device which is no longer available instead of reporting a successful no-op.
- Administrative confirmations now name native system selectors explicitly,
  and audit snapshots include address storage types as well as their displayed
  values.

## Native pfSense address editing and validation

- Rule and port-forward editors now separate Any, literal addresses/networks,
  aliases and pfSense system selectors. Configured interface addresses and
  subnets are offered by their friendly names rather than requiring internal
  values such as `wanip` to be typed.
- Saves preserve pfSense's native `any`, `network` and `address` shapes instead
  of flattening all three into an address. Read-back checks both the value and
  its shape, so a structurally incorrect save cannot be reported as successful.
- The firewall validates the native shape, special selector, alias/address,
  port, protocol, interface and IP family before changing its configuration.
  Ambiguous or unavailable values fail without a configuration write.
- Rule and port-forward validation recognizes configured interface subnet keys
  such as `wan` and interface-address keys such as `wanip` as pfSense system
  selectors rather than user aliases.
- The fixed `self`, `pptp`, `pppoe` and `l2tp` selectors are accepted as well,
  while unknown alias-shaped values remain blocked so spelling errors are not
  silently written to the firewall.
- New port forwards now actually default their destination to the selected
  interface address, matching both the editor's description and pfSense's own
  default behavior.

## Rule insertion and moves use stable anchors

- New and duplicated filter rules can be placed before a selected rule or at
  the end; existing rules can keep their position or be moved explicitly.
- Position requests use the selected rule's stable tracker rather than a
  numeric index. The coordinator rechecks that anchor immediately before the
  write, and the firewall rejects the operation if the anchor disappeared or
  moved to another interface.
- The write response is correlated with the requested placement, and read-back
  verifies the saved rule is immediately before its anchor or last as chosen.
- The editor previews the proposed position and recalculates reachability
  findings against the resulting order before confirmation.
- Reorders have their own protected audit category. New and duplicated rules
  remain disabled by default regardless of their selected position.

## Rule simulation now proves its log is usable

- Opening simulation still fetches the filter log first, but it now checks the
  section's success timestamp and error instead of assuming the retained array
  came from that request.
- A recent last-good sample remains usable after a brief fetch failure only
  with a prominent cached-data warning, its fetch time, the failure detail and
  a retry action.
- A normal sample older than two refresh intervals, a failed cached sample older
  than ten intervals (at least five minutes), or a log that has never loaded
  successfully produces no result. This keeps old or absent data from looking
  like zero matching traffic.
- The freshness policy is deterministic and covered for fresh, cached, stale
  and unavailable samples.

## Creation is now a complete administrative transaction

- Rule and port-forward creation now keep their server-issued tracker from the
  write response and use it for read-back verification, the receipt and the
  protected audit result.
- The coordinator records creates as `add_rule` and `add_port_forward`, while
  edits retain their edit categories and wording.
- Create preflight records the current collection rather than trying to find an
  object whose tracker has not been allocated yet.
- Both pfSense save snippets allocate a collision-safe tracker for creates and
  return it. NAT creation no longer appends an untracked forward.
- A stale edit is rejected server-side instead of silently becoming a new rule.
  NAT edits also retain their original position rather than moving to the end.
- Add and Duplicate failures are shown in the editor instead of leaving Save to
  appear unresponsive.
- The client rejects save responses that omit the tracker, misreport create vs
  edit, or return a different tracker for an edit.

## Rule simulation: reachable, and answering a real question

`RuleSimulationView` was referenced exactly once in the whole tree — by its own
`#Preview`. A complete simulation feature that nobody could open.

It is reachable now, from a rule's More menu, prefilled with that rule. It
answers what `RulePlacement` deliberately refuses to: placement compares rules
to each other by literal value, this compares a rule to packets the firewall
actually logged.

### The engine it replaces produced a meaningless number

`RuleSimulationEngine`'s headline was
`max(matchedAddresses.count + matchedPorts.count, 1)`:

- it added a count of **addresses** to a count of **ports**, which are not the
  same unit and cannot be summed into anything;
- it matched an address appearing as source **or** destination, so a rule from
  A to B counted every host that was A or B and never checked that traffic went
  from one to the other;
- and `max(…, 1)` meant it could never report zero — a rule affecting nothing
  claimed one match.

That figure was shown beside a "risk level" derived from it, immediately before
a write. A plausible number that quantifies nothing is more dangerous than no
number, because somebody believes it.

### What is there instead

Every figure is a count of log lines, and the screen says so. It evaluates the
rule against each logged packet — source, destination, ports, protocol,
interface — and reports what the firewall did with the matching traffic at the
time. That last part is the actionable one: **"12 of those were passed at the
time, so this rule would stop traffic that is getting through today"** is a
sentence the old engine could not produce.

It states where it is blind, next to the number rather than in a footnote:
pfSense logs only the rules with logging enabled plus the default deny, so a
zero means nothing matching was **logged**, not that no such traffic exists.
Matching is literal — a rule naming an alias or a network matches nothing here.
Lines the parser cannot read are counted separately, because a log that failed
to parse and a log with no matching traffic otherwise give the same zero.

Fourteen tests. The first three are the three things the old number could not
do. The fixtures are built from real syslog text at the offsets the parser
documents, because `filterFields` is parsed from the line rather than stored —
a fixture that set the fields directly would test a struct the app never sees.

## Creating and duplicating port forwards

The last round added `create: true` handling to `save_nat_rule` and taught the
coordinator to accept it, and then wired the UI for filter rules only. So the
snippet had a path nothing could reach, and rules could be added from the app
while forwards could not — the dangerous half done and the useful half missing.

- **New forward** on the NAT pane once an interface is selected, and
  **Duplicate** in a forward's toolbar, matching the rule side.
- **A duplicate drops the original's tracker and sets `create`.** This matters
  more for a forward than for a rule: with no tracker, a forward is matched
  back by interface, destination, port and target — and a copy is identical to
  its original in all four. Without the flag, saving a duplicate matches what
  it was copied from and replaces it. Duplicate would have deleted the thing it
  duplicated.
- **A duplicate also clears the destination port.** Two forwards on one
  interface sharing a port is a conflict pfSense accepts and only one of them
  will work — and a copy that keeps its original's port is exactly that, made
  by accident.
- New forwards start disabled and with an empty target, so validation refuses
  to save until somewhere to send traffic has been named.
- Creates go through the same coordinator as edits: rate limit, audit,
  read-back.
- The plus button's switch over the pane is exhaustive with no `default`. A
  third pane added later has to decide what its button does rather than
  silently getting none.

## Creating and duplicating rules

- **New rule** on the Firewall screen, once an interface is selected. It has to
  land somewhere, and asking which interface inside the editor would be a
  question with fifteen answers in a sheet that is already long.
- **Duplicate** on a rule's detail, which opens a copy in the editor rather
  than writing one. It is a starting point, not an action.
- **The firewall assigns the tracker, not the app.** A tracker chosen on the
  phone is chosen against a ruleset fetched some seconds ago, and a collision
  does not append — the save matches it and replaces whatever already held it.
  The snippet generates one with the same collision loop quick-block already
  used, and returns it so the app knows what was made.
- A create sends `create: true` and an empty tracker. For port forwards that
  flag also skips matching entirely: a duplicate is identical to its original
  in every field the NAT fallback compares — interface, destination, port,
  target — so without it, "duplicate" would have matched its own original and
  replaced it. Which is to say: duplicate would have deleted what it copied.
- `WriteCoordinator` still requires a tracker for every save that is not a
  create. An edit without one appends a second copy instead of changing the
  rule, so the requirement stays everywhere else.
- **New and duplicated rules start disabled.** The one thing that cannot be
  undone from a phone is traffic that got through while a rule was being
  written.
- A duplicate's description is marked `(copy)`. Two identical descriptions in a
  list of ninety-eight is how somebody edits the wrong one later.
- The confirmation for a create describes the rule and where it lands rather
  than listing every field as a change, since against nothing every field is
  one.
- Creates go through the same coordinator as edits: rate limit, audit,
  read-back. A create is a write like any other.

### A gate that checked the wrong thing

`write-coordinator` asserted the editors showed a preview by counting the
literal `title: "Review ` twice. That passes for a sheet titled "Review" that
shows nothing, and fails the moment a title becomes conditional — which is what
distinguishing a create from an edit needs. It now counts
`message: changePreview`, which is the preview itself.

## Rule placement, and the conflict detector it replaces

The editor could tell you what a rule would say and not where it would sit.
Rules are order-dependent and pfSense evaluates filter rules `quick`, so the
first match decides — which makes "what is above it" the whole question.

The editor now shows the rule's position among its own interface's rules, and
what precedes it that would catch the same traffic first. The confirmation
sheet repeats it, because that is the last thing read before a firewall
changes.

### `RuleConflictDetector` is gone

It was referenced by nothing, and could not have been trusted if it had been.

- It asked `isShadowedBy(rules[i], rules[j])` with `i < j` — whether the
  *earlier* rule was shadowed by the *later* one. Shadowing runs the other way,
  so every finding it produced named the wrong rule.
- It never compared interfaces. On a firewall with fifteen of them, every pair
  of `any → any` rules on unrelated interfaces reads as contradictory.
- It ignored `disabled`. A rule that is not evaluated cannot shadow anything.

`RulePlacement` answers one question about one rule instead: what precedes it
on its own interface that would match the same traffic. It reports three
things — never reached, already handled the other way, and identical to an
earlier rule — and nothing else.

### It refuses to guess, on purpose

It compares literal values and `any`. It does no subnet arithmetic and does not
resolve aliases, so a `/24` above a host inside it is **not** reported, and the
card says so rather than letting silence read as proof.

A warning shown immediately before a write is read by somebody about to change
a firewall, and one false alarm there teaches them to dismiss the next one.
Silence costs a missed hint; a wrong warning costs the warning system.

Position is counted within the interface, not the whole ruleset — "rule 40 of
98" across fifteen interfaces is a number about nothing. A rule not yet in the
ruleset reads as new and appended, which is where new rules land and rarely
where they are wanted.

Sixteen tests, most of them asserting that nothing is reported. The three
faults above are the first three.

## Lost-response safety and disposable compatibility matrix

- Fixed a critical transport regression: all eight administrative operations
  were calling the read path, whose retry-on-transport-failure policy could
  send a mutation twice after pfSense committed it but its response was lost.
  Writes now use an explicit one-attempt transport.
- A lost response is still written to the encrypted audit as an unknown
  outcome. The app directs the user to inspect pfSense and never treats the
  failure as permission to repeat the action.
- Rule and port-forward save snippets now retain a caller-supplied tracker when
  creating a disposable test fixture, so the object can be found, verified and
  removed safely. The app's normal editors continue to require an existing
  tracked object.
- Added a destructive lab matrix for all eight writes, with exact-host and
  state-loss acknowledgements, one-attempt transport, read-back verification,
  temporary tracked objects, JSON results, and explicit cleanup guidance.
- Added fast `lost-response` and `admin-matrix` gates. No live firewall is
  contacted by the automated suite.

## Credential lifecycle hardening

- Firewall passwords now use `WhenUnlockedThisDeviceOnly`: they are
  unavailable while the device is locked and cannot migrate to another device
  or through a backup restore.
- Existing `AfterFirstUnlock` password items migrate without risking data loss.
  Vaktpost copies the value, reads the protected destination back exactly, and
  deletes the source only after verification. Failed steps keep the original
  for retry.
- Opening the firewall editor no longer reads a saved password into view state.
  Revealing it and replacing it are separate actions, each requiring a fresh
  Face ID or Touch ID evaluation without passcode fallback.
- Removing a firewall and the logout path now require successful cleanup of
  both current/pre-migration Keychain entries and the firewall's encrypted
  administrative history. A failure keeps the profile visible and is reported
  instead of leaving an invisible administrator credential.
- Added migration ordering and accessibility tests plus the
  `credential-lifecycle` repository gate.

## Administrative transactions and durable verification

- All eight firewall mutations now pass through one `WriteCoordinator`; views
  can no longer independently omit rate limiting, binding checks, auditing, or
  verification.
- Confirmations name the active firewall and exact target. Rule and
  port-forward editors show field-by-field change previews before saving.
- The coordinator captures current state and commits a pending audit record
  before sending. It sends each mutation once and reads the affected object or
  subsystem back before reporting success.
- A lost response is reported as an unknown outcome with explicit guidance not
  to repeat the operation until the firewall has been inspected.
- Administrative history is encrypted with AES-GCM, protected by a
  device-only Keychain key and complete file protection, and stored separately
  for each firewall. Settings now provides verification status, retention,
  deletion, and a redacted export.
- Added persistence tests and a `write-coordinator` structural gate that fails
  if a view bypasses the coordinator or the transaction order regresses.

## Staged changes removed

The app had two answers to "what happens when I press Save": the editor wrote
immediately, and `StagedChanges` queued a change for a later batch apply. Both
existed, neither knew about the other, and the queue did not work.

- **A staged change stored no payload.** `Change` held an action, a target
  string, a description and a timestamp, so applying one meant parsing the
  human-readable label back into arguments:
  `target.split(separator: " ")`, `parts[0]` as an address, `parts[1]` as an
  interface.
- **Staged quick-blocks could never be applied.** `stageQuickBlock` set
  `target` to the address alone — one token — and apply guarded on
  `parts.count >= 2` and `continue`d. The change was skipped, counted as
  neither success nor failure, and then `clear()` removed it. Every staged
  block was silently discarded.
- **It could not express the operations that matter.** No case for saving or
  deleting a rule or a port forward. Staging the editor would have meant
  inventing payload storage, which is the whole design — the class was not a
  head start.
- **Its documentation described something that does not exist:** "at apply time
  all changes are sent to the firewall in a single batch, ensuring atomicity."
  Apply looped one at a time, each its own `write_config`, counting failures as
  it went.

Staging earns its complexity when changes are interdependent and applying half
of them is dangerous. This app edits one rule at a time from a phone, and it
already has a rate limiter, a confirmation step, an audit trail with
before/after JSON, and validation that blocks an invalid save. A second,
weaker persistence layer on top of that — one that survived restarts holding
changes it could not apply — was subtracting safety rather than adding it.

Gone: `StagedChanges`, `StagedChangesView`, the More entry, the store property,
`FirewallClient.StagedOperation` and its four `stage*` helpers, and the staging
toggles on Quick block, Flush states and Service manager. `AuditTrail` stays —
it is what staging was half-duplicating, and it records what happened rather
than what was asked for.

If queueing changes offline is wanted later, it needs payload storage,
per-change failure reporting and a story for a firewall that changed underneath.
That is a build, not a retention.

### Found while removing it

- Quick block and Flush states set their progress flag in the button closure
  and cleared it with a `defer` on the same line — and that closure only opened
  the confirmation sheet. The flag was never observed true, so neither screen
  ever showed that a write was in flight. It now wraps the write. Same shape as
  the editor's save bug, in two more places.

## The NAT replace could replace the wrong forward

- `save_nat_rule` was changed in this session from append-only to
  match-and-replace, and matched on interface, destination address and target.
  `PortForward` carries no tracker, so that fallback is the only path — and it
  left out the destination port.
- Two forwards to one host on one interface, 80 and 443 to 10.0.0.5, then match
  identically, and editing either one replaces the other. That is an ordinary
  pair of forwards, not a corner case.
- The match now includes the destination port, which is what `PortForward.id`
  has always been.
- Changing a forward's destination or target still will not match it and will
  append instead. That is a real limitation and the safe direction to fail in:
  a duplicate is visible and removable, a wrongly-replaced rule is neither.

## Build fix: JSONValue could not be written

- `JSONValue` was `Decodable` alone, which was right for as long as everything
  travelled one way. The write path encodes a rule as a base64 payload instead
  of interpolating its fields into PHP, so the type now needs to go out as well
  as come in.
- Encoding rather than a second model on the way out: one representation that
  disagreed with the other about what a number or an empty value is would be a
  bug that only appears on save.
- `.null` encodes as JSON null rather than being omitted. A key that vanishes
  and a key that is null mean different things to pfSense, and the snippet
  decides which fields to drop.

## The write boundary, and what the editors send

### Values were being interpolated into PHP

This is the serious one. The write snippets built their PHP by interpolating
their arguments into it — a rule's description went into the middle of a
double-quoted PHP string, and three of the optional fields were assembled as
*fragments of PHP source*, so the snippet's own shape depended on the values it
carried.

A description containing a double quote ended that string. A description
containing the right quote, a semicolon and a call ran on the firewall, as
root, typed into a text field in the editor.

Arguments now cross as a single base64 payload and are decoded on the other
side. Base64's alphabet is `A-Z a-z 0-9 + / =`, none of which can terminate a
PHP string literal, so the snippet text is fixed no matter what anybody types.
Escaping was the obvious alternative and is the wrong one: it has to be right
every time, in a language whose string rules differ from Swift's, and getting
it wrong looks like working code.

### The gate was switched off rather than updated

`readonly.sh` proved the app could not write, by grepping for `write_config`
and failing on any hit. When the editor arrived that stopped being true, and
the gate was answered with a `READONLY=0` switch that turned the entire suite
off.

That is the worst available shape: the promise is not weakened by it, it is
made unobservable — and a write added by accident looks exactly like the ones
added on purpose. It had been red all along, so a new finding would have looked
like the existing ones.

The writes are named instead, in `PHPSnippet.writeOperations`, and checked in
both directions: a snippet that writes without being named fails, and a name
whose snippet no longer writes fails too. **The list was six when it was
written and the check found two more** — `restart_service` and `flush_states`.
The app's write surface was believed to be six operations and was eight.

The snippet names made that worse: `delete_rule_\(tracker)` and
`save_nat_\(descr)` meant every call produced a different name, so the write
surface could not be enumerated by name at all. They have stable names now; the
tracker is in the audit trail, which is where it belongs.

Three narrower gate fixes came with it: assignment into a validated `$config`
section is no longer treated as an unguarded read, `unset` is permitted on
local arrays and refused on `$config`, and a multi-line constant now ends its
own declaration rather than swallowing everything after it.

### Nothing validated a field

The editors took free text for every address and port and posted it to
`write_config`. `10.0.0.256`, `8100-8000`, an alias that does not exist — all
reached pfSense, and pfSense was the first thing to find out. A rule it refuses
to load is a rule enforcing nothing while the app says "saved".

`FieldValidator` checks addresses, networks, ports, ranges, aliases against the
ones this firewall has, and NAT targets. Save is disabled while anything is
wrong, and every problem is listed at once rather than one at a time. It is
pure and has its own tests, because it is the part with all the edge cases.

The cases worth naming: a reversed port range, which pfSense accepts and which
matches nothing; a port on a protocol that has no ports, which will not load; a
NAT target of `any`, which forwards to wherever the packet was already going;
and an alias name that does not exist, which is the likeliest typo in the
editor and the one that looks most correct.

### Two more write bugs

- **`save_nat_rule` only ever appended.** Editing a port forward added a second
  one and left the original, so pressing Save grew the NAT table every time. It
  matches on tracker, or on interface plus destination plus target where
  pfSense has not given one.
- **`members.sh` resolved members file-wide**, so a `let error: WriteError` in
  one type claimed a `Binding<WriteError?>` parameter of the same name in
  another. Declarations now bind inside their own type, as they do in Swift.

## Two build warnings that were not cosmetic

- **The legacy keychain migration could delete a credential.**
  `Keychain.setPassword` returns a `Result` and it was discarded, then
  `deleteLegacy()` ran regardless — so a failed write removed the only copy of
  the password: signed out, credential gone, nothing said. The old entry is now
  removed only once the new one is definitely stored, and a failure is logged
  and left in place so the next launch tries again. A duplicated credential is
  recoverable; a deleted one is not.
- **`ConfigSnapshot.id` could not survive being decoded.** `let id = UUID()` is
  not overwritten by a decoder, so every snapshot read back from disk got a new
  identity. Two decodes of one snapshot compared unequal, `ForEach` treated the
  same row as a different row after a relaunch, and any diff matching snapshots
  by identity matched nothing. The id is derived from the timestamp and counts
  now — what a snapshot actually is — so it round-trips for free.

## The rule and port forward editors

### Why they were slow to open

- The form was assembled in the detail view's `onAppear`, and the sheet
  rendered `ProgressView("Loading...")` until it arrived. `RuleEditForm(from:)`
  copies a struct out of a rule the view already holds — there was never
  anything to load. The spinner was the entire delay, and on a quick tap it was
  what you got. Both forms are now built at presentation and the loading branch
  is gone.
- Saving set `isSaving = true` with a `defer` that put it back before the
  `Task` inside had started, so the flag was never observed true: no spinner,
  and Save stayed live through the whole write, where a second tap sent a
  second one. The save is awaited, the sheet shows its own progress, and the
  button is disabled while it runs.
- Save is disabled until something changes. An unchanged save is a write that
  alters nothing, spends the rate limit and puts a line in the audit trail
  saying an edit happened.
- On success the sheet closes and the data refreshes. It used to dismiss the
  *detail* view from under its own sheet, so the thing you had just edited was
  the one screen you could not check.

### Theming

- Both editors were bare SwiftUI `Form`s, which is where the theming went:
  `Form` brings its own background, row insets and typography, and none of them
  can be reached from the theme. So the editor arrived in system grey with
  system fonts in the middle of a Catppuccin dashboard. They are now the app's
  own scroll view, slabs and type, grouped into Rule / Source / Destination /
  Options.
- New `EditField`, `EditChoice` and `EditToggle` built from the same tokens
  every other surface uses. Autocorrect and autocapitalisation are off on all
  of them — autocorrect on an address field turns `10.0.0.1` into prose, and a
  typo here is pushed to a firewall.
- Action, protocol, interface and IP version are pickers instead of text
  fields with the accepted values in the placeholder. "Type (pass/block/reject)"
  puts the validation in the hint text, and the firewall is the first thing to
  find out about a typo. Interfaces come from the ones this firewall has.

### Two write-path bugs found on the way

- **The address family was dropped when a rule was saved.** `toDict` derived
  `ipprotocol` by comparing the *transport* protocol against the strings
  "inet" and "inet6", so it was nil for every real rule and the key was left
  out of the payload — saving an IPv6 rule converted it. The family is now the
  rule's own value, carried through the form and always sent.
- **The same fault in port forwards, plus a missing field.** `PortForward` did
  not read `ipprotocol` at all, so the editor guessed it from the protocol and
  always guessed IPv4. A field the app intends to write back has to be a field
  it reads.
- **The interface field was ignored on save.** Both editors offered one and
  both passed the *original* interface to the firewall, so moving a rule or a
  forward between interfaces appeared to work and changed nothing.

## Sections are independent, and there are tests that say so

- The fix for the linked sections was a one-time rewrite of the stored layout,
  which is the right fix and an invisible one: it is impossible to tell from
  the outside whether the sections are genuinely independent now or whether
  another coupling is waiting.
- So the guarantee is asserted end to end through the registry rather than only
  over the migration function. Hiding VPN servers leaves VPN clients. Hiding
  one and then unhiding Status does not bring the hidden one back — the exact
  reported symptom. A legacy layout migrates once and then behaves like any
  other pair, and nothing reintroduces the old name afterwards. Hiding
  everything and adding one back adds one.
- These go through `ServerRegistry` and real `UserDefaults`, because the bug
  was never in the section enum — it was in what storage kept.

## Overview sections appeared to be linked together

- Unhiding Status also unhid both VPN sections. They are not linked; the stored
  layout was.
- Splitting `vpn` into two sections expanded the old name at *read* time and
  left it in storage, which is half a migration. So hiding VPN servers removed
  `vpnServers` — a name that was never stored — while `vpn` stayed behind, and
  the next load expanded it again. Anything that touched the layout brought
  both VPN sections back with it.
- The migration now rewrites storage once, on the first load that finds an old
  name, and writes nothing when there is nothing to change. It is idempotent,
  which matters because it runs on every appearance.
- A name this build does not recognise is kept rather than deleted. It cannot
  be displayed, but it belongs to whoever stored it, and a build that knows
  about it should still find it after this one has run.

## An internal hostname in a test fixture

- `ConflictDetectorTests` used a real internal domain for its DNS override
  fixture. Replaced with `example.se`. A fixture is as public as the source
  around it, which is the lesson the secrets suite already learned once when a
  real WAN address turned up in a test.
- The same habit, one word short of being caught: the expiry notification
  fixtures named a real firewall as their server. Now "firewall".

## Investigate fetches what it searches

- Firewall rules, aliases, port forwards and DNSBL load only when their own
  screens are first opened, so the search was quietly incomplete: "which rules
  apply to this device" answered "none" until somebody had happened to visit
  the Firewall screen. A search screen whose answers depend on where you have
  been is worse than one that takes a moment to open.
- They are fetched on open, and on pull to refresh. Each loader already guards
  against repeating itself, so every open after the first costs nothing.
- Sequentially, not together. pfSense serialises `exec_php` against its own web
  UI, so starting three at once would not finish sooner — it would only make
  the webConfigurator unusable while they queued.
- DNSBL is not forced. It is the only one that reads a megabyte of log, and it
  declines by itself when pfBlockerNG is absent or its DNSBL component is off.
- The coverage note stopped telling the reader to go and open other screens —
  work the screen can do itself. It now says either that the tables are
  arriving, or which of them this firewall has nothing for. An empty alias list
  is a real answer, and calling it "not searched" would send somebody looking
  for a screen that would tell them the same thing.

## Link errors say whether they are happening now

- The counters were already fetched and already on screen, as a field row under
  "Since boot" reading "in 4211 · out 12". That is the number that cannot be
  acted on: four thousand errors on a link that has been up for two hundred
  days is noise, four thousand in the last minute is a cable about to fail, and
  they render identically.
- `InterfaceErrorTracker` keeps the previous reading and reports the
  difference. Errors get their own section on the interface screen — in, out
  and collisions, with whether anything is new since the last refresh and
  roughly how fast.
- **The counters are not guaranteed to only go up**, and everything careful
  about this follows from that. A reboot, an interface bounce or a driver
  reload resets them; subtracting anyway gives a negative, and re-baselining
  wrongly gives a large positive on the reading after. A backwards step is
  reported as a restart and rebaselines, and the reading after it measures from
  the new baseline.
- No rate under ten seconds. Two errors across a two-second poll is "sixty a
  minute", which is a projection rather than a measurement and reads as far
  more alarming than what was seen. It still says errors are rising; it just
  does not invent a rate.
- The first reading reports nothing. A total since boot is not a change, and
  treating it as one would flag every interface on the first refresh after
  launch — the fastest way to make somebody stop reading the warning.
- Interfaces are tracked by device, not description. A description can be
  edited on the firewall and renaming one should not look like a counter reset.
- The interface list shows a warning triangle only while errors are moving, and
  a static total says so in words rather than being left to look like a live
  fault.

## Conflicts: where the firewall's own tables disagree

- A screen under More, badged with the count that breaks traffic. Seven checks
  across ARP, DHCP leases, static mappings and DNS overrides: two MACs on one
  address, ARP disagreeing with an active lease, two static mappings for one
  address, one device with two mappings, a reservation for an address somebody
  else currently holds, one name resolving to two addresses, and two devices
  answering to one name.
- Nothing is fetched. Every check is a comparison between tables the client
  refresh already pulled, so it costs nothing to look at, and it can be wrong
  in only one direction — it can miss something, but anything it reports is two
  records the firewall is holding at once.
- Each conflict says what it means rather than only what it is. "Duplicate
  address" names the fault; "traffic will reach whichever device answered ARP
  most recently, and will move between them" explains the symptom somebody came
  here about.
- Severity is graded, and only the ones that break traffic now are red. A
  duplicate hostname is untidy and frequently deliberate — two leases both
  called `localhost` is not an incident — and grading it the same would teach
  people to skim past both. Only the red ones reach the badge.
- Most of the tests are that nothing fires. A missed conflict costs somebody
  the debugging they were doing anyway; an invented one costs them a hunt for a
  problem that does not exist. So: one device with several addresses, the same
  MAC in different case, an expired lease naming another device, a static
  mapping matching its own static lease, a laptop that changed subnet, and a
  missing MAC — where `DHCPLease` substitutes an em dash, and two absences
  would otherwise read as two devices.
- Each conflict links through to Investigate with its subject filled in.
- The limit is stated on the screen: it only sees what the firewall records, so
  a device with a hardcoded address that has never spoken is not in the ARP
  table and nothing here will know about it. A clean result is not proof of a
  healthy network.

## Investigate: one box, everything that references an address

- A screen under More, and a link from any client's page with the address
  already filled in. Type an address, a MAC or part of a name and get the
  client, its ARP entries and leases, static mappings, DNS overrides, VPN
  connections, aliases, firewall rules, port forwards and DNSBL counts — in
  one list, grouped in reading order.
- **It asks the firewall nothing new.** All of this was already fetched and
  already searchable, just behind six separate search boxes on six screens, so
  the question people actually ask took five visits and a good memory.
- **The answer nothing else in the app gives**: which firewall rules apply to a
  device. A rule names an alias, the alias holds the address, and no single
  screen makes that connection. Aliases are resolved first and their names
  carried into the rule and NAT walk, and every such result says "via alias
  SERVERS" — a result somebody cannot account for is one they have to go and
  verify, which is the work this was meant to save.
- **Addresses are matched exactly, never as substrings.** Both sides are
  normalised, so equivalent IPv6 spellings match and "10.0.0.1" does not match
  "10.0.0.100". Fields are split into tokens first, because firewall fields
  hold lists; a `/32` or `/128` is treated as the host it names, which is how
  WireGuard writes its allowed IPs.
- No subnet arithmetic, and the tests pin that: a `/24` rule is not reported as
  applying to a host inside it. Claiming otherwise would be a guess dressed as
  a result.
- The screen says which tables have not been fetched yet. Several load only
  when their own screen is first opened, so an empty result can mean "nothing
  references this" or "the app has never asked", and a search that cannot tell
  those apart is worse than one that admits it.

## VPN cards: servers stop counting clients, clients stop listing absentees

- A server row said "2 connected". `statusLabel` falls back to a count of
  connections when the endpoint reports no status field, which is what 26.07
  does — so the servers card was answering the clients card's question. A
  server that appears in `status/openvpn/servers` is running, and that is what
  it says now.
- Client rows are one line: a health dot, the name, where it sits on the
  tunnel, and the bytes each way. The endpoint and the connect time are gone —
  four connected devices at three lines each was most of a screen, and a
  dashboard card is a glance rather than a report. Both are on the VPN screen,
  a tap away, which is where somebody looking for them is going anyway.
- The address yields before the transfer figures when the row is tight. A
  truncated address is still recognisable; a truncated byte count is wrong.
- WireGuard peers now need a handshake inside five minutes to count as
  connected, not merely to have handshaken once. A laptop that closed its lid
  yesterday keeps its timestamp, so the card was listing peers last seen
  eighteen hours and a day ago under a heading about who is connected. Five
  minutes is the right threshold because WireGuard rehandshakes roughly every
  two while traffic flows. The VPN screen still lists them with last-seen
  times.

## The two VPN sections now answer their own questions

The first split was wrong. Servers showed peer and connection counts — the
clients' question wearing the servers' title — and clients listed OpenVPN
*client instances*, the outbound tunnels a firewall dials, which most firewalls
have none of. So one section said what the other should and the other said
nothing at all.

- **VPN servers** is about the servers: name, state, listen port, and the bytes
  that have gone through. One row per OpenVPN server, WireGuard tunnel and
  IPsec association.
- RX and TX are summed from the connections for OpenVPN, because the server
  endpoint reports no totals of its own; WireGuard reports the tunnel's own
  counters. Both are totals since the daemon started, not rates, and are
  labelled as such rather than left to be mistaken for throughput.
- IPsec carries its remote host and state instead of the same columns filled
  with dashes. It reports neither a listen port nor byte counters here, and
  padding a row to match its neighbours implies a reading that does not exist.
- **VPN clients** is now who is connected, across every server, busiest first:
  common name, tunnel address, where they came from, what they have moved, and
  how long they have been on.
- WireGuard peers appear there only once they have handshaken. A configured
  peer that has never connected is not a client, and listing them would put a
  row for every key ever issued above the people actually on the VPN.
- Nobody connected is `info`, not `warn`. A remote-access VPN with no one on it
  at four in the morning is working exactly as intended, and a card that goes
  amber for that teaches people to ignore the colour.

## VPN on the dashboard is two sections now

- **VPN servers** — what this firewall hosts and who is connected to it:
  OpenVPN servers, WireGuard tunnels and peers, IPsec associations.
- **VPN clients** — what it dials out to. Each OpenVPN client is named with its
  own status rather than counted, because on a firewall that routes traffic
  over a provider, *which* tunnel is down is the whole answer. "1 of 2 active"
  makes you open another screen to learn nothing more.
- They answer different questions and were sharing a card. One is "can people
  reach me", the other is "is my own tunnel still up", and the second used to
  be three lines down inside the first.
- Health is per section. A combined figure meant one down outbound client
  turned the whole card amber and a perfectly healthy server could not say so.
- IPsec and WireGuard sit under servers. Neither has a server and a client in
  pfSense's own terms — both are peer to peer, both terminate on this firewall,
  and both are things it provides rather than things it dials out to.
- The stored layout is a list of raw names, and an unknown one is silently
  dropped, so `vpn` maps to both replacements on load. Without that, splitting
  the section would have removed VPN from the dashboard of everybody who had it
  and put the two new sections in the hidden list to be found by hand.

## A donut for the DNSBL breakdown

- On the DNSBL screen and on the Overview card: the share each domain took of
  everything blocked, six slices on the screen and four on the dashboard, with
  the total in the hole.
- A donut rather than a pie because the hole is where the total goes, and the
  total is what makes the slices mean anything — 33% of nine requests and 33%
  of nine thousand are the same wedge and not the same fact.
- **The remainder slice is the part that makes it honest.** The counts are a
  top-twenty and the total is every event, so a chart built only from the rows
  would describe the top twenty while looking like it described the whole. The
  total is passed in separately and anything unaccounted for becomes "Other".
- Hand-drawn with `Path`, like `Sparkline` and `RowTrace`, rather than pulling
  in Swift Charts for one shape. Colours come from the flavour's own accents,
  ordered to keep neighbouring hues apart, so it looks right in all four
  themes.
- Slices under about four degrees keep their hairline gap rather than being
  swallowed by it — a thin wedge beats a missing one.
- The chart is one accessibility element reading the top five as percentages.
  A screen reader gets the reading rather than a description of a circle, and
  the legend beside it is hidden so it is not read twice.

## pfBlockerNG was wrong about two things at once

- **DNSBL always reported as switched off**, on a firewall whose `dnsbl.log`
  was 52 KB and being written to that minute. `pfb_dnsbl` was read from the
  main pfblockerng settings, where it does not exist. It lives in a separate
  package section, `pfblockerngdnsblsettings`, which is where pfBlockerNG's own
  code looks for it. The DNSBL mode comes back with it now.
- **Every list reported "not loaded"**, on a firewall where every list was
  loaded and working. The counts asked pf directly through
  `pfSense_get_pf_table` or `pfr_get_table_addrs`, and on pfSense Plus neither
  function exists — so the screen said no list could be counted and meant it.
- Counts now fall back to where pfSense's own alias screens get them. A
  `urltable` alias keeps its addresses in `/var/db/aliastables/<name>.txt`,
  which is the file pf is loaded from; other types keep theirs inline in the
  configuration. A port alias such as `DNSBL_Ports` has neither a pf table nor
  a table file, so "not loaded" was describing something that never exists for
  that type.
- Each count says which of the three answered — the running firewall, the file
  it loads from, or the configuration — because they are not the same claim. A
  list written but not yet applied counts from the file and would not count
  from pf, and the screen says which it is looking at rather than implying the
  stronger one.
- The pf accessor is still preferred where it exists. Its absence is no longer
  a warning: it is the normal case on Plus.

## The lock screen asked for a face at the wrong moment

- Returning from the background showed "The operation couldn't be completed.
  (com.apple.LocalAuthentication error 6.)" with two buttons, instead of
  prompting.
- The prompt was fired the instant the lock became required, and that is
  `.background` — the app is on its way out, nothing can be presented, and
  `evaluatePolicy` fails immediately with an error about the *request* rather
  than about the person. By the time the app came back, the prompt had already
  failed; the screen was showing the result of an attempt made while it was
  off-screen.
- Face ID has to be asked for while the app is frontmost. The prompt now waits
  for `.active` and nothing else.
- `hasPrompted` guards against the second half of that: presenting the system
  sheet makes the app inactive and dismissing it makes it active again, so
  "became active" fires more than once per unlock. It is cleared on a real
  backgrounding, so the next foreground is a new unlock.
- `LAError.invalidContext` and `.notInteractive` join `systemCancel` and
  `appCancel` as outcomes that are not failures. They mean the request was
  made at the wrong time, not that a face was rejected, and they were landing
  in the default branch and being reported as a failed attempt — which is what
  put that error on screen rather than something a person could act on.
- A cancelled outcome now clears the message and re-arms the prompt, so a lock
  screen cannot end up sitting there having given up.

## DNSBL block statistics

- A screen behind pfBlockerNG, and a section on the Overview dashboard: how
  many requests DNSBL refused, the busiest domains, which clients asked for
  them, which feeds and groups matched, and an hourly bar chart. The same
  numbers as the package's own DNSBL Block Stats page.
- Computed from the same file that page uses, `/var/log/pfblockerng/dnsbl.log`,
  whose format is documented in pfBlockerNG's own source. That page shells out
  to `cut | sort | uniq -c`; this reads the tail of the log and counts in PHP,
  which needs no process and no allowlist entry beyond a sort.
- **Only the tail.** A busy DNSBL log runs to tens of megabytes and reading it
  whole would die on PHP's memory limit, which is indistinguishable from an
  empty log. The window is the last megabyte, and the screen says when the log
  is bigger than that — a total that silently means "some of it" is worse than
  no total.
- Hour labels stay as text. pfBlockerNG writes its timestamps with no year, so
  anything building a date from "Sep 3 01" would be inventing one, and would
  invent the wrong one for a log spanning New Year. They are kept in the order
  the log has them, which is chronological because the file is append-only —
  sorting them by name would put "Sep 9" after "Sep 10".
- Clients are named from the ARP, lease and override tables, the way every
  other address in this app is.
- Gated at three levels, saying something different at each: the package is not
  installed, the package is installed and DNSBL is off, and DNSBL is on with an
  empty log. The link from the package screen appears only when DNSBL is
  enabled, because a link to a screen that can only say "this is switched off"
  is worse than no link.
- The Overview section is always in the list rather than appearing with the
  package. Somebody installing pfBlockerNG later should not have to find a
  hidden section to turn it on; the card explains itself instead.

## Less prose under the traffic list

- The four explanatory paragraphs are gone — the capture interval, the ten-host
  cap, what a row's trace means, and what Local means on a WAN. All true, all
  read once, and then sitting under a live screen forever.
- The constraints they described are still documented where they are of use to
  somebody changing the code rather than somebody watching a graph: the capture
  and its limits in `PHPSnippets.hostTraffic`, the rest in `TrafficView`'s own
  header.
- What stays is the line carrying whatever pfSense wrote when it returned no
  rows. It only appears when the list is empty, and when the list is empty it
  is the only thing on screen that says why.
- The one-line reason under the filter control also stays. It appears only on a
  WAN or a tunnel, where the default is not the obvious one.

## Two things found while reviewing this session's own code

- The store accepts an injected `UserDefaults` so a test can have its own, and
  then handed neither of its two new children one — both reached for
  `.standard`. A test touching the notification setting changed it for the
  person running the tests. They take the store's now.
- The top-talker record encoded and wrote itself on the main actor every five
  seconds. It is a dictionary of value types, so a copy goes to a detached task
  and is encoded there. The moment this cost the most was the moment the app is
  drawing a live trace, which is the worst possible time to stall the main
  thread.
- Retention was seven days and nothing else, which is not a bound: seven days
  across fifteen interfaces is thousands of hourly buckets, all re-encoded on
  every save. There is a ceiling of 600 hours now, oldest dropped first.

## What is actually scheduled

- The notification count in Settings is now a link to the list behind it:
  every pending notification, grouped by firewall, with its title, the
  certificate it is about, how many days before expiry it fires, and the exact
  date and a relative one.
- Read back from iOS rather than from anything the app remembers. A list built
  from the app's own intentions would agree with itself and tell nobody
  anything — and iOS silently drops requests past its 64-per-app limit, which
  is exactly the disagreement worth being able to see. Over about 56 pending,
  the screen says so.
- Grouped by firewall, and the grouping is parsed out of the identifier rather
  than remembered, so a notification is still attributable after its firewall
  stops being the active one or is removed entirely.
- A trigger that will not resolve to a delivery date is called out rather than
  shown as a dash. It is the one entry worth chasing.
- A "Reschedule from this firewall" button forces the reconcile that normally
  happens on refresh, and the screen says what it does and does not touch: a
  certificate renewed since its notifications were scheduled keeps the old
  dates until something reconciles them, and reconciling one firewall must
  never cancel another's.
- Reconciling is the part of that feature most likely to be quietly wrong — it
  runs on every refresh, removes by identifier prefix, and until now there was
  no way to see what it had done.

## Crash fix: top talkers trapped on the third capture

- The recorder put entries into its dictionary under a normalised address key
  and rebuilt that dictionary from storage under the raw address. The two never
  matched, so every lookup missed, every capture added a second entry for a
  host that was already there, and the third capture handed
  `Dictionary(uniqueKeysWithValues:)` two entries of the same address — which
  traps. A crash on the third capture of any interface with anything on it: six
  seconds at a two-second interval, forty-five at fifteen.
- The key is now a property of the record, computed one way and used on both
  sides.
- Both uses of `Dictionary(uniqueKeysWithValues:)` are gone. That initialiser
  traps on a duplicate key, which is fine over a literal somebody wrote and a
  crash waiting to happen over anything else — and both of these were over data
  the app does not control: its own stored file, and whatever a firewall's
  package repository returns. They merge now, so a bad file costs accuracy
  rather than the app.
- The quieter half of the same bug: because every lookup missed, each capture
  replaced a talker's stats rather than folding into them, so every entry read
  as a single sample however long a screen had been open. Peaks and means are
  real now.
- The traffic list deduplicates rows by identity before drawing them. `ForEach`
  over duplicate ids is undefined behaviour and the identity comes from an
  address the firewall chose, which this app does not get to assume is unique.

## Build fix

- `fetchSection` did not handle `Section.pfblocker`. It joins the other
  sections that are loaded when their own screen opens rather than by the
  refresh — HAProxy, ACME, RRD — and does nothing there.

## Build fix

- Reconciling expiry notifications used a nested `contains` whose inner closure
  named its own argument, leaving a `$0` in it with nothing to refer to. It is
  a set lookup now, which compiles and is also the right shape: this runs once
  per refresh over every pending notification on the device.

## The lock screen asked for nothing, and asked too late

Three faults, compounding into one symptom: returning to the app showed the
dashboard, then a Face ID sheet that flashed up and let you straight in.

- **The `LAContext` was shared.** It was a `static let` reused by every call,
  and an `LAContext` holds the result of a successful evaluation — evaluate the
  same policy on the same context again and it returns success immediately
  without prompting. The system sheet still appears for an instant as it is
  created and torn down, which is exactly what it looked like. There is now a
  fresh context per evaluation, as Apple's guidance says, with reuse duration
  pinned to zero.
- **Locking was driven off `.active`, which is too late.** iOS takes the
  app-switcher snapshot at `.inactive`, so by the time a lock screen appeared
  on `.active` the dashboard had already been photographed and shown. The cover
  now goes up at `.inactive`.
- **`.inactive` was treated as backgrounding, and presenting a Face ID sheet
  makes the app inactive.** So authenticating set the "went to background"
  flag, and succeeding immediately re-armed the lock: authenticate, go
  inactive, authenticate again. Covering and locking are now separate states —
  `.inactive` covers the screen and asks nothing, `.background` locks.

Alongside those:

- A re-entrancy guard, because two evaluations at once produce two system
  sheets and the second tearing down the first is another route to a prompt
  that flashes and vanishes.
- `LAError.systemCancel` and `.appCancel` are no longer reported as failures.
  They mean iOS took the sheet away, not that a face was rejected, and saying
  "authentication failed" to somebody whose face was never looked at is both
  wrong and alarming.
- A passcode fallback, which the failure message had been promising and the
  code never offered. Biometry locks out after five failed attempts and stays
  locked until a passcode unlock, so a lock screen offering only biometrics
  could shut somebody out of this app entirely. The unused `usingPasscode`
  state is now reachable.
- Auto-refresh restarts on `.active`. It was stopped on `.inactive` and never
  started again, so pulling down the control centre silently ended automatic
  refreshing until the app was relaunched.
- The four `print` statements left in the scene-phase handler are gone.

Not verifiable outside a device: biometry needs real hardware and a real
enrolment, so this is reasoned from the LocalAuthentication contract rather than
observed. Worth testing the interrupted cases specifically — background the app
while the sheet is up, and fail Face ID five times to reach the passcode path.

## Search in the traffic list

- The same `InlineSearchField` the Clients list uses, matching on the address
  and on every name the firewall knows the device by rather than only the one
  that won the title — a device shown as its DNS override stays findable by the
  description on its static mapping.
- Ten rows do not need searching for their own sake. What it is for is the
  question the list cannot answer by being read: whether one particular device
  is in the ten right now. Typing its name and watching the row appear and
  disappear across captures says that; scanning ten changing rows for it does
  not.
- A search that matches nothing gets its own sentence rather than falling
  through to "nothing measured", which would be false — something was measured,
  it just was not this. The sentence carries the same ambiguity the list always
  has: absent from the ten is usually idle and is sometimes crowded out, and a
  search cannot tell which.
- It narrows what is shown and never what is measured. The captures, the row
  traces and the hourly record are all unaffected, and the firewall's own
  output is only surfaced when the capture itself came back empty rather than
  when a search filtered it away.

## pfBlockerNG

- A screen under More, following the same installed / not-installed shape as
  HAProxy and ACME: enabled state, DNSBL state, every `pfB_` alias, and how
  many addresses pf currently holds for each.
- **Counted from pf, not from the package's files.** A feed file on disk says
  what was downloaded; a pf table says what is loaded into the running
  firewall, and those differ whenever an update has been fetched and not
  applied. The app already had an accessor for pf tables, so the headline
  number needs nothing new on the firewall.
- A list with no pf table reads as "not loaded", never as zero. Both look the
  same on any screen that prints a number and only one of them means traffic is
  getting through, so unloaded lists are called out separately and left out of
  the blocked total.
- Installed is decided on the filesystem, not on the config section. A removed
  package leaves its settings behind and a screen reading those as installed
  would show zeros indefinitely.
- Paths are probed rather than assumed. pfBlockerNG and pfBlockerNG-devel keep
  their logs and databases in different places, and the result reports which
  were found so the screen can say what it is looking at.
- Logs are described, not read — name, size, and when they were last written.
  A busy firewall's block log runs to hundreds of megabytes, and pulling it
  across the wire to count lines would cost more than the count is worth. A log
  untouched for days is a component that is not running, which is the question
  somebody actually has.
- Loaded when the screen opens rather than on the refresh timer. Most firewalls
  do not have the package and every one of them would otherwise pay for the
  question every thirty seconds.

## Top talkers, hour by hour

- Every capture the traffic screens take is now folded into a rolling record of
  the busiest addresses per interface per hour, reachable from History on the
  traffic screen. Kept for seven days, at most 20 addresses an hour, persisted
  so it survives a relaunch.
- **It only knows what it was watching, and the screen says so.** Captures come
  from screens that run while they are open: iOS does not let an app poll a
  firewall in the background, and a one-second packet capture is not something
  to ask of a background refresh even if it did. So the gaps are hours nothing
  was watching rather than hours nothing happened, and coming back in the
  morning to ask what saturated the line at 3am is the one thing this cannot
  answer unless the app was open at 3am. The screen points at pfSense's own
  Monitoring for interface totals and at ntopng for unattended per-host work.
- Coverage is carried per hour and shown under each summary — how many captures
  and the span between the first and last. Three captures at 2:05 and three
  hundred spread across the hour produce the same list and are not the same
  claim. It is stated in captures and span rather than as a percentage, which
  would imply the gaps between captures were measured.
- An address missing from a capture is not folded in as a zero. pfSense returns
  ten addresses and a different ten each time, so a device crowded out was not
  necessarily idle and counting it as silent would drag its mean down for being
  unlucky.
- Names are resolved at record time. Resolved at display time, a device that
  has since left the network would lose its name exactly when somebody is
  looking it up.
- Rates are what an address was doing at the moment of a capture. They are not
  totals transferred, and the screen says so — multiplying instantaneous rates
  by elapsed time would produce a number this app cannot support.
- The per-client trace feeds the same record. It takes the same capture and
  gets the interface's whole top ten back, so there was no reason to discard
  the rest of it.
- Clearing is offered on the screen. A record of which devices were busy and
  when is the most personal thing this app keeps.

## Certificate expiry as a notification

- Certificates now schedule local notifications 30, 14, 7, 3 and 1 days before
  they expire, at 9am local time, each naming the firewall it belongs to.
- This is the only alert this app can deliver while it is not running, and the
  reason is worth stating: everything else on the Alerts screen is derived from
  status the app has to ask the firewall for, and an app that is not running
  cannot ask. A certificate says months in advance exactly when it becomes a
  problem, so the notification is scheduled for that date and arrives whether
  or not the app is ever opened again.
- Off until switched on, and permission is requested at that moment rather than
  at launch. A prompt on first run, before the app has shown what it would use
  it for, is the reliable way to be refused permanently. If permission was
  refused later in iOS Settings the toggle says so, because a switch that is on
  and does nothing is worse than one that is off.
- Thresholds already passed are not scheduled. Otherwise every known expiry
  would arrive at once the first time this was enabled, which is how somebody
  learns to dismiss these without reading them.
- Pending notifications are reconciled on every refresh, scoped to the active
  firewall's identifier prefix. A renewed certificate has a new expiry and its
  old schedule is now a lie; without the removal, renewing would leave an
  "expires in 7 days" pending that arrived on time for a certificate replaced a
  month earlier. Namespacing by firewall means reconciling one never cancels
  another's.
- Skipped when the certificate fetch failed. An empty list from a failed
  request looks exactly like a firewall with no certificates, and acting on it
  would cancel every pending notification because one call timed out.
- Identity is the reference ID, not the description. pfSense does not stop
  anybody calling two certificates the same thing, and one silently replacing
  the other's schedule would mean the second expiring unannounced.

## Build fix

- The traffic row's name and address are selectable only where the row does not
  navigate, and that was written as one modifier taking a ternary between
  `.disabled` and `.enabled`. Those are two types, not two cases, so it did not
  compile. Split into two branches applying the modifier or not.

## Throughput was labelled in two units at once

- `ThroughputTracker` is built twice: for interfaces it multiplies byte
  counters by eight and holds bits per second, and for VPN tunnels the
  multiplier is one and it holds bytes per second. Nothing carried which was
  which, so it had to be remembered at every call site, and it was not.
- `ThroughputChart` fed the interface tracker's bits into `Sparkline`, which
  labelled both its y-axis and its tooltip as bytes — directly above a
  `RateLegend` reading the same sample as bits. Two numbers on one card, 8.4x
  apart: eight for bits against bytes, and again 1024 against 1000.
  `InterfaceComparisonView` had the same fault, with a bytes tooltip over a
  bits legend in the same file.
- The unit now travels with the data. `ThroughputTracker` exposes it, derived
  from the multiplier so the two cannot disagree, and `Sparkline` takes it as a
  parameter. A caller passing `tracker.unit` cannot get it wrong.
- The VPN row was already correct and is unchanged; it reads a bytes tracker
  and formats bytes.

## The interface picker is grouped

- Uplinks, Networks and Tunnels, instead of fifteen entries in pfSense's config
  order with two uplinks, five tunnels and eight VLANs interleaved into a list
  you had to read all of. The three kinds answer different questions.
- The slot travels with the entry rather than being recomputed from the
  grouped order. Grouping changes what is shown and must not change what is
  sent — otherwise the app samples one interface and labels it with another's
  name, which is the failure the result already carries a check against.
- Order within a group is pfSense's. Sorting by name would look tidier and
  would mean the menu rearranged itself whenever an interface was renamed.
- Empty groups are dropped, so a firewall with no tunnels gets no heading for
  them.

## Each interface starts on a filter that returns something

- Opening a WAN or a tunnel used to show an empty list, and an empty list reads
  as a broken screen. On both of those the empty list is exactly what Local
  correctly returns: a tunnel is point to point and has no local subnet for the
  capture to scope to, and a WAN's local subnet is the link to the ISP rather
  than anything on the network. Tunnels now start on All and interfaces with a
  gateway start on Remote.
- Classified structurally, not by name. A tunnel is recognised by its device
  prefix — `ovpn`, `tun`, `wg`, `ipsec`, `gif`, `gre` and so on — and a WAN by
  having a gateway, which is what makes an interface a WAN in pfSense's own
  terms. The description is deliberately not consulted: "WAN_2" is a
  convention, not a fact, and a LAN somebody named badly should not be
  classified by its label. Where the gateway is absent this falls through to
  Local, which is what the screen did before.
- The device prefix is checked before the gateway, because a tunnel usually has
  a gateway too and being a tunnel is the stronger fact.
- A one-line reason appears under the control where the default is not the
  obvious one, and nothing at all on a VLAN, where a line explaining that Local
  means local would be noise on every visit.
- It is a default, not an override: applied when the interface changes, and a
  filter chosen by hand afterwards survives until the interface changes again.
- The per-client trace follows the same rule. It was hardcoded to Local, which
  was right for a device on a VLAN and wrong everywhere else — a device reached
  over a tunnel would never appear in a capture, and the card would report it
  idle indefinitely.

## A trace on every traffic row

- Each row in the host traffic list carries the last twenty captures as a small
  two-direction trace. A single instantaneous number cannot tell a device that
  is winding down from one that is ramping up, and at a fifteen-second interval
  two consecutive glances are a long way apart.
- Scaled to the row's own peak rather than the list's, because the question a
  row-sized trace answers is which way that one is heading. Against a shared
  scale every row but the busiest would be a flat line along the bottom. The
  two directions do share a scale with each other, so a device downloading at
  5 Mbit and uploading at 3 kbit is not drawn as two similar lines.
- A row that falls out of the top ten carries a zero rather than a gap, so it
  is drawn winding down rather than vanishing, and is forgotten once its whole
  window is zeros. Without that, a firewall left on this screen accumulates a
  trace for every address that has ever been busy on the interface.
- `RowTrace` is a new view rather than the existing `Sparkline`, which carries
  axis labels, gridlines and a tap-to-inspect tooltip — right for a card, wrong
  for a strip under two numbers, and its tap gesture would fight the link the
  row now is.
- Traces are keyed by normalised address and cleared when the interface, filter
  or sort changes. Two spellings of one IPv6 address would otherwise be two
  half-empty traces, and the previous run's history describes a different
  question.

## Host traffic rows open their device

- A row in the traffic list is now a link to that device's investigation page,
  where the firewall recognises the address. Both screens live in the Clients
  tab and describe the same devices, so "172.16.1.10 is pulling 5.63M" and that
  device's leases, names and filter log were one tap apart in principle and
  several in practice.
- The lookup goes through the MAC when a direct address match fails. The client
  list shows one address per device and a capture can catch it on another, which
  would otherwise be a row that looks tappable and refuses to open.
- Rows the firewall does not recognise stay as they were, with no chevron. On a
  WAN that is most of what a capture returns, and a link to nothing is worse
  than no link. Those rows keep selectable text; linked rows do not, because
  text selection swallows the tap.

## Housekeeping

- The `interfaces` snippet had two lines assigning `inbytes` and `outbytes` to
  themselves, under a comment claiming they were being set from the same call
  the counters snippet uses. It is the same call, so the assignments did
  nothing and the comment described an intent the code never had. Both gone;
  `counters_present`, which distinguishes "this interface has no counters" from
  "no second sample yet", is the part that was doing the work.
- SECURITY.md now accounts for `printBandwidth`. That file is the honest
  account of what the XML-RPC transport gives up against the REST build, and it
  was one entry out of date: the allowlist had gained something that spawns a
  packet capture. It gets its own paragraph — what bounds it, and what somebody
  weighing this app against a production firewall should know. Two other claims
  there had quietly gone stale: snippets are no longer all `static let`, and the
  log reader is no longer the only one taking parameters.
- The five working-note markdown files moved out of the repository root into
  `docs/`, with a README saying what each is and pointing at CHANGELOG.md
  first. `layout.sh` had been warning about them on every run, and a warning
  nobody acts on teaches people to skim the suite output — which is how a
  switched-off gate went unnoticed for months.
- `swiftlint.yml` is now `.swiftlint.yml`, the name SwiftLint actually looks
  for. Without the dot it was only ever found because the Makefile passed it
  with `--config`; anything else invoking SwiftLint in this tree silently
  linted with defaults.

## Host traffic

Per-interface host traffic — the table under Status > Traffic Graph in the
webConfigurator — now works. It never had.

- The snippet behind the Traffic screen read `ifhosttraffic` off
  `get_interface_info()`. pfSense has no such key in 2.6, 2.7 or current, and
  as far as the source history goes it never has, so the screen was blank on
  every firewall it was ever pointed at. Replaced with a call to pfSense's own
  `printBandwidth()`, which is what `status_graph.php` polls to fill that
  table.
- The screen is now per interface, with the same Local / Remote / All filter
  and Bandwidth In / Out sort the webConfigurator offers. Addresses are resolved
  to names from the ARP, DHCP, static mapping and DNS override tables the app
  already holds — pfSense can name hosts itself, but only by replacing the
  address in the same column.
- It lives in the Clients tab, as a Devices / Traffic switch above the list,
  rather than behind More. "Which devices are on this network" and "which of
  them is using it" get asked in the same breath, and three taps apart meant
  the second one mostly went unasked. The device list keeps its own All / Seen
  / Static filter underneath.
- The host list updates continuously with no button, refreshing every three
  seconds, as does the per-client trace. Both are periods measured start to
  start rather than pauses between captures, so the interval holds steady
  instead of drifting with how busy the firewall is, and the trace's time axis
  means something. Changing the interface, the filter or the sort cancels the
  capture in flight and starts a new run, so a result from the previous
  question never sits under a changed control.
- The interval is a control rather than a constant: 2, 5, 10 or 15 seconds,
  defaulting to 15, stored and shared with the per-client trace so one firewall
  is never polled on two schedules at once. The right number depends on what is
  being watched for and on what else the firewall is doing, which is not
  something the app can decide. The floor is not a preference — below about a
  second and a half the captures queue faster than they complete — so two
  seconds is the shortest offered, and on a busy firewall that setting is
  effectively continuous polling rather than a two-second interval.
- Busiest by In / Out is a control rather than a re-ordering, because pfSense
  truncates to ten hosts *after* sorting — switching it can return a different
  set of devices, not the same ones in a different order. The rows are sorted
  locally as well, on the same column with a stable tie-break, so the list
  cannot disagree with the control above it and rows stop swapping places
  between captures for no reason. The column being sorted on is emphasised.
- A failed capture no longer blanks the screen. The last good reading stays
  visible with the error above it, and the loop backs off — four seconds, then
  eight, capped at fifteen — rather than either giving up or hammering a
  firewall that is already struggling.
- The proportion bar is gone from the host rows. It was scaled against the
  busiest row in the capture, and pfSense returns whichever ten hosts happened
  to be busiest, so its full width meant a different rate every three seconds
  and a row could shrink while its own throughput rose. The numbers are the
  measurement.
- The Traffic pane takes the full width rather than sitting in the split view's
  list column, so on iPad it is not a narrow sampler beside an empty pane
  advising you to choose a device.
- Still reachable from each interface's detail screen, which pushes it as a
  screen of its own with a title and a back button rather than switching tabs
  underneath the person.
- A client's investigation page now has a Traffic now card. It resolves the
  device's interface from the client list, the ARP table or its lease, samples
  that interface, and looks for the device in the result — sorted the other way
  as well when the first capture does not find it, because the sort decides
  which hosts survive pfSense's truncation. The second capture is only paid
  when the first came up short.
  It updates continuously while the card is on screen and draws a live trace,
  with no button to press.
- The floor on that interval is set by the measurement rather than chosen.
  `rate` needs a full second of wall clock to produce one report and each poll
  is an `exec_php` that pfSense serialises against its own webConfigurator, so
  asking much faster would queue requests faster than they can complete.
- A device that is not in the returned list plots as zero, which is the honest
  shape for a live trace. What that zero cannot distinguish is idleness from
  ten busier neighbours, since pfSense returns ten addresses, so the card says
  so in a line beneath the trace whenever the last sample did not find the
  device.

**This costs the firewall a one-second packet capture per sample.** There is no
per-host counter on pfSense; `printBandwidth` shells out to `/usr/local/bin/rate`
and asks for one report. So nothing is sampled until it is asked for, automatic
refresh starts switched off and runs at five seconds rather than the web UI's
three, and the interface detail screen links to this rather than embedding it.

`printBandwidth` reports its own two failures — an interface it cannot resolve,
and a capture that found nothing — by echoing a translated phrase into the
output it otherwise fills with rows. Nothing matches on those phrases. Every
condition the app acts on is established before the call instead, including
whether the interface has a device behind it at all, and whatever pfSense wrote
is shown verbatim rather than parsed.

Two limits are pfSense's rather than the app's, and are stated on screen:
at most ten hosts per sample, and a sort that decides which hosts survive the
truncation rather than only their order.

`printBandwidth` is the one entry on `allowedFunctions` that is not a counter
read. The branch it takes only reads; the branch that kills processes and
unlinks files is reachable only through a `mode` argument the snippet never
passes, and there is a test asserting it stays that way. The interface is
chosen by clamped index into `get_configured_interface_with_descr()` rather than
by name, so no runtime string reaches the PHP, and the resolved key comes back
in the result and is checked against the interface that was asked for.

## Offline MAC vendor lookup

- Added a bundled 1.6 MB index built from the official IEEE MA-L, MA-M, MA-S and legacy IAB public listings.
- Client investigations now show the manufacturer, assignment type and registered prefix without sending MAC addresses to another service.
- Locally administered, randomized and multicast addresses are identified before lookup.

## Incident timeline

- Added a unified, chronological view of firewall, system, authentication, DHCP and OpenVPN events.
- Added severity, source and text filters, per-source freshness, partial-failure handling and full-entry navigation.
- Added timestamp normalization for structured, Unix and syslog dates.

## Unreleased — XML-RPC transport

Replaces the pfSense REST API package with pfSense's built-in XML-RPC service.
Nothing is installed on the firewall any more.

**This weakens the security posture and the change is deliberate.** See
SECURITY.md. The REST build's read-only claim was structural — no write verb
existed in the client and a grep proved it — and the REST package's own Read
Only setting enforced it at the firewall. This build sends PHP to `exec_php`,
which will run whatever it is given, so the guarantee now rests on an audited
allowlist in `PHPSnippets.swift` plus the checks in
`vaktpost-tools/tests/readonly.sh`. A maintainer who edits both files has
defeated it; the REST build had no such door.

The credential changes with it: a scoped, revocable API key becomes a
webConfigurator password with the administrator-equivalent "System - HA node
sync" privilege, sent on every request because XML-RPC has no session.

### Gained

- Dynamic DNS entries, with the last address pushed and an alert when it no
  longer matches the interface being watched.
- System notices — the webConfigurator's bell icon.
- Per-filesystem usage instead of one aggregate `disk_usage`.
- mbuf figures, which the REST endpoint returned as null on this hardware.

### Lost

- Installed package inventory, configuration revision history, and pf table
  browsing. Each needs a shell or a writing PHP function.

### Corrected against a live firewall

- LDAP accounts authenticate over XML-RPC. The docs said they did not, which
  was true of the REST API and carried over by assumption. XML-RPC goes through
  the webConfigurator's normal auth path, so any account the web UI accepts
  works here. Noted in SECURITY.md as a reason for more caution rather than
  less.
- `return_gateways_status(true)` returns an associative array keyed by gateway
  name, which JSON-encodes as an object rather than a list. Row extraction fell
  through to folding the top-level object and produced exactly one row, named
  "data", with no status — a firewall with two healthy gateways would have
  displayed one broken one. Now handled explicitly, with the key folded in as
  the row's name.

### Fixed by running the snippets against a live firewall

All 25 returned data on first contact, but four were returning the wrong data
quietly, which is the failure mode this transport is most prone to:

- **CPU showed 995026240%.** `cpu_usage()` returns "<total ticks>|<idle ticks>"
  since boot, not a percentage. The ticks now come across raw and
  `DashboardStore` differences consecutive samples, the same way interface
  throughput works — so CPU needs two refreshes before it shows anything, and
  shows nothing rather than zero until then.
- **Every log came back empty.** The tail read introduced in the previous
  change passed a negative offset larger than the file, which makes the seek
  fail and `file_get_contents` return false. Every log on a normal firewall is
  smaller than the 256 KB window, so all five broke at once. The offset is now
  clamped to the file size.
- **Absent sensors read as zero.** `get_temp()` and `get_mbuf()` return empty
  strings on hardware without them, and `floatval("")` is 0.0 — a firewall
  sitting at exactly zero degrees with zero mbufs, both of which look like
  measurements. Now null, so the rows hide.
- **`platform` is an object**, not a string, so the hardware row was blank.
- **The firmware update flag** lives in a nested object as a comparison
  operator, not a boolean. Flattened in the snippet; comparing the version
  strings directly would have failed on "26.07-RELEASE" against "26.07".

Also noted, not fixed because it cannot be: pfSense reports every ZFS dataset's
usage against the pool's free space, so on a 400 GB pool they all read 0%. The
figure is honest and useless. Only tmpfs mounts show real pressure.

### Fixed: a comment about escapes, containing an escape

The previous change replaced the log snippet's newline escape with `PHP_EOL`
and explained why in a comment — a comment that itself contained the escape.
Swift turned it into a real newline, which ended the PHP line comment early and
left `" deliberately: a backslash escape in a` as bare code. Parse error, HTTP
500, and the snippet was fine one edit earlier.

The test added alongside it did not catch this, because it looked for
backslashes in the runtime string, where the escape has already been consumed.
The check now runs in `readonly.sh` against the source file, where the evidence
still exists, and permits only `\(` interpolation. Verified by reintroducing
the escape and watching it fail. The Swift test now asserts the consequence
instead: no line of any snippet is stranded code.

`check-snippets.sh` also distinguishes HTTP 500 as a parse failure rather than
a runtime one — a snippet that compiles and then fails returns an XML-RPC
fault, so 500 specifically means the PHP was never valid.

### Fixed: the checker was reading something the app never sends

`check-snippets.sh` reads `PHPSnippets.swift` as text, and that is not the same
as the string Swift builds from it. `\\n` on disk is a two-character escape
that becomes one backslash and an `n` at runtime — so the checker sent PHP that
split its log on a literal backslash-n, matched nothing, and reported one row
from a healthy 850-byte file. The app, which sends the runtime string, was
correct throughout.

Three changes, because fixing only the symptom would leave the trap:

- The snippet uses `PHP_EOL` instead of `"\n"`, so there is no escape and the
  file and the runtime string are identical text.
- The checker applies Swift's unescaping to what it extracts, in the same order
  Swift does — interpolation first, then escapes — so any future escape is
  handled rather than silently altered.
- A test asserts no snippet contains a backslash at all. Anything reading the
  source instead of running it is then inspecting exactly what the firewall
  receives, by construction rather than by care.

### Fixed on first device build

- `XMLRPCClient` assigned `trust.profile` directly. `TrustEvaluator` had since
  been refactored to hold its state behind a lock with a `configure(with:)`
  setter, so the property is read-only. Now uses the setter.
- The keychain service string changed with the transport, which left
  `deleteLegacy()` looking under the new service — finding nothing, reporting
  success, and leaving the old REST API key in the keychain indefinitely. The
  legacy accessors now name the old service explicitly.
- The keychain setter kept its old name. It had been refactored to return a
  `Result`, so a rename matching the old signature silently missed the
  declaration and renamed only the call sites.
- The Disk meter had no source. XML-RPC reports per-filesystem rows and no
  aggregate, so `diskUsage` falls back to the fullest mount, which is a more
  useful figure than an average anyway.

### Fixed on the first run against real hardware

- **Every meter rendered twice.** `SingleMetricSparkline` drew nothing when it
  had fewer than two points, but still rendered its frame and footer — so under
  the live "Memory 8%" sat an empty box captioned "Memory 0%". Two readings,
  one invented. On first launch every metric is in that state, so the whole
  Resources card was doubled. It now renders nothing until there is a line to
  draw.
- **VPN throughput printed "↓ -)/s".** A closing parenthesis that belonged to
  `map` was written outside the interpolation, so it printed literally — and
  the appended "/s" was a second unit on a value that already carried one.
- **Ninety-seven clients all called "?".** `system_get_arp_table` writes a
  literal "?" when the reverse lookup fails, which on a LAN with no internal
  DNS is nearly every entry. "?" is no longer treated as a hostname.
- The About panel still described the REST transport and an API key.

### Fixed: snippets crashing on single-entry config sections

pfSense's config parser returns a section holding exactly one entry as that
entry, not as a list of one. `foreach` then walks the entry's *fields*, which
are strings, and indexing a string throws `Cannot access offset of type string
on string`. Every loop over `$config` had the hazard; all eight are now guarded.

The failure was visible because pfSense records an uncaught PHP error as a
system notice — so the app read its own stack trace back out of the firewall
and displayed it as an alert. Two consequences worth handling:

- Long notices collapse to their first line with a "Show full notice" control.
  A backtrace shown whole filled the screen and buried the five alerts under
  it.
- A notice raised by this app is labelled as such. Its own bug arriving as an
  apparent firewall fault is a bad way to be wrong.
- Notice text is HTML-unescaped; pfSense stores it escaped, so traces arrived
  full of `&gt;` and `&#039;`.

Note that these notices persist on the firewall. Clear them from the bell icon
in the webConfigurator once the snippets are fixed.

### A suite that catches members before the compiler does

Three build failures in one afternoon had the same cause: a patch applied by
matching text landed in the wrong struct, or matched nothing and silently did
nothing, and a view kept calling a property that was never written.
`vaktpost-tools/tests/members.sh` resolves every member against the declared
type of its binding and finds these in under a second, where the compiler needs
a project regeneration and reports one file at a time.

It now covers four classes, each of which cost a build today: a member its type
does not declare, an enum case no switch handles, a view using `store` or
`theme` without a binding for it, and a `"""` literal opened and closed on one
line. None is subtle — Swift refuses all four — but the compiler reports them
one file at a time after a project regeneration, and this reports all of them
at once in under a second.

It also checks enum exhaustiveness. Swift enforces that itself, so this is not
about correctness but about when you find out: adding `.haproxy` to `Section`
and forgetting the switch is a two-minute build away from the error, and a
second away here. That happened twice.

`bindDescription` and `routingDescription` had landed in `HAProxyServer`
instead of `HAProxyFrontend` — both structs end with the same `health` line, so
a replace-first matched the wrong one. Fixed, and now caught automatically.

### Alerts can be acknowledged one at a time

Silencing a whole category was the only control, and it is the wrong shape for
what people actually want — "I have seen this one" rather than "never tell me
about capacity again".

Long press an alert to acknowledge it. The identity used is the category, the
severity and the title with digits removed, so "Chipset at 81 °C" and "Chipset
at 83 °C" are the same acknowledgement — otherwise it would need doing again on
every degree. Severity is part of it on purpose: something you decided to live
with as a warning is not something you decided to live with when it turns
critical.

Acknowledgements persist, are listed by name on the Alerts screen with a way to
undo them, and are dropped when the condition clears — otherwise acknowledging
a gateway that was down would silence that gateway going down again next month.

### The settings toggles read backwards

Under a heading saying "silence individual kinds", every switch meant *shown*
and every switch was on. So the screen looked like everything was already
silenced, and turning one off silenced nothing. On now means silenced.

That probably explains the missing thermal alert: the context menu's "silence
all capacity" is one tap away from the alert, and the temperature alert moved
into that category earlier the same day.

### The temperature threshold was guessing

`get_temp()` returns a number without saying which sensor produced it, and the
number alone is not interpretable — 81 °C is unremarkable for a chipset and
worth investigating on a CPU die. The snippet now probes the sysctls first,
because that is what identifies the sensor, and only falls back to `get_temp()`.
An unidentified sensor gets 90/100 rather than 80/95: an alert nobody can act
on is how a list stops being read.

### Seven smaller things

- The "Refreshing…" pill is a plain spinner. It announced something nobody
  asked about, every thirty seconds, over the screen behind it.
- WAN and LAN are pinned to the Overview by default, seeded once so removing
  one sticks. A default that reasserts itself is not a default.
- VPN is split by technology, and only shows tabs for what the firewall runs.
- System Certificates offers CAs / Certificates / Expiring. "All" mixed
  authorities that never expire with the certificates you came to check.
- The System screen can check pfSense's own version on demand.
- The username field no longer suggests `admin` — the setup notes ask for a
  dedicated account, and the field should not argue with them.
- Acknowledged and silenced alerts are counted separately, so the same alert is
  not reported as hidden twice for two different reasons.

### Sensors is an ordinary kind of alert

It had its own heading and a slider, which made a temperature threshold look
like a different class of setting from the switches under it. It is a row like
the rest now, with a thermometer beside it.

That needed a real category: temperature alerts rode under Capacity, so
somebody who wanted to stop hearing about a warm chipset had to silence disk
and memory warnings with it.

The threshold has not gone — it is a long press on the row, in fixed steps
rather than a slider. The useful answers are "follow the sensor" and a handful
of round numbers, and a slider asked somebody to aim for one of them.

"Kinds to show" is "Kinds of alerts".

### The app stopped calling the thing that crashes

`rrd_xport` returned 502 again after being guarded on the file declaring its
data sources. Something in that call takes the process down on this firewall,
and finding out which part is not work the app should do on a live box every
thirty seconds.

The refresh takes `rrd_fetch` — which returns unknowns here, but does not
crash. An empty chart is a poor result; an empty chart plus a web server that
stops answering is a much worse one. A monitoring app should be the last thing
to disturb what it watches, and for two builds this one was the worst thing on
the network.

### It took minutes to notice the network was gone

Turning off Wi-Fi left the tabs up and the old readings on screen. The state
was correct; it just arrived far too late to be any use.

Each request waited 30 seconds and retried once, and a refresh makes five in
sequence — so the app could sit on stale data for minutes before concluding
anything. Three things now:

- The first transport failure sets the error immediately and ends the cycle.
  There is nothing to learn from four more timeouts: if the firewall cannot be
  reached, it cannot be reached.
- No route is distinct from a timeout. `notConnectedToInternet` and its
  siblings are not retried — the system already knows there is no path, and a
  second attempt waits the full timeout to be told the same thing.
- The request timeout is 15 seconds. This is a firewall on the local network:
  it answers in milliseconds or it is not reachable.

The end-of-cycle assignment no longer clears an error already reported, which
it would have done on the next pass.

### The disconnected screen never appeared

Two faults, both mine, and together they meant the state I had just built could
not be reached.

`isUnreachable` also required `system == nil`. The store keeps the last good
data, so an app that had ever connected never satisfied that — it sat on its
tabs behind a small banner, showing numbers from an hour ago. A monitor
quietly displaying stale readings is the failure this whole app exists to
avoid, and I built one.

And `.transport` — the error a phone with no network produces on every request
— was in the default branch, recorded against each section and nowhere else. So
thirty section errors, no connection error, and the tabs stayed up. That is
precisely the case the screen was for.

`connectionError` was already the careful signal: it is set only when every
section failed and the failure was fatal, so a single unlucky request does not
trip it. Trusting it was enough; the extra condition only broke it.

### The tabs go away when the firewall does not answer

Five tabs of empty cards is a worse answer than one sentence. Each screen
explained its own emptiness separately and none said the thing they had in
common, so somebody would pull to refresh on five screens to learn the same
fact once.

In its place: the firewall's name, its own error text rather than a paraphrase
— a refused certificate, a wrong password and an unreachable address need
different things doing about them — a Try again button, and what to check in
the order that resolves it quickest. Pinning is mentioned only when pinning is
on.

The toolbar stays, so another firewall can be chosen or this one's address
corrected without getting past the error first.

It takes an error *and* nothing loaded. One timeout on a phone changing
networks should not tear the tabs away from somebody reading a log.

### Firewall rules search what they show

The rows show addresses and ports, not alias names, so searching only the raw
fields meant typing `443` found nothing while the rule showing exactly that sat
on screen. Search resolves aliases now, in both rules and NAT.

The search field moved into the content: `.searchable` puts its field in the
navigation bar, which animates itself in and out on focus, so the field jumped
up the screen the moment it was tapped.

"All" is the first chip rather than the last — the way back to everything was
past thirteen interfaces.

### Diagnostics lives in Settings

A stethoscope on every screen was one icon too many, and it watched for a
condition nobody needs watched continuously — diagnostics is where you go when
something already looks wrong, not something to keep an eye on.

It is a row in Settings now, saying either "Everything is answering" or how
many sections are failing, and turning amber when they are. The toolbar keeps
the alerts bell and the gear.

### Settings is a toolbar button

Both were rows in the More list, several taps from anywhere. They are now a
gear and a stethoscope in the top right of every tab, beside the alerts bell,
and the stethoscope fills and turns amber when a section is failing — the count
was previously only visible by opening the list they were buried in.

The toolbar itself was written out five times, once per tab: five places to
edit and five chances to leave one behind, which had already happened. It is
one modifier now.

### The recording did stop, and the archives prove it

The probe read the file's archives: 60s covering 20 hours, 300s covering 60,
3600s covering 77 days, and a daily one covering six years. Every window
shorter than a day returns nothing. The week window returns 320 values whose
newest is 26 hours old and oldest 167 — data that ends exactly where
`rrd_last` says the last write was.

So the traffic recording stopped about 26 hours ago, and the fine archives have
been filling with unknowns since. My first reading was right; I abandoned it
twice on pfSense pages that carried the same "Mon Sep 07 19:49" caption — the
time of the render, not the data.

The app opens on the shortest span that has anything in it, rather than on an
empty chart. An empty chart where a longer span has data looks like a broken
feature rather than a firewall that stopped recording. It says when it widened,
because a picker that moves by itself looks like a mis-tap, and an explicit tap
is answered with exactly that span and the sentence explaining why it is empty.

### The probe asks where the data is, not just whether

pfSense draws an 8-hour graph from the same file the app finds empty at 8
hours, so recent data exists and "the recording stopped" was wrong again.

The probe now lists the file's archives — each one's consolidation function,
resolution and how far back it reaches — and then asks for the same window at
four resolutions, reporting for each how many values were numeric *and how old
the newest and oldest of them are*.

A count says whether a window found something. The ages say where the data
lives in time, which is the question every wrong answer so far has turned on.

The twelve older variants went: they asked the same thing without the timing,
and twelve requests where six will do is twelve chances to disturb a firewall.

### The history chart says what it is showing

A line with no numbers on it says "there was traffic" and nothing else. It now
carries the peak rate above it, a legend naming which colour is in and which is
out, and the ends of the span along the bottom — formatted for the span, so a
day shows hours and a year shows months.

An empty span says why. The 8-hour and day windows come back empty on this
firewall while the week is full, because the recording stopped a day ago:
whichever span did find data knows when it ended, and the empty one borrows
that sentence rather than leaving somebody to work it out from the picker.

### The clients list has a search field

It had a `query` and a filter that used it, and nothing anywhere to type into
— the field had been lost in an edit and the filtering code sat there unused.

It searches the names the firewall knows the device by, not only the one that
won the title: a device shown as its DNS name is findable by the description on
its static mapping. The interface too, so "vlan_100" narrows to one segment.

Below the header, like Logs, Network and Firewall — `.searchable` puts its
field above the title and jumps on focus.

### The client list marks this phone

Picking your own device out of two hundred rows meant checking a MAC in
Settings and scanning for it.

Matched on IP, not MAC. iOS has refused to give an app the Wi-Fi MAC since
iOS 7 — every app reads `02:00:00:00:00:00` — and Private Wi-Fi Address means
the address the firewall sees is generated per network anyway. The IP is what
the system will tell us, and it is right for as long as the lease lasts, which
is the same window in which the client list is worth looking at.

### ClientsView's body had been pasted over two other structs

`ClientRow` and `ClientDetailView` each carried a copy of the master-detail
container, and their real content sat below under the name `listColumn`. An
edit that replaced every `var body: some View {` in the file rather than the
first, some rounds ago.

Both restored. It compiled and ran the whole time, which is why nobody noticed.

### An eleventh rule: helpers in the wrong type

Four helpers were inserted into `RRDChart` while `InterfaceDetailView` used
them — the edit anchored on `peak`, a property both types declare, so it landed
in whichever came first. The compiler reports "cannot find X in scope" a minute
later and one file at a time.

The members suite now names both sides: which type declares the helper and
which type wants it. Only `private` members, and only names declared once in a
file, since an internal helper may legitimately be shared.

Its first run reported seven uses of `points` that were all locals inside
functions. Locals and parameters are excluded now — a rule that cries wolf gets
switched off, and this one nearly earned it before being checked.

### Choose the span: 8 hours to a year

pfSense keeps years of these — its own page offers up to four — and the app
asked for one fixed window. Which span answers the question changes: an
evening's shape, a working week, a month's growth.

The interface screen has a picker now. Each span is fetched once and kept, so
moving between them is instant after the first look, and switching firewalls
clears the lot — another box's history under this one's interface names would
be nonsense.

The snippet is built from a closed enum, the same way the log snippets are: the
span is an `Int` this file chose, rendered as digits. The read-only check
flagged the interpolation, correctly, and its exemption list now names
`window.seconds` and `window.rawValue` with the reason. I verified the rule
still catches an unapproved interpolation afterwards — the first attempt at
that test edited nothing and passed, which proved only that a probe with a bad
anchor proves nothing.

### A week reads; a day does not

The probe found it: every 24-hour window returns nothing but unknowns, and
`AVERAGE -s -604800` returns 320 numeric values starting `inpass=814758.67`.
With `rrd_last` at 25.6 hours, the picture is finally consistent — the traffic
files stopped being written about a day ago, so a day-long window lands
entirely inside the gap while a week reaches back past it.

So the app fetches a week. That is the better default regardless: when the
recording resumes it shows the recent data *and* the gap behind it, which is
what anybody wants to see after an outage.

The card is "Recent history" rather than "Last 24 hours", and says how old the
newest sample is when it is more than two hours back. A chart drawn from
day-old data without saying so is quietly misleading, which is a worse failure
than the empty one it replaces.

My first reading — that the recording had stopped — was right. I abandoned it
on a screenshot of a cached page and spent four rounds on the wrong thing.

### rrd_xport is fatal on this firewall — established

Six isolated steps: the functions exist, the file is readable, `rrd_last`,
`rrd_info` and `rrd_fetch` all answer, and `rrd_xport` returns HTTP 502. That
is a finding rather than a guess, and it took building the tool properly to get
it.

The probe stops calling xport now and searches the safe space instead — six
`rrd_fetch` shapes, each its own request, printing how many values came back
and how many were numeric. `--dump` is passed so the numbers appear: "2 keys:
values, numeric" is the shape of an answer, not the answer.

Two quoting faults found by exercising it against a stand-in rather than a
firewall: the argument list arrived as `["'AVERAGE, -r, 60'"]`, one string
where three arguments belong. The variations are plain space-separated lists
split in PHP now, which cannot be got wrong by three levels of shell quoting.

### The probe was running the whole suite

Its first step calls nothing but `function_exists`, and it reported HTTP 502.
That cannot happen, and it did — because the script set `PT_PROBE` in the
environment, while `check-snippets.sh` sets that variable itself from
`--script`. The value was overwritten with an empty string, so every step
quietly ran the entire snippet suite instead: thirty snippets including the
`rrd_traffic` one that was crashing the firewall. The 502 was real and came
from there.

So a tool built to isolate one call was firing all of them, at a firewall
already being hurt by one of them. It pipes through `--script -` now, which is
the supported interface, and I exercised the whole flow against a stand-in
before it went near a real box.

The failure message was the other half of the problem: it grepped the entire
output for "502" and announced a crash. It prints what actually came back now
and only stops on a result line that says so — a confident message about
something the tool had not established is worse than no message.

### bin/rrd-probe.sh

Six steps, each its own request: which functions exist, whether the file is
readable, `rrd_last`, `rrd_info`, `rrd_fetch`, then `rrd_xport` with a single
data source over one hour.

A crash takes the whole response with it, so asking several things in one call
learns only that something in it was fatal. Separate requests mean the first
step that reports 502 is the call that cannot be used, and everything above it
is known good.

This is the tool for finding that edge deliberately, rather than by pointing
the app at a firewall and watching what happens — which is what the last two
rounds amounted to.

### The xport attempt returned HTTP 502

Not an error — the request died. A `DEF:` naming a data source a file does not
have makes the rrd extension abort the process, and the loop asked every
`*-traffic.rrd` for `inpass` and `outpass`. Not all of them carry those.

Each file is now asked what it holds, through `rrd_info`, before anything is
built against it; a file that does not answer falls back to `rrd_fetch` rather
than being risked. The trace script's own xport probe got the same guard — a
trace that crashes the thing it is tracing is worse than no trace.

Worth stating plainly: this crashed the firewall's web server on every refresh
that reached it. Guarding the call was not an afterthought I skipped, it was
one I did not think to make, on a call I had not used before.

### rrd_fetch was the wrong call

Status → Monitoring set to Traffic / WAN_1 draws a full current day at
five-minute resolution from the same file that four different `rrd_fetch`
windows returned nothing but NaN from. The data is there, it is readable, and
the function was wrong — which is where three rounds of window-tuning should
have led much sooner.

`rrd_xport` is what rrdtool provides for getting values out rather than a
picture. The consolidation function, the window and the step are stated in the
DEF, so nothing is left to a default that turns out to mean something else, and
it is the call the firewall's own graphing takes one layer down. `--end -60`
rather than `now`, because the current bucket has not closed.

`rrd_fetch` stays as a fallback for an extension without xport, and the trace
script now runs both and says which one reads the file.

### Superseded: four windows

Two guesses have now failed — an explicit day, then five-minute resolution —
each producing a day of NaN from a file the firewall graphs. A third guess is
not worth making, so the snippet asks for each plausible shape in turn and
keeps whichever carries data: 5-minute, 1-minute, rrdtool's default, then a
week.

The week is the useful one. If the traffic archives really did stop a day ago,
a week-long window still finds the data before the gap — which separates
"nothing is recorded" from "nothing recent is recorded", and those need
different answers.

Diagnostics names the window that answered, so a week-long fallback succeeding
is not mistaken for the day working.

### The firewalls screen, simplified

A row per firewall and nothing else. It had a section header repeating the
title, a status pill, a fingerprint prefix, a TLS note, an edit button and an
add button in its own card — six things competing on a screen that exists to
answer which firewall is in use and whether anything is wrong with it.

A row says the name, the address, and a warning only when there is one: a
pinned certificate is the expected state and says nothing by being mentioned,
while its absence does. The active one is a filled dot rather than a pill
labelled "active" beside a name that is already obviously selected.

### Not stopped — the wrong archive

I said the recording had stopped, on the strength of `rrd_last` reading 25
hours old. The firewall's own Status → Monitoring then drew a full current day
from the same files. The data is there; the conclusion was wrong, and it sent
somebody looking for a setting that was not the problem.

That page draws its day at "Resolution: 5 Minutes". A fetch with no resolution
asks rrdtool for the finest archive it has, which on these files holds nothing
for the window — a day of NaN from a file that is being written every minute.

The snippet asks for 300-second resolution now, the same as the firewall's own
page, and falls back to the default only if that comes up empty. Which one
answered is carried back, so it cannot be guessed at again.

The empty-chart message and the trace script's verdict both asserted the
recording had stopped. They name both possibilities now and say which page
settles it: an old timestamp is a lead, not a verdict.

### The RRD files stopped being written 25 hours ago

The trace settled it: `last written 19:49:24 (90541s ago)`, every value in the
24-hour window NaN, and the file header showing `unknown_sec = 24`. Nothing has
been recorded since. That is a firewall-side condition — pfSense writes these
every minute while monitoring is on — and no fetch argument reaches around it.

So the app was right all along and its message was the only thing wrong. The
snippet now carries each file's last-write time, and both the diagnostics panel
and the empty chart say how long it has been rather than counting series
nobody can act on.

Two faults in the trace script itself, both mine:

- It described `/var/db/rrd/ipsec-traffic.rrd` — the first file alphabetically,
  and quite possibly an interface carrying no traffic at all. It looks at the
  WAN file now, and reports every file's age so one dead interface is not read
  as a dead firewall.
- It blamed a step mismatch. The age check ran *after* the NaN check, and I put
  it there deliberately in the last round while fixing something else. A file
  unwritten for 25 hours explains all-NaN completely; the dull cause has to be
  ruled out before the interesting one is offered.

### A trace script for the RRD history

"207,504 values offered, 0 numeric" rules out the transport, the snippet's
shape and the Swift decoding, and leaves the values themselves — which cannot
be identified by reading code from here. Three rounds have gone on guessing
between the possibilities.

`bin/rrd-trace.sh` asks the firewall directly: the values' PHP types, the first
few as strings, the file's step and archives, and how long since it was last
written. Then it says what that means, because a type dump still leaves
somebody to interpret it.

The NaN check comes before the numeric one, deliberately: `is_numeric(NAN)` is
true in PHP, so a NaN reads as a number right up until `json_encode` refuses
it. That confusion is what put a whole day of unknowns behind a fetch that
looked like it worked.

It runs `check-snippets.sh --only rrd_trace` rather than owning a second copy
of the transport, so the password is prompted for once by the script that
already does that carefully.

### Editing a firewall stopped working

Edit was a `swipeActions`, which does nothing outside a `List` — converting
that screen away from one silently removed the only way to change a firewall's
address. It is a button on the card now, with an entry in the context menu
beside Remove.

Removing the List was right; not checking what the List had been providing was
not.

### The All chip is back, at the end

Taking it out left "no filter" as a state reachable only by tapping the
selected chip again, which nothing on screen suggested. At the far end of the
row it is out of the way of the interfaces without being invisible.

### Every RRD value came back unknown

Eight series per interface, none with a sample in them — so the fetch works and
the data structure parses, and every value inside is being rejected.

The window was asked for as `--start -86400 --end now`. rrdtool's own default
is the last day ending now, which is exactly what is wanted, so the arguments
are gone: `rrd_fetch($path, ["AVERAGE"])`. Whatever the extension made of that
explicit window, not passing one cannot be misread.

The response now also counts values offered against values kept. Nothing
recorded and everything rejected produce the same empty chart, and they need
different fixes.

### The firewalls sheet belonged to a different app

A `List` with `.plain` style keeps the system background — white in light
appearance — where every other screen is a ScrollView over `theme.bg`. It is
one now. The section header went with it: the navigation title already says
"Firewalls", and saying it twice on one screen reads as a mistake.

Removing a firewall moved from swipe to a context menu, since swipe-to-delete
is a List behaviour and the List is gone.

### RRD reads, and the chart was drawing the wrong eight lines

The diagnostics panel answered it: 144 series across 18 interfaces, so
`rrd_fetch` is present and the data arrives. A pfSense traffic file holds eight
data sources — pass and block, in and out, v4 and v6 — and the chart drew all
eight, which puts six near-flat lines under the two worth reading and gives the
app nowhere to say which is which.

It draws the pass series now, coloured by direction, and skips any series with
no samples. A chart with nothing left to draw says so instead of rendering
blank. The diagnostics panel counts samples as well as series, since "144
series" says the fetch worked and nothing about whether any of them carry data.

### Smaller things from a pass on the device

- Search moved below the page heading on Logs and Network. `.searchable` puts
  its field in the navigation bar, above the header these screens draw
  themselves, so the search came first and the title second.
- Floating is a chip beside the interfaces, which is what it is: a rule set
  belonging to no single one of them. "All" is gone — tapping the selected chip
  clears the filter, which is what All did with one chip fewer to read.
- The temperature threshold moved into the alerts card under "Sensors". It is a
  threshold for one kind of alert, and standing alone it looked like a
  different sort of setting.
- Network charts are the same height as the Overview's. A 44-point strip is a
  sparkline; these are the charts somebody opened that tab to read.
- Filter lines in the Overview's firewall card open their detail, like the same
  rows on the Logs tab.
- First-run setup offers to pin the certificate. The edit screen has offered it
  for a while and the first-run screen did not, which is backwards: a first
  connection is when pinning is worth most and when nobody thinks to look for
  it.
- Dragging a section needs two thirds of a neighbour's height rather than half.
  Half means a card swaps the instant it overlaps, so a wobble near a boundary
  flips it back and forth.

### The firewall menu manages firewalls

"Log out" was the only thing that menu offered besides switching, which framed
the app as something you sign in and out of. It is not — it holds a list of
firewalls, and what you want from that menu is to add one, fix an address or
remove one you no longer run. It opens the management page now, and the active
firewall carries a tick, which with three of them the menu previously gave no
clue about.

The bulk "log out" on the management page went too: firewalls are removed
individually by swipe, and removing one clears its credentials, so it did
nothing the swipe does not.

### The drag was jumpy because one height stood for all of them

Sections range from a status banner to a full system card, and the drag divided
the finger's travel by a single 80-point estimate. One number was too large for
half the sections and too small for the rest, so a card would jump two places
or refuse to move.

Each row reports its own height through a preference key now, and the drag
walks the real geometry: a card swaps once it is more than halfway over its
neighbour, where halfway depends on how tall that neighbour actually is. The
offset that keeps the card under the finger sums the real heights it has passed
rather than multiplying a count by an average.

### The RRD state is on the diagnostics screen

A chart that draws nothing cannot explain itself in the space it has. The
diagnostics screen now says which of the five states the last read reached —
not read, reading, failed, unsupported, or working — and in the working case
lists the file names that came back, because those are what the interface
screens match against.

The same panel settled the throughput mystery in one screenshot. It is a better
tool than another round of me reasoning about it.

### Sections move while you drag them

The drag computed a drop target and applied it only on release, so nothing
moved until you let go — and the offset that was meant to nudge the neighbours
returned zero unconditionally, so it never could have.

The list reorders now while the finger is down. Everything else animates into
place because the ForEach re-renders with the new order, which is what makes
the cards move in relation to each other. The dragged card's offset is the
finger's travel minus the distance its own slot has moved, or it runs away from
the cursor by a row each time the list shifts.

The lift, scale and shadow were on the header row rather than the card, so
dragging moved a heading and left its contents behind. They are on the card.

The row height is still an estimate — sections differ a lot, and measuring each
one needs a preference key per section. The comment says so rather than
implying it is measured.

### Tooltip bubbles ran off the edge

`.position` centres a bubble on the x it is given, so a sample at either end
put half of it outside the chart. The marker stays on the sample and the label
slides in far enough to stay readable.

### An empty RRD card said nothing at all

`RRDHistoryView` had no branch for "read, and empty" or "not read yet", so both
rendered as a blank card — which is how a screen can be least useful. Every
state says something now, and the working state lists the file names that came
back, because those are what the interface screens match against.

### The overview's arrangement was never saved

Dragging a section rearranged the screen and the next appearance put it back.
The order lived only in the view's `@State`, and the loader rebuilt it by
filtering `allCases` — which returns declaration order and discards whatever
was stored. Both halves had to agree that the stored array *is* the order.

All three paths that reorder now write it back to the profile, so it is kept
per firewall like the rest of that screen's settings.

### Chart readouts sat off the line

Three faults in the same few lines.

`.offset` on a ZStack child is measured from the *centre* of the stack, while
the paths are drawn from its top-left — so every marker and label was displaced
by half the chart in both directions. `.position` is the one that takes the
same coordinates the line does.

The index truncated instead of rounding, so a tap two thirds of the way between
two samples reported the one on its left. And the marker was drawn at the
tapped x with the sample's y, so it floated off the line by however far the
finger was from a sample. The tap now snaps to the nearest sample and both
coordinates come from it.

The clamp allowed `count`, one past the end: a tap on the right edge of either
chart indexed out of bounds. That one was a crash waiting for somebody to tap
the last pixel.

### "No recorded history" meant three different things

Never read, cannot be read, and read-but-nothing-matched all fell through to
the same sentence. They are separate now, and the last one lists the file names
the firewall actually returned — RRD files are named for pfSense's internal
handle, so if that differs from what the app expects the match is one string
away from working, and an empty chart alone would send us guessing again.

### NaN broke the whole RRD response

The history read failed with "the response wasn't in the expected XML-RPC
format", which is a sentence that fits a PHP fatal, an HTTP error page and a
truncated body equally well.

The likely cause: RRD writes NaN for gaps in its data, `is_numeric(NAN)` is
true in PHP, and `json_encode` fails *outright* on NaN — returning false for
the whole document rather than skipping that value. The wrapper then puts a
boolean where a JSON string belongs, and the app reports a malformed response.
One missing sample poisoned everything. `is_finite` is the check that actually
excludes it, and INF with it.

The other floats the snippets encode all come from `floatval` on a string,
which yields 0.0 rather than NaN, so this was the only exposure.

### A malformed response now says what came back

Whether or not NaN was the cause, "not in the expected format" was never going
to identify it. The error now carries the first 200 characters of what the
firewall actually said — pfSense prints its fatals into the response, so that
usually names the function and the file.

### Every log line opens, not just filter lines

A DHCP or OpenVPN line is a sentence with a syslog prefix, and the list shows
two lines of one that may run to twenty. Tapping any line now splits off the
timestamp, host and process, gives the message room to wrap, and names any IPv4
address in it — a lease going to 172.16.1.161 is more use when the screen also
says which device that is.

IPv4 only. An IPv6 address cannot be told from a MAC or a fragment of a
timestamp without more care than a convenience like this deserves, and a wrong
guess would put a name against the wrong thing.

### "What this app cannot read" is gone

It listed RRD history as unreachable on the same build that now attempts to
read it, which is the kind of stale certainty that makes a whole screen less
trustworthy. Each gap is now said where it comes up, by the screen that has it.

### Smaller things from a pass on the device

- The Network tab's interface cards carry the same chart the Overview does.
  Lifetime counters say how much has gone through an interface since boot and
  nothing about whether anything is going through it now.
- Rule and NAT rows keep FROM, TO and PORT to one line each. A rule whose
  source expands to twenty networks was four lines tall in a list of
  ninety-eight, and the list exists to be scanned.
- Their detail screens put one address per line instead of a wrapped run. A
  wrapped run breaks mid-address, so `198.51.100.0/22` can end one line and
  start the next.
- `WHY` is `DESC`.

### Observing an optional does not compile

Two of the six views held their tracker as an optional, and `@ObservedObject`
cannot wrap one. Both were defensive wrappers around store properties that are
never nil, so the optional bought nothing and cost the redraw — which is how
the staleness got in.

I made the same conversion by hand twice and got the same compile error twice,
so rule 10 now checks both directions: an observable held as a plain `let`, and
something observed that is optional or not observable at all. The fix for one
is the failure mode of the other.

### The chart never redrew, and five others had the same fault

The diagnostics screen settled it in one look: three points recorded for WAN_1,
a card saying "none yet", and VLAN_100 saying "1 so far" — three different
numbers for one tracker. The chart was not stale in the data; it was not
re-rendering at all.

`ThroughputChart` held `let store: DashboardStore`. SwiftUI decides whether to
re-render by comparing a view's stored properties, and a reference never
changes — so the body ran once, when the card was created, and kept whatever it
saw. A card created before the first sample said "none yet" for the rest of the
session. VLAN_100 was created a refresh later and froze at one.

Nothing about that is a compile error. It produces a screen that is quietly,
permanently wrong, which is the worst kind of bug this app has produced, and I
spent four rounds reasoning about PHP field names and tracker arithmetic that
were correct the whole time.

A tenth rule now flags a View holding an ObservableObject as a plain `let`. It
found five more on its first run: gateway latency and three VPN throughput
cards had the same fault and would have been just as wrong. The VPN one held
the tracker as an optional, which cannot be observed at all — the store's
tracker is never nil, so the optional bought nothing and cost the redraw.

The rule also needed tightening: matching `ThemeManager` inside
`ThemeManager.Selection` reported a nested enum as an observable, and a rule
that has to be argued with is a rule that gets ignored.

### Historical traffic, where the firewall will give it up

pfSense records months of per-interface traffic in `/var/db/rrd`, and this app
has only ever shown what it watched since launch. The interface screen now
reads a day of it and draws it under the live chart — separate rather than
merged, because one is five-minute averages over a day and the other is two
seconds, and on a shared axis the live one would be a vertical line.

The read is guarded. RRD is a binary format normally read by `rrdtool`, a shell
binary, and shelling out is what the snippet rules forbid; PHP can read it only
with the `rrd` extension loaded, which is not standard on pfSense. Where
`rrd_fetch` exists it is used, and where it does not the screen says exactly
that instead of showing an empty chart that looks like an interface with no
traffic.

Every interface at once, with no parameter, because a snippet is a constant —
interpolating an interface name would mean assembling PHP at runtime, which is
the one thing that would make the allowlist unreviewable. Downsampled to 120
points a series: a day at RRD's finest resolution is 1440 buckets per direction
per interface, which is a megabyte of JSON to draw a line 200 points wide.

### Rules and NAT read as four labelled lines

FROM, TO, PORT, WHY — in that order, so a column of rules can be read down
rather than across. The port has its own row because it belongs to neither side
and squeezing it beside one made both wrap. NAT cards took the same shape, with
SENDS for the target.

The kind marker went with the alias names: with the names resolved it was
labelling an address as "alias", which describes where the value came from
rather than what it is. The detail screens resolve too — the name above its
members was the same duplication the list had already dropped.

### One chip per interface, not one per combination

A floating rule names every interface it applies to, so the raw values produced
a chip reading "OPENVPN1, OPENVPN2 +11" — a filter for a set nobody thinks in.
The chips are now individual interfaces, and choosing one shows every rule that
applies to it, floating rules included.

### Sharing a log showed a blank page

The button handed `UIActivityViewController` an array of a hundred-odd separate
strings, so it tried to preview a hundred documents at once and rendered an
empty sheet with a placeholder icon. A log excerpt is one thing you are
sharing; it travels as one document now, through `ShareLink`.

### Back from a rule went to More, not the rule list

`MasterDetail` created a `NavigationStack` of its own, and Firewall is pushed
from More — so a stack nested inside a stack, and going back popped the outer
one. A screen that may be pushed cannot own the stack it is pushed into.

It drives the ambient stack now, which works whether the screen is a tab root
or pushed. Clients is wrapped by the shell again, as it was before.

### Rules and NAT show addresses again, not alias names

Adding the kind markers reintroduced the alias names in the rows — the thing
that had already been removed once. Both sides and both ports resolve, with the
kind still marked so an entry expanding to several addresses is not mistaken
for one.

### The dashboard chart reports its own state

The two-second detail chart draws and the thirty-second dashboard chart does
not, and reading the code has not explained why: the keys match, the counters
arrive — the Network tab renders them — and the arithmetic is covered by
passing tests.

So rather than reason about it further, Diagnostics now lists every series the
tracker holds, how many points each has, and which interfaces have a baseline
but no rate. One look at that screen says whether ingest is running at all,
which is the fact I have been guessing at.

### A ninth rule: views used but not defined

Removing the ARP pane with a non-greedy regex matched to the wrong closing
brace and took `InterfaceCard` and `ARPRow` with it. `ARPRow` was meant to go;
`InterfaceCard` was not, and the Network tab stopped compiling.

That is the third edit today to delete more than intended. The members suite
now flags a `*View`, `*Card` or `*Row` that is used but defined nowhere, which
is what all three looked like from the outside.

### Tapping a client went black and bounced back

`MasterDetail`'s compact path was a computed binding whose getter built a fresh
array on every evaluation, so SwiftUI saw the path change identity
mid-transition and unwound it. The path is held now and mirrored to the
selection in both directions.

Tidier code that does not work is worse than plainer code that does, and the
derived binding was chosen for tidiness.

### Filter log lines open

`filterlog` writes a documented CSV and the app was showing it raw — a wall of
commas where the rule, the direction and the ports are countable but not
readable. Tapping one now names them, resolves the addresses to the devices the
firewall knows, and finds the rule the tracker refers to. The raw line stays at
the bottom, because parsing is lenient and the tail varies.

Two offsets were wrong before the real lines were tried: the protocol appears
twice, a number then a name, and taking the number gave a column reading "6"
where "tcp" belonged. IPv6 carries class, flow label and hop limit where IPv4
carries tos, ecn, ttl, id, offset and flags, so reading v6 at the v4 offsets
reported the hop limit as the protocol. Both fixed and covered by tests using
lines from the firewall.

### Firewall rules say more in the list

Interface, protocol, both sides with their ports, and the description. Each
side is marked with what it is — host, network, alias, interface, any —
because four rules that look alike in a list can be doing very different
things, and pfSense does not say which is which anywhere visible. The tracker,
IP version and logging flag stay on the detail screen: they matter when you are
working on a rule, not when you are looking for one.

### Overview charts are taller, and keep four hours

60 samples was chosen when the chart was a sparkline. A pinned interface is
pinned to be looked at, so the tracker keeps 480 points — four hours at the
default refresh — and the Overview draws them at twice the height. pfSense
keeps months in RRD and this app cannot read it, so the history it keeps itself
is all there is.

### The ARP tab is gone from Network

Clients already joins ARP with leases and static mappings, names each device
and shows its filter log. A second, thinner view of the same table was a place
to look that answered less.

### An eighth rule: the snippet catalogue

Regenerating the batches cut from the first batch to a `// MARK:` comment, and
`rrdProbe` had been added between them — so it was deleted while still named in
`all`, which does not compile.

The members suite now checks both directions: a name in `all` that is not
declared, and a snippet declared but missing from `all`. The second matters
independently — `all` is what the publish check audits and what
`check-snippets.sh` exercises, so a snippet absent from it is unaudited.

Two of today's edits have now cut a wider range than intended. Deleting by
index between two markers is fast and does not notice what it passes over.

### The batch accumulator collided with a body's own variable

Clients and the ARP table came back empty on device, with no error anywhere.
The batch had succeeded.

The accumulator was called `$sections`, and `host_overrides` uses that name for
a local — starting with `$sections = [];`. Every section captured before it was
discarded, and its own `$sections[] = …` appends left the result structurally
valid and wrong. So the app decoded a well-formed response containing nothing,
and reported success.

That is the worst shape a bug can take here: an empty network and a broken
fetch look identical, which is the thing this app keeps having to distinguish.

The accumulator is `$vaktpost_batch` now, and a test asserts no other snippet
mentions that name — the accumulator shares scope with every body in its group,
so the collision is structural rather than bad luck. A second test asserts each
capture appears after its own body and before the next, since a capture in the
wrong place stores the previous section's result under this section's name and
decodes cleanly.

Clients and the ARP tab also say when a fetch failed rather than showing their
empty state. ARP already did; Clients did not, and "No clients seen" is a
reassuring sentence to show somebody whose firewall is not answering.

### Floating rules name every interface they apply to

`opt5,opt6,opt7,lan,opt10,opt11,opt12,opt13,opt2,opt3,opt4` was printed raw,
which is both unreadable and the one place the configured names matter most.
A list covering everything now reads "all interfaces"; a shorter one names the
first two and counts the rest.

### The drift test was comparing the wrong thing

Every batch "had drifted from" every one of its parts. Not drift: the test
compared `script`, which is the *wrapped* form — every snippet gets an
`ini_set`, a lock release and a `json_encode` tail, and a batch has one wrapper
rather than five, so comparing scripts compares the wrappers too and can never
match.

`PHPSnippet` now exposes its unwrapped `body`, and the test compares that.

Worth recording how this got shipped: I simulated the assertion before writing
it and the simulation passed, because it compared bodies while the test I then
wrote compared scripts. Checking a test by re-implementing it only works if the
re-implementation does the same thing, and mine quietly did the right thing
where the test did the wrong one.

### The widget is gone

It was the least-used surface and the most expensive: a second target, a shared
snapshot type, an App Group, and its own copy of the palettes and the Dynamic
Type modifier. It also carried a bug found an hour ago — it looked up
throughput by the wrong key and had been showing no rate at all.

Removing it takes the App Group with it, which removes the one thing that made
a first install fail: an App Group must be registered on the developer account
before Xcode will sign against it. The entitlements file is now deliberately
empty, and the layout check warns if anything reappears in it.

### GENERATE_INFOPLIST_FILE was off

Comparing the two projects once more, this time the target settings rather than
the catalogue: a project where icon switching works sets `INFOPLIST_FILE` and
leaves `GENERATE_INFOPLIST_FILE` alone. This one set it to NO.

That setting controls whether the build merges the partial plists other steps
produce — including the one the asset catalogue compiler writes with
`CFBundleIcons`, which is exactly what `setAlternateIconName` reads to find the
alternates. With it off, the alternates can be compiled into the bundle and
still be invisible to the runtime.

It is removed. The layout check now asserts the hand-written plist keeps the
keys only it carries, since the opposite failure — a generated plist replacing
it — is what that setting was there to prevent.

The earlier "Registered: AppIcon-amber, …" reading came from a build where I
had declared the alternates in the plist by hand. That block came out two
rounds later, and nothing has confirmed the keys were present since.

### Every icon set had the same filename

Comparing against a project where switching works, key by key: the build
settings match, the Info.plists are equivalent, the catalogue structure is the
same, the images are 1024, RGB, no alpha. One difference left — six
`appiconset` directories in one catalogue each containing a file called
`icon.png`, where the working project names each after its colour.

`INCLUDE_ALL_APPICON_ASSETS` copies these into the bundle, and six sources
sharing one name is the kind of thing that survives a build and fails at
runtime. Renamed, previews too.

Whether that is the cause I do not know. It is the only difference left between
a build that switches icons and one that does not, which is a better reason to
change it than any of the theories that came before.

The picker also reports whether `CFBundlePrimaryIcon` is declared. iOS refuses
to switch in an app with alternates and no primary to switch back to, and gives
the same unhelpful `EAGAIN` for it. The alternates have been confirmed present
twice; that half has never been looked at.

### Icon switching uses the async call

A working project on the same device does this and nothing else:

    try await UIApplication.shared.setAlternateIconName(icon.alternateName)

This app had the completion-handler variant wrapped in
`DispatchQueue.main.async`, an `applicationState` check, an eight-step retry
loop, a pending icon kept until the scene became active, and a `scenePhase`
observer to apply it. Every piece of that was built to work around `EAGAIN`,
and every piece was a guess at what iOS wanted. The async variant does not
produce that error.

All of it is gone. The build settings and the asset catalogue turned out to
match the working project exactly — the call was the only difference, and it
was the one thing I never compared.

It was not the widget, which was removed several rounds ago.

### Icons: the simulator was never going to work

`NSPOSIXErrorDomain 5` — `EIO`, an I/O error — from the simulator, where the
earlier device attempts gave `EAGAIN`. Two failures that look alike and are
not: the simulator has no Home Screen icon database to write to, so alternate
icons cannot work there at all.

Showing the domain and code is what made this visible. "The operation couldn't
be completed" had been the same sentence for both, and I had spent two rounds
treating a simulator limitation as a timing problem — adding delays, then
waiting for `.foregroundActive`, then a pending retry, none of which could ever
have helped there.

The picker now says so before the tap rather than after: the simulator cannot
change app icons, and the choice will apply on a device. Retrying is not
offered, because a suggestion that can never work is worse than none.

The device path keeps the pending retry, which is still the right answer for
`EAGAIN`.

### Icons: a refused change is remembered

`setAlternateIconName` kept returning `EAGAIN` on a device where the app was
plainly in front and all five alternates were registered. The documented reason
is that the app is not `.foregroundActive`, and waiting for that was not
enough.

So rather than keep guessing at delays: a refused icon is kept and applied when
the app next becomes active. Leaving Settings and coming back does it. That
turns a failure the person can do nothing about into one they can, and costs
nothing when the call works first time. The picker says what is pending.

Errors now include the domain and code. "The operation couldn't be completed"
is the same sentence for a dozen different problems, and knowing which one is
the whole difficulty.

### A diagnostics screen

Every section already recorded why it failed, but that error only appeared on
the card it belonged to — so an empty Gateways card meant finding the Gateways
card to learn why, and "is the app healthy" meant visiting nine screens.
Several of this app's own bugs went unnoticed for a session because the
evidence was scattered.

Under More: what is failing, what has stopped being retried and after how many
attempts, and the connection itself. Nothing is fetched; it is what the last
refresh already found out.

It also writes down what this app cannot read and why — blocked hosts, live
HAProxy status, UPnP maps, historical graphs. Each cost a round of guessing to
establish, and an empty screen looks identical to a broken one without the
explanation.

### The widget was showing no rate at all

It looked up throughput by `device` while the tracker stores by `seriesKey` —
the VLAN-on-a-lagg bug, fixed in the tracker weeks ago and missed in this copy.
The key never matched, so the rate was always absent.

It also follows whatever is pinned to the Overview now rather than always the
uplink, and says which interface it is showing. A bare rate does not say what
it is a rate of.

A test asserts the two keys stay in step.

### The ARP tab searches the name it shows

It displayed the resolved name — DNS override, then lease, then static mapping
— but searched only the announced hostname. Typing the name on the row in front
of you found nothing.

### iPad gets a list and a detail side by side

The app was an enlarged phone: a column of cards down the middle of a 13-inch
screen, and tapping one replaced the whole thing. Clients and Firewall suffer
most, because comparing two entries is most of what you do there.

Both now show the list on the left and the selection on the right at regular
width, and behave exactly as before on a phone.

Two decisions worth recording:

- **An HStack, not a `NavigationSplitView`.** A split view can only be a root,
  and these screens are not all roots — Firewall is pushed from More. Nesting
  one inside a navigation stack puts the detail in the wrong column or drops
  it. An HStack composes anywhere and gives the same thing.
- **Selection is an identifier, not the item.** A stored copy of a row goes
  stale on the next refresh: thirty seconds later the detail pane would be
  showing counters from before the last sample. The id is looked up again each
  time, so the detail follows the data — and the compact path is derived from
  the same selection, so a back swipe clears it and the two layouts cannot
  disagree about what is showing.

Every other screen caps its content at 720 points on iPad. Cards designed for a
phone's width become lines of text a foot wide with a status pill marooned at
the end, which is harder to read than the layout it replaced.

### A seventh rule: assignments to properties that do not exist

The batch decoders assigned `self.arpEntries` where the property is `arp` — a
name I invented rather than checked, in a file with sixty-odd stored properties
to confuse it against.

The members suite could not see it: its typed-binding rule needs a written type
annotation, and `self` has none. It now checks assignments to `self.x` against
the properties the enclosing type declares, which names the same line the
compiler does.

### Text scales with the person's setting

Every font in the app was `Font.system(size:)`, which does not scale — the same
points whether text is set to xSmall or to the largest accessibility size. On a
monitoring app you read on a phone, that meant somebody who needs larger text
got a dashboard they could not read.

All 246 call sites now use a `.scaledFont` modifier that multiplies by the
current Dynamic Type ratio, relative to `.body` throughout: the sizes were
chosen against each other, and scaling them by different curves would pull a
card apart at large sizes. Converted by rewrite rather than by hand — a missed
site leaves one unscaled label that nobody notices until somebody complains.

Three things the conversion needed beyond the fonts:

- The icon wells scale too. A 22pt well clips a symbol that has grown to 30pt.
  The decorative rails down the side of a card stay fixed: they are not text.
- Row summaries allow two lines instead of one. "Allow Cloudflare to HAP…" says
  less than two lines of it.
- The modifier lives in its own file compiled by both targets. The widget uses
  it as well, and it does not compile `Components.swift` — putting it there
  would have broken the extension build.

`Font.custom(_:size:relativeTo:)` scales natively but needs a font name, and
naming the system font by string is fragile across releases. `@ScaledMetric`
gives the ratio directly and keeps the system font.

A test fails the build if a fixed font size reappears, which is how all 246 got
there: one at a time, each looking reasonable on its own.

### A refresh is five calls instead of twenty-two

pfSense serialises XML-RPC, so every request queued behind the last and behind
whatever the webConfigurator was doing. The cost of a refresh was in the round
trips, not the work.

Three of those calls were the *same* telemetry snippet, run separately for
system status, the state table and filesystems. That was free to fix and should
have been noticed long ago.

The rest are grouped into four calls by screen: core (telemetry, firmware,
interfaces, gateways, services), clients (ARP, leases, static mappings, host
overrides, aliases), VPN, and system. The filter log stays on its own because it
takes a parameter.

Grouped rather than combined into one, because a PHP fatal cannot be caught: a
single call would mean one bad section blanking the whole dashboard. Four groups
bound that to the screens they serve, and errors are still recorded against
individual sections — "batch_core failed" would be an implementation detail
leaking onto a screen, and would leave four other cards blank with no
explanation.

The batches were generated from the existing snippet bodies rather than
retyped, so there is no transcription risk — but there are now two copies of
each body, and a test asserts each batch contains its parts verbatim. Without
it, fixing a field name in one and not the other would leave a screen quietly
reading the wrong key. The individual snippets stay because that is what
`check-snippets.sh` exercises when debugging one section against a live
firewall.

Row unwrapping is now shared between the batched and solo paths, so the `data`
envelope, bare lists and keyed-object folding behave identically either way.

### The read-only check failed about once in twelve runs

It forked two greps for every function name it found — well over a hundred
processes — and under load an occasional fork failed, which reads as "not on
the allowlist". It named a different innocent function each time, which is what
made it look like noise.

I dismissed it as flaky three times this session before looking. That is the
wrong instinct: an intermittent check is worse than one that always fails,
because it trains you to ignore the one thing standing between this app and a
snippet that writes to a firewall.

Now a single pass. Zero failures in thirty runs, and it still catches a planted
`system_reboot_now`.

### Interfaces report whether they have byte counters at all

The throughput chart has never charted anything, and said "collecting samples"
throughout — a message that cannot distinguish "this started a moment ago" from
"no sample will ever arrive". The likeliest cause is `get_interface_info()` not
returning the counters the app reads.

The snippet now reports explicitly whether they are present, and the chart says
which situation it is in rather than promising a sample that may never come.

### Icon switching waits for the app to be active

A fixed 0.6s retry was a guess at a delay, and it kept failing. `EAGAIN` from
`setAlternateIconName` means iOS declined at that moment, and the moment that
matters is the scene's state: it refuses unless the app is `.foregroundActive`,
which it is not during a navigation push, a sheet presentation, or while a
screen is still animating in.

So it now waits for the app to actually be active rather than guessing how long
that takes, and retries up to eight times a quarter-second apart. If it still
refuses, the message says how many attempts were made and what the build
registered — the difference between "try again" and "this build is wrong" is
not something to leave a person guessing at.

The registered names are shown on any failure now. Previously they appeared
only when icons were missing, which meant their absence was itself a clue and
nobody could read it.

### Two different icon failures, told apart

`setAlternateIconName` returns the same unhelpful "resource temporarily
unavailable" — POSIX `EAGAIN` — for a transient refusal and reports a generic
error when the icon simply is not in the build. Those need different responses
and the screen said neither.

It now reads `CFBundleIcons` from the running bundle first. If the requested
icon is not registered there, it says which ones are, because no amount of
tapping fixes a packaging problem. If it is registered, the call is deferred to
the next runloop turn — being inside a SwiftUI update is one of the states iOS
declines from — and retried once after a moment, which is usually enough for a
genuine EAGAIN.

The picker shows progress while a change is settling, and says how many
alternates the build registered when that number is short.

### The icons were packaged wrong

"The file doesn't exist" — `setAlternateIconName` could not find them, and the
previews were blank for the same reason. Loose files at the bundle root are the
old way of doing alternate icons and depend on the build system putting them in
exactly the right place, which it did not.

They are asset catalog icon sets now, with
`ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES` listing them. Xcode generates
the plist entries and places the images itself, which is what it has done since
Xcode 14. The hand-written `CFBundleIcons` block came out, since it would fight
the generated one. Previews are ordinary image sets, because an app icon set
cannot be loaded as a normal image.

### The app has an icon, and six of them

A watchtower, in coral, ocean, mint, amber, lavender and silver. Coral is the
primary one in the asset catalog — the app had no catalog at all until now —
and the other five are loose bundle files, which is what `setAlternateIconName`
resolves. Settings has a picker.

Worth noting the filenames matter: `Icon-ocean@2x.png` at the bundle root, not
the size-suffixed names an asset catalog uses. I generated the wrong ones first
and they would have failed silently at runtime.

The website header uses the icon too, switching to whichever of the six is
nearest the chosen accent.

### A firewall rule opens, rather than explaining itself in the list

Ninety-eight rules at five lines each is a list nobody scrolls. Rows are two
lines now — what the rule does, and its description — and everything else moved
to a detail screen: both sides with ports, the interface, IP version, whether
it logs, and the tracker, which is how you find the rule again in the
webConfigurator. Aliases show their name *and* contents there, where there is
room for both.

NAT the same.

### The label field is gone from first-run setup

One more thing to fill in before a connection could be tested, for a name that
matters only once there is a second firewall. Still editable when editing one;
the list falls back to the hostname when it is empty.

### Saving a firewall left you on the edit screen

It saved and reported the connection test inline, so nothing indicated the job
was done. Success dismisses now; failure stays open, because the error is the
reason to still be there.

### It offers to pin the certificate

pfSense ships a self-signed certificate, so the first connection is necessarily
made with untrusted TLS allowed — and that is the one moment the app knows the
certificate is the right one, because the person is looking at the firewall
they just typed in. It now offers to pin it there. Asked rather than done
silently: pinning breaks the connection when the certificate is renewed, and
that should not be a surprise.

### The temperature threshold is yours to set

80.5 °C on a chipset does not trigger the built-in 95 °C warning, which is the
right default and the wrong answer for somebody who knows their board and wants
to hear about it. Settings has a slider; the critical point follows ten degrees
above, so lowering the warning does not lose the difference between warm and
serious.

### UPnP removed

The screen could say whether the service was on and nothing else, because the
port maps live in a pf anchor that only `pfctl` can read. A page that exists to
tell you it cannot tell you anything is not worth a row in the menu. Removed
entirely — snippet, model, view and tests.

The finding stands and is worth keeping in mind: three separate things on this
firewall (blocked hosts, live HAProxy status, UPnP maps) are behind a shell, and
that is the real boundary of what this transport can see.

### Superseded: the UPnP screen

Two guesses were spent finding this out. A lease file that does not exist, then
an accessor function that does not either — the probe reported only
`upnp_running` and `upnp_action`, and no lease file at all.

miniupnpd keeps its port maps in a pf anchor. pfSense's own status page builds
its table by running `pfctl -a miniupnpd -sn` and parsing the output, and
shelling out is exactly what the snippet rules forbid, for the reason that
`exec` cannot be audited as read-only.

So the screen shows what is knowable — installed, enabled, running, which
interface — and says plainly where the mappings are instead of showing an empty
list. That distinction is the point: "no ports are open" and "this app cannot
see which ports are open" render identically, and the first is far more
comforting than it deserves to be. A running UPnP daemon is a standing offer to
open ports on request, so it is coloured as a warning even though the resulting
ports cannot be listed.

The call to `upnp_get_active_mappings` stays, so a package version that gains
one starts working with no other change.

### The old UPnP screen note

The first version read `/var/etc/miniupnpd.leases` directly, which came back
empty against a firewall whose webConfigurator was showing a live mapping. The
lease file is not where pfSense keeps them.

It now calls `upnp_get_active_mappings()` from the package's own include, which
is what the status page uses, and reports which functions and files it found
when that is not there — so a wrong guess is corrected in one round trip
instead of by trying paths one at a time. The model reads both plausible field
namings, since the accessor is undocumented and one guess has already been
wrong.

The expiry column is gone: the lease file had a timestamp and the accessor does
not, and showing "no expiry" for everything would be inventing a fact.

### The old UPnP screen note

Ports opened because a device asked, rather than because somebody wrote a rule
— the one place where what is open and what is in the rules can differ. Shows
the route, what the firewall knows the device as, and how long the lease has
left. Installed-but-off is said plainly rather than shown as an empty list.

### The publish gate caught a leak, and was missing more

The secrets check stopped a publish over an internal hostname in test fixtures
and doc comments — written from live data while debugging, which is exactly how
this happens.

Looking at what else was there found worse: the real WAN address in four test
fixtures, in the changelog, and on the public website's mockup. The check had
missed all of them for two reasons.

- It only matched addresses inside a URL. A bare address in a fixture is the
  same leak without the scheme.
- It scanned `Sources`, `Resources`, `public-web` and `README.md` — not
  `Tests`, not `CHANGELOG.md`. Fixtures are written from live data and the
  changelog quotes what was on screen when something broke; both are as public
  as the code.

Both widened, with the RFC 5737 documentation ranges allowed so examples stay
possible. Everything now uses `203.0.113.x` and `example.se`. Verified by
putting a real address back and watching the check fail.

### Port forwards have a source, and it was being dropped

A sweep against the live firewall showed `source` on every port forward row.
The model never read it, and a comment I had written asserted it did not
exist — I inferred that from the model rather than from the firewall.

It is parsed now and shown when it narrows something. A forward restricted to
one source is exactly the kind of rule worth seeing marked as restricted;
"From any" on all five would be a row that never varies, so it is hidden when
it says nothing.

### Acknowledging one gateway silenced another

The acknowledgement signature stripped every digit from a title, so
"WAN_DHCP is down" and "WAN2_DHCP is down" became the same condition — and
acknowledging one would have hidden the other. The same held for openvpn1 and
openvpn2.

Only whole numeric words are dropped now: a digit inside an identifier is part
of its name, a word that is only a number is a measurement. Checked against
every title the alert builder can emit, which turned up one more — "CARP VHID 1
backup" identifies a virtual IP by a bare number, so alerts can now carry an
explicit key for the cases where the title cannot distinguish them.

### A failing test crashed the whole run

`ServerMigrationTests` force-unwrapped a value that a genuine failure would
leave nil, so instead of a failed assertion the process died, taking every test
after it and producing a macOS crash report. It uses `XCTUnwrap` now.

Underneath it was a missed edit: two `ServerRegistry()` constructions were
nested deeper than the ones I replaced, so those tests built a registry against
the shared defaults while asserting against the isolated suite.

### Rules read as fields, not as one line

`198.51.100.0/24, 198.51.100.0/22, 203.0.113.0/24 +19 → wanip:80, 443` is a
wall: it wraps mid-address, and which side is the source depends on spotting an
arrow in the middle. Rules and NAT now use labelled rows — From, Src port, To,
Port — with a fixed label column so addresses line up down the card, which is
what makes them comparable between rules.

### Address and port were welded together

`FilterAddress` joined them into `host:port` and every consumer split on ":" to
get either back. That cannot work for IPv6: `fe80::1:443` has no unambiguous
split, and every rule with a v6 address was being rendered through exactly
that. They are separate fields now and resolved independently, so the joining
never happens.

### Rules and NAT show addresses, not alias names

`alias_host_pms001:alias_port_plex` now reads `172.16.1.43:32400`. The name is
dropped rather than shown alongside: a rule you are reading to find out what it
permits is answered by the addresses, and carrying both doubled the height of
every row for something you would look up elsewhere anyway.

Nested aliases resolve, duplicates are dropped, and there is a depth limit
because pfSense does not forbid a cycle. Long lists cap at three with a count —
`alias_url_cloudflare` holds twenty-two networks.

Aliases have their own screen under More, since looking one up is a different
task from reading a rule. Searching it matches nested members too, so looking
for a host finds every alias that ends up containing it.

### Previously: rules and NAT showed what their aliases contain

`alias_host_nas_hyperbackup → alias_port_hyper_backup` is precise and says
nothing about what the rule permits without opening two other pages. The alias
name stays — it is what you would search a rule for — and its members are shown
underneath.

Nested aliases are flattened, because that one holds four other aliases.
Duplicates are dropped, since two nested aliases often share a host and listing
it twice reads as a mistake in the rule. There is a depth limit: pfSense does
not forbid a cycle, and a stack overflow is a poor way to render a rule. Long
lists are capped with an honest count.

### The stored alert preferences read inverted

Flipping what the switches meant left anyone who had touched that screen with a
stored set interpreted the opposite way — every kind silenced when they had
silenced nothing. Changing the meaning of a stored value without changing where
it is stored is a migration, and I did not do one. The preference now lives
under a new key and the old one is removed on launch, so everybody starts from
the default: all kinds shown.

### Alert switches turn things on, not off

Under "silence individual kinds" a switch was on when the kind was silenced, so
a default of everything enabled looked like a screen full of off switches —
which reads as nothing working. The master switch had the same problem in
reverse: "Silence all alerts", off by default, is a double negative to parse
before you can tell whether alerts are on.

Now "Show alerts" and "Kinds to show", on by default, off to stop receiving
them. Same behaviour, stated the way people expect to read it.

### VPN peers moved behind a tap

Four instances each listing their connections made the tab a wall of addresses
and byte counts, and the question it is usually opened to answer — is
everything up, how many are on — was buried inside it. Each row now says "2
clients connected" or "1 of 1 connected", and the peers are on a detail screen.

WireGuard counts *connected* peers rather than configured ones: a tunnel with
three peers and none connected is a different situation from three all up, and
a bare count cannot tell them apart.

### One refresh indicator, not two

Every screen is inside a `refreshable` scroll view that draws its own spinner.
The floating one above the tab content was a second copy of the same
information, sitting over the title while scrolling.

### The website shows the app

Three more renderings — Clients, the live interface graph, and VPN — beside the
overview that was already there. Every colour in them is a theme token, so the
picker at the top of the page recolours them along with everything else.

### The exhaustiveness rule was checking almost nothing

`CertificatesView.Filter` lost its `all` case and kept a `case .all:` in the
switch, which is exactly what the members suite exists to catch. It passed.

Three faults stacked on top of each other, each hiding the next:

- The enum had to be written `: String, CaseIterable {` exactly, so one that
  also conformed to `Identifiable` was invisible. Now any CaseIterable enum
  matches, with its body found by brace matching rather than by stopping at the
  first `}` — which lands inside a computed property.
- Cases on one line with raw values parsed as nothing, because the pattern
  stripping `= "..."` ran on text where strings had already been blanked to
  spaces. Everything after `=` is dropped by position now.
- The inner loop reused the variable holding the enum's name, so the one
  message that did get produced said `expiring.certificates` instead of
  `Filter.certificates`.

Of the fourteen CaseIterable enums in the app, the rule previously saw two.

### The website, shorter

- The "What it can't do" section is gone. A list of absences is a strange thing
  to put in front of someone deciding whether to install something.
- The privilege callout is gone; the one sentence that mattered — it is
  administrator-equivalent, use a dedicated account — is in the step it
  qualifies, where somebody following the steps will actually read it.
- Feature cards are one line each. They had grown into paragraphs explaining
  the reasoning behind each feature, which belongs in the changelog.
- "What it reads" was a table of endpoint paths, which told a reader nothing
  about whether the app does what they need. It is now "What each screen shows",
  one short entry per screen.

The CSS for the removed sections went with them rather than being left to rot.

### The website describes the app as it is now

Setup no longer tells people to install a package that is not used. It is an
account with the HA node sync privilege, Max Processes raised, and a pinned
certificate — with a note explaining that the privilege is
administrator-equivalent and why a dedicated account is worth the minute it
takes.

Cut: "Watch the wall, touch nothing", the etymology of the name, and the
section arguing that the app never writes. The first was doing a job the
subtitle already does, the second was interesting to nobody deciding whether to
install it, and the third made a promise the current transport supports less
strongly than the old one did — better made once, plainly, next to the privilege
it qualifies.

Added: the live per-interface graph, HAProxy backend monitoring, ACME renewal
state, per-filesystem usage, dynamic DNS staleness, interfaces named the way the
administrator named them, and alert silencing. The "what it reads" table now
describes what each screen shows rather than listing endpoint paths, which is
what somebody deciding whether to install it actually wants to know.

Two honest additions to the limits: no historical graphs, and no live HAProxy
server status — with the reason, since "the socket that reports status also
accepts commands that disable servers" is a better answer than silence.

### A test that read the real firewall's settings

`testEmptyStateProducesNoServers` asserted the registry starts clean when
nothing is stored, and failed with a profile for a live firewall in it.

In a host-app test bundle `UserDefaults.standard` *is* the app's own store on
that simulator, and the tests wrote and read it directly — so the test passed on
a fresh simulator and failed on one where somebody had configured a firewall. It
was reading real settings. A test whose result depends on the state of the
machine running it is worse than no test, because a failure looks like the app
broke.

`ServerRegistry` now takes its store as an argument, defaulting to `.standard`,
and each test gets a fresh suite that is torn down after it. A sixth rule in the
members suite rejects any test touching `UserDefaults.standard`.

### A fifth rule for the members suite

`@ViewBuilder` written above a doc comment and again below it — the duplicate
hidden by the comment between them. Swift rejects it, and the suite now catches
it first. Attribute lines that also declare something end the run, so two
consecutive `@Published` properties are not mistaken for a duplicate; that
correction came from four false positives on the first attempt.

### Package and firmware updates now alert

The firmware alert already worked — `get_system_pkg_version()` gives the
comparison and the Overview raises it.

Packages did not, and the reason was the design: checking was manual, so an
alert could only appear after somebody pressed a button, which is not an alert.
The check now runs in the background at most every six hours, unawaited so the
rest of the dashboard does not wait behind it. Package releases happen weekly
at most, so this is about being told within a working day rather than within a
minute, at the cost of one repository round trip per six hours.

The time of the last check is persisted and shown, because "no updates" from a
week ago is a different claim from "no updates" from this morning.

Also: package descriptions arrive with `<br />` and hard line breaks —
pfBlockerNG's runs to six lines — which rendered as literal markup in a
one-line summary. Stripped.

### Packages can be checked against the repository

A Check button on the System screen compares installed versions against the
package repository, using `get_pkg_info()`.

That function runs pkg internally, which looks like it should be forbidden and
is not. The snippet rules stop *this app* from sending `exec`, `mwexec` or a
shell; they do not stop pfSense using one inside its own functions. The same
reasoning already covered `wg_get_status()`, which shells out to `wg show`.
What the rules protect is that every line of PHP this app sends is reviewable
and cannot write, and that holds here. Both cases are now named in SECURITY.md
rather than left as an inconsistency somebody would have to notice.

It is a button rather than part of the refresh because the call reaches the
repository over the network and takes seconds. On a thirty-second timer that
would have the firewall fetching a package index all day to answer a question
that changes weekly. The transport gained a per-call timeout for it — two
minutes, since timing out at thirty seconds would report a failure for
something that had not failed.

Results are merged rather than replacing the list, so a package the repository
has dropped does not vanish from what is installed.

### Seven from a session on the device

- **Packages are read again.** They were dropped in the conversion as
  unreachable; they are in `$config` after all. Live version comparison still
  is not — that needs `get_pkg_info()`, which shells out to pkg — so the screen
  shows what is installed and never claims an update is available rather than
  guessing none is.
- **ACME certificates are no longer listed twice.** The certificates snippet
  flags the ones ACME manages, and the general list leaves them to their own
  screen, where the renewal state that matters for them is also shown.
- **Renamed to System Certificates and ACME Certificates**, which is what each
  actually contains.
- **Onboarding still described the REST API.** An earlier edit matched text
  that had already changed and silently did nothing — the same failure as the
  three build breaks, this time in a string nobody compiles.
- **Overview interfaces open the live graph**, as on the Network tab.
- **Interfaces can be pinned to the Overview.** Fifteen is too many for a
  dashboard and one is too few; which three or four matter depends on what you
  run. Starred on the Network card, and the Overview falls back to the uplink
  when nothing is pinned. Note that `swipeActions` was written first and would
  have done nothing — it only works inside a List, and that screen is a
  LazyVStack.
- **The temperature alert was unactionable.** 82 °C is alarming for a CPU die
  and unremarkable for a chipset, and this firewall's only sensor is the PCH —
  so a healthy box raised a permanent warning, which is how an alert list stops
  being read. The snippet now reports which sysctl answered, the label follows
  it, and the thresholds do too: 95/105 for a chipset against 80/95 for a CPU.
- **Alerts can be silenced where you see them.** Long press an alert to quiet
  its kind or all of them. The switches in Settings were real but nobody goes
  to Settings looking for a way to stop something they are looking at.

### The test suite caught up with the app

29 failures, and all but one were tests asserting behaviour that had since been
deliberately changed — the cost of moving quickly on rules like naming priority
without revisiting what encoded the old ones.

- Alias-as-title tests: aliases no longer title clients, so these now assert
  the address is shown and the alias is carried for the detail sheet.
- Static-mapping description tests: the announced hostname and DNS overrides
  both outrank it now, which was a deliberate reversal.
- Throughput tests keyed by device: the tracker keys by interface, since VLANs
  on a lagg share a device.
- A WireGuard test with a fixed handshake timestamp: it went stale the moment
  the label started depending on recency — connected when written, idle a week
  later. It now builds a recent timestamp.
- A lease test expecting `.ok` for a static mapping, which the model colours
  `.info` deliberately.

The one that was a test-design problem rather than a stale expectation: a
line-shape heuristic meant to catch a comment broken by an escape flagged every
continuation of a multi-line ternary as "stranded code" — eight false positives
on valid PHP. Replaced with a brace-and-string balance check, which is the
property that actually broke.

### Tap an interface for a live graph

The Network tab's cards open a full screen that polls that interface every two
seconds and charts both directions against a shared scale — independently
scaled directions look like symmetric traffic when they are not. Current rate,
peak, lifetime counters and errors are alongside.

Two seconds is a floor, not a placeholder. Every poll is an `exec_php` that
pfSense serialises against the webConfigurator, so a tighter loop would make
the firewall's own web UI feel slow while the screen is open. The screen says
so, and the poll stops the moment it is dismissed — the loop is driven by the
view's `.task`, which SwiftUI cancels.

Supporting changes: a counters-only snippet, since the full `interfaces` read
returns fifteen rows of addresses and MAC addresses that do not change between
samples; and a second tracker with a longer history, so a minute spent watching
one interface does not flush the half-hour every other screen draws from.

### Certificates and ACME each have a screen

Sixteen certificates at the bottom of System was a list nobody could find
anything in. Certificates is now its own screen under More, sorted by expiry
rather than by name — the only question anybody opens it to answer is which one
runs out next — with All/Expiring/CAs and a badge for anything close.

ACME is separate from it, because the two answer different questions. The
certificate store says when something expires; ACME says whether anything is
going to renew it. A Let's Encrypt certificate with 40 days left is fine if
renewal is configured and a problem if it is not, and looking at the
certificate alone cannot tell you which. Each entry is joined to the store by
name and shows both, with the worse of the two conditions colouring the card.

Two things the screen flags that nothing else does: an entry with renewal
disabled, which will expire silently; and an account key pointing at Let's
Encrypt staging, whose certificates no browser trusts — a failure that looks
like a certificate error rather than the configuration mistake it is.

### HAProxy backends

A screen under More answering the question that was asked: is backend
monitoring set up? A backend with no health check keeps sending traffic to a
server after it dies, because HAProxy only knows a server is down if something
told it to look. That is configuration, readable from `$config`, and arguably
more useful than live status — live status says a server is down now, this says
you would never find out.

The summary line counts unchecked backends, the More row badges them, and each
card shows the check type, URI and interval or says "no health check".

Verified against a 35-backend configuration: `ha_backends` and `ha_pools` are
the right keys, and `stats_accessors` came back empty — no version of the
package on 26.07 exposes a stats accessor, so live status is not reachable
without the admin socket. That is now a finding rather than an assumption.

Two things the real data corrected. Frontend bind addresses live in a list
(`a_extaddr`), not the single `extaddr` field, which holds nothing once more
than one address is possible — every frontend read as having no bind. And a
blank check interval is HAProxy's own default rather than an absence, so it now
says "default interval" instead of trailing off after the check type.

**Live per-server status is deliberately absent.** It lives in HAProxy's admin
socket, and reading it means writing `show stat` to a socket that also accepts
`disable server backend/srv1`. Nothing reading this app's source could tell
those apart, so the read-only guarantee would stop being a property and become
a promise. Parsing `haproxy_stats.php` was the other option and is worse: it is
a webConfigurator page that changes shape with every package release.

The snippet probes for a package accessor with `function_exists` and reports
what it finds without calling it. If one exists, live status can be added
without guessing at a name — and the screen says so rather than pretending the
gap is not there.

### Dynamic DNS has its own screen, and three fixes

A firewall that hosts anything has twenty or more entries, and at the bottom of
System they were a wall of near-identical cards pushing everything else off the
page. Now under More, with search, an All/Stale/Disabled filter, and a summary
line so "is anything wrong" does not require scrolling twenty cards. The More
row carries a badge when something looks stale.

Three things were wrong in the data:

- **Every entry read DISABLED** while the webConfigurator showed them all
  green. pfSense writes this flag as an empty element, which is falsy in PHP —
  presence of the key is what means enabled, and a disabled entry has no key.
- **The hostname was "@" or "www"**, because `config.xml` keeps host and domain
  apart and the webConfigurator joins them. "@" on its own names nothing.
- **"Last pushed" showed `203.0.113.9|1788038229`.** The cache file holds
  an address and a timestamp separated by a pipe. Splitting it also gives the
  real update time, where the file's modification time only says when it was
  last touched.

The watched interface is labelled too — "WAN_1", not "wan".

### Firewall rules were never fetched

The Firewall tab loads its rules, NAT and aliases on appearing rather than on
the refresh timer, because 98 rules is a large payload for a screen most people
never open — but nothing called the loader, so the tab was permanently empty.
It now loads when the screen opens. The interface chips above the list were
already there; they had no rules to filter.

### Interfaces are called what the firewall calls them

A client on `lagg0.100` is on `VLAN_100`, and a rule on `opt7` is on
`WIREGUARD1`. The device name and pfSense's internal handle are both correct
and neither is what anybody calls the interface — reading them requires a
lookup table nobody carries in their head. Clients, ARP entries, rules, port
forwards and the rule filter chips all show the configured description now,
falling back to the raw value for an interface the app has not seen.

### Aliases are no longer used as client titles

`alias_host_app003` is accurate and useless for recognising a device in a list
of ninety — it is the name a rule refers to, not the name the machine answers
to. When there is no DNS name the address is shown instead, which at least says
where the thing is. The alias stays on the detail sheet, where it is the thing
you would search a rule for.

### Alerts can be silenced

Settings → Alerts silences everything, or individual kinds: gateways, services,
system notices, certificates, updates, capacity, HA, VPN, connection. Silenced
alerts stop driving the tab badge and the Overview banner but remain on the
Alerts screen, which says how many are hidden — an alert that vanishes without
trace is indistinguishable from a condition that cleared.

### Fixed: an empty card above every log

A log file ends with a newline, so splitting it yields an empty final element.
Reversed for display, that became the first row: an empty card sitting above
every log on every tab. Blank lines are dropped.

### DNS names first, aliases on the detail sheet

Client naming now prefers what the device is actually called on the network:
a DNS host override, then the hostname it announced, then a static mapping's
description, then a firewall alias, then its address.

An alias like `alias_host_srv001` is accurate but it is filing rather than
identity — it is the name a rule refers to, not the name the machine answers
to. It is still there, in full, on the detail sheet, which now lists every name
a device has with the source of each. The title also says which source it came
from, so a surprising name can be traced without guessing.

### Charts stay hidden until they have a line

An empty frame with "↓ — ↑ —" beneath it is not a chart waiting to fill; it is
a rectangle that takes vertical space, draws the eye, and says less than the
transfer totals directly above it. VPN cards now render nothing until there are
two samples.

The interface chart keeps its "collecting samples" caption on the Network tab,
where the chart is the point of the card, and drops it on the Overview where it
sits among a dozen other things.

### The ARP table now names things the way the Clients tab does

Every row was titled "?" — the literal string the ARP table writes when reverse
DNS fails, which the Clients tab already filters. The same device was called
"?" on one screen and `alias_host_nas001` on another. Both screens now go
through one lookup.

Two smaller things in the same rows: interface names were being uppercased by
the status pill, turning `ix0` into `IX0` which reads as the letter O — an
interface name is an identifier, not a label. And "Expires 1181" is a count of
seconds; it now reads "19m".

### Temperature, and two charts that drew solid blocks

- **Temperature works on this hardware now.** `get_temp()` returns empty on a
  box whose Thermal Sensors widget is showing 83 °C, because that widget reads
  a sysctl directly and which one depends on the chipset — "PCH 0" is
  `dev.pchtherm.0` on Intel server boards, where `dev.cpu.0` does not exist.
  Three candidates are tried in turn behind `function_exists`.

- **The metric charts scaled to zero**, so memory steady at 8% was a filled
  area covering nine tenths of the frame — a solid grey block that looked like
  a broken chart. They now scale to the data, with a tenth of the span as
  headroom, and a completely flat series is centred rather than pinned to an
  edge. The state-table trend had the same fault: 10,856 against a ceiling of
  1,621,000 was a line on the floor of an empty box.

- **Every VLAN on a lagg shared one throughput series.** They report the same
  `hwif`, so the tracker differenced one VLAN's counters against another's,
  got a negative delta, and cleared the history as if the counter had reset —
  which is why the history never grew past a point. Keyed by interface now.

  "Collecting samples" also names the interface and says how many it has, so a
  series that will never fill can be told from one that started a minute ago.

### Fixed: aliases named nothing because their members never parsed

`config.xml` stores an alias's members as one space-separated string —
`"172.16.1.50 172.16.1.51 172.16.1.52"` — where the REST API returned a list.
Reading it as a list gave an empty alias under XML-RPC: every one of the 56
looked like it had no members, the Firewall tab would have shown counts of
zero, and no client took a name from one.

Per-member descriptions have the same problem with a different separator:
`config.xml` joins them with `||`.

Both forms are now accepted, so a fixture from either transport decodes.

### Fewer calls per refresh

A full refresh ran 26 snippets, one at a time, because pfSense serialises
XML-RPC — so they queue on the firewall no matter how they are issued. Four of
them were log reads of a quarter of a megabyte each, for a tab that is usually
not on screen.

The four secondary logs (system, auth, DHCP, OpenVPN) now load when the Logs
tab appears and refresh while it is visible. The filter log stays on the timer
because the Overview shows its counts.

Still worth doing and not done: most of the remaining calls are small reads of
different corners of `$config`, and could be answered by one snippet instead of
a dozen. That would cut a refresh from roughly twenty round trips to about
five.

"Collecting samples" now says how many it has. On its own the message is
indistinguishable from "this has been stuck for ten minutes" — which is the
ambiguity that made the sparklines hard to reason about.

### Blocked hosts, attempted safely

`loadTables()` still had a `do/catch` around an assignment that could not
throw — dead code from the conversion, and the warning the compiler raised.

Rather than delete the feature, it is attempted the way the WireGuard status
call was: `function_exists` first, so a firewall without an accessor returns
"not available" rather than raising an error that pfSense would keep forever.
The two candidate names are called explicitly, and if neither exists the app
says pf tables cannot be read without a shell instead of showing an empty list
that reads as "nothing is blocked".

Writing it turned up a real hole in the publish check. The first draft picked
an accessor at runtime and called it through a variable — `$found($name)` —
which defeats the allowlist entirely, since nothing reading the source can tell
what it will invoke. `readonly.sh` now rejects variable function calls, and
skips comments when scanning, because the comment explaining this rule was
itself failing it.

### Alerts stopped reporting failures that were already fixed

Notices persist on the firewall until somebody clears them, so eighty entries
from a bug fixed twenty minutes earlier still read as "a snippet is failing".
The crash log made it plain: the last PHP error was at 16:38:24 and the
screenshot was taken at 16:50 — nothing had failed for twelve minutes.

Only notices from the last fifteen minutes now count as a current failure. The
full history stays under System → Notices, where it belongs, and if there is a
pile of old ones with nothing recent the app says so and points at the bell
icon instead of claiming a fault.

Also: the metric sparklines repeated the meter directly above them, printing
"Memory 8%" under a bar reading "Memory 8%". They now show the range the
history covers and how many samples it holds, which is what a chart adds over a
current reading.

### The app no longer writes to the firewall's log because of its own bugs

A snippet that raises a PHP error leaves a permanent notice on the firewall.
With a thirty-second refresh timer that is one notice every thirty seconds —
78 accumulated in an afternoon, filling the bell icon and this app's own alert
list with the same defect.

Retrying less often was not enough. After three faults a section is now
abandoned for the rest of the session, and says so in the card it belongs to.
Pull to refresh, switch firewall or relaunch to try again: all three are a
person saying "try again", which is the only signal worth acting on.

This is the more important half of the `host_overrides` bug. The snippet was
mine to fix; writing to somebody's firewall log every thirty seconds until they
noticed was the part that should never have been possible.

### host_overrides rewritten through pfSense's own accessor

Reading `$config` by hand kept fataling on shapes that were not what they
looked like — an empty element parses to a string, a single entry parses as
itself rather than a list of one — and a fatal inside `exec_php` returns an
empty HTTP 500 with no message to read, so each attempt cost a round trip to
guess again.

Rewritten through `config_get_path()`, pfSense's own null-safe accessor, behind
a `function_exists` guard with the hand-rolled version as fallback. Every value
is coerced with `strval` and no index is nested.

`bin/check-snippets.sh --script FILE` was added for the bisection this needed,
along with four probes in `probes/`. A fatal with no message cannot be reasoned
about; it has to be cut down until it works.

### Fixed: host_overrides faulted on every refresh

An empty element in `config.xml` — `<dnsmasq></dnsmasq>` — parses to an empty
*string*, not an empty array. `$config["dnsmasq"]["hosts"]` then indexes a
string, which is a TypeError in PHP 8. Checking `is_iterable` on the inner
value was too late: reaching it had already thrown.

That is the snippet that was writing a notice on every refresh and filling the
alert badge. Every two-level read of `$config` had the same shape and all seven
are now guarded — the section is assigned to a variable and checked with
`is_array` before anything is read from it.

This is the second time this class of bug has cost a round trip, so
`readonly.sh` now rejects any snippet that indexes two levels into `$config` in
one expression. Verified by reintroducing the pattern and watching it fail.

Two diagnostic fixes came out of chasing it:

- pfSense returns XML-RPC faults with a **500** status, and both the app and
  `check-snippets.sh` were discarding the body — throwing away the firewall's
  own explanation and leaving a bare "HTTP 500". Both now read the fault out of
  it.
- The checker's message for a 500 asserted "the PHP failed to parse, not to
  run", which was a guess presented as a diagnosis. It was also wrong: this was
  a runtime TypeError.

### Fixed after the WireGuard build

- **Firewall aliases never reached the client list.** They were fetched only by
  `loadFirewallObjects()`, which runs when the Firewall tab is opened — so on a
  normal refresh the alias table was empty and no client got a name from it.
  Aliases now load on every refresh; rules and port forwards stay on demand,
  since 98 rules is a large payload for a screen most people never open.
- **The alert list filled with the app's own errors.** A failing snippet writes
  a notice every refresh, so the badge reached 50 and every entry was the same
  PHP error, burying anything real. Notices raised by this app now collapse
  into a single alert that says a snippet is failing and where to clear them.
- **Two more charts rendered before they had a line**, the same fault as the
  duplicate meters: the state-table trend showed an empty box containing
  "10 256 →", and each gateway a stray "0ms →" repeating the figure directly
  above it. Both now render nothing until there are two samples.

### WireGuard: live status, and a secret that nearly travelled

`wg_get_status()` gives everything the Status → WireGuard page shows —
handshake times, transfer counts, endpoints — and one call now replaces the two
config-reading snippets.

**It also returns the private key of every tunnel and the preshared key of
every peer.** Returning the structure whole, which is the obvious way to write
that snippet, would have put those into the app's memory, across the network on
every refresh, and into any payload `check-snippets.sh --save` wrote to disk.
Fields are copied out by name instead, and `readonly.sh` now fails if a snippet
so much as mentions one — verified by adding a private key back and watching
the check refuse it.

Peer state now distinguishes three things that were previously one: connected
(a handshake within five minutes, which is roughly WireGuard's rehandshake
interval), idle (an older handshake — a laptop that closed its lid is not a
fault), and never connected (`latest_handshake` of "0"). Tunnels report their
real `up`/`down` status and lifetime transfer.

The snippet is guarded by `file_exists`, so a firewall without the package
returns empty instead of raising a PHP error that pfSense would keep as a
permanent notice.

### Fixed: WireGuard reported no peers

Peers are a separate section of the WireGuard package's configuration, each
naming its tunnel in `tun` — not nested inside the tunnel rows, which is where
the snippet looked. So every tunnel showed "Peers 0" while the webConfigurator
showed one connected with a handshake 53 seconds earlier.

Peers now decode with their description, public key, endpoint and allowed IPs.

What is still missing is live status. Handshake times and transfer counts come
from `wg show`, not from configuration, and reaching them needs either a shell
or a package function this app has not verified exists — guessing at one would
raise a PHP error on the firewall, which is recorded as a permanent system
notice. So a peer with no handshake data now reads "configured" rather than "no
handshake": absent data must not be reported as a failing peer.

### Added

- **Host-type firewall aliases name clients.** Most people with a structured
  firewall have already named every device they care about under Firewall →
  Aliases, so it is the richest naming source available and costs nothing — the
  aliases are already fetched for the Firewall tab.

  A description is used where set, otherwise the alias name. Only exact
  addresses count: an alias holding a subnet, a range, or the names of other
  aliases identifies no single device. Where several aliases cover one address,
  the one with fewest members wins — an alias holding a single address names
  that device, while one holding six is a group it belongs to.

- **DNS host overrides name clients.** Anything with a static address usually
  has an entry under Services → DNS Resolver → Host Overrides, and that is the
  firewall's own name for the device — far better than a reverse lookup that
  fails. Read from both the resolver and the forwarder, aliases included, and
  matched to clients by address.

  Priority is: a static mapping's description, then a host override, then a
  firewall alias, then the hostname the device announced, then its address. The static mapping wins
  because somebody typed it against that exact device.

### Mechanics

- `XMLRPCClient` handles transport, faults and TLS. Responses are wrapped in
  `json_encode` on the firewall — borrowed from hass-pfsense, which found
  XML-RPC's own null encoding unreliable — so `JSONValue` and every existing
  model kept working unchanged.
- Calls are serialised: pfSense holds a mutex for the duration of each
  `exec_php`, so overlapping requests queue on the firewall anyway.
- Field shapes differ in quiet ways and are covered by tests: ARP uses
  `ip-address`, leases report `"online"` as a string, gateways carry units in
  `"0.387ms"` and `"0.0%"`, load average may be an object.
- Logs are read from `/var/log/*.log` with `file()`. The path comes from a
  closed enum and the line count is clamped, so nothing typed reaches PHP. The
  filter log's pass/block is recovered from the line text.

## 0.1.0 — Unreleased

First working version. Nothing has shipped, so this is the whole feature set
rather than a list of changes.

### The app

- Five tabs: Overview, Clients, Network, Logs, and More, with Alerts, VPN,
  Firewall, System, Firewalls and Settings behind the last one.
- Clients assembled by joining DHCP leases, the ARP table and static mappings
  on MAC, with an IP fallback. Tapping through shows the filter-log lines
  mentioning that address.
- Throughput sparklines derived from lifetime byte counters by differencing
  consecutive samples. Sixty points per interface, cleared when the counter
  resets or the firewall is switched.
- An alerts feed computed on device: gateways, stopped services, disk, memory,
  swap and mbuf pressure, state-table fill, available updates, certificate
  expiry, CARP maintenance mode and IPsec state.
- VPN status for OpenVPN, IPsec and WireGuard.
- A read-only browser for firewall rules, NAT port forwards and aliases.
- CARP status, configuration revision history and certificate expiry.
- Multiple firewalls, each with its own keychain item, TLS settings and
  refresh interval.
- A home screen widget in the small and medium families, fed by a snapshot the
  app writes to the App Group rather than by its own networking.
- All four Catppuccin flavours and all fourteen accents, with separate
  light-appearance and dark-appearance choices.
- TLS: SHA-256 leaf pinning, with untrusted-certificate acceptance as the
  weaker fallback.

### Fixed before first build

- `APIClient` still called the single-server `Keychain.apiKey()` after the
  multi-firewall rewrite. Every request threw `noAPIKey`; the compiler caught
  it, but only once something built.
- No test target and no declared scheme, so `make test` failed with "Scheme
  Vaktpost is not currently configured for the test action". `project.yml` now
  declares the scheme rather than leaving Xcode to invent a non-shared one.
- `SUPPORTED_PLATFORMS` was left to fall back, which xcodebuild reported as
  "Supported platforms for the buildables in the current scheme is empty".
- `project.yml` used XcodeGen's `info:` and `entitlements:` keys, which
  *generate* the files they point at. Every `xcodegen` run overwrote the
  hand-written Info.plists and entitlements: the app lost `UILaunchScreen` and
  its ATS exception, both entitlements became empty dicts taking the App Group
  with them, and the widget lost its `NSExtension` dictionary. Nothing failed
  to build — the simulator just refused to install, with "extensionDictionary
  must be set in placeholder attributes". Now `INFOPLIST_FILE` and
  `CODE_SIGN_ENTITLEMENTS` under `settings`, with a check in
  `vaktpost-tools/tests/layout.sh` so it cannot recur silently.
- `Health.color(_:)` was nonisolated while reading `@MainActor` state off
  `ThemeManager`. Older toolchains warned; the one in Xcode 26 errors. Now
  `@MainActor`, which costs nothing because every caller is a SwiftUI view and
  `View` is itself main-actor isolated.

### Fixed against a live firewall

First run against real hardware (pfSense Plus 26.07). Five field-name guesses
were wrong, and every one failed by rendering a plausible zero rather than an
error — which is the worst way for a dashboard to be wrong:

- Uptime is `"5 Days 01 Hour 37 Minutes 40 Seconds"`, not a count of seconds.
  Reading it as an integer took the leading 5 and stopped, so a box up for five
  days showed "up 0m".
- Load average is `cpu_load_avg`. None of the three names tried existed, so the
  row read "—".
- The state table fields have no underscores — `currentstates`, not
  `current_states` — and `maximumstates` is null unless overridden, so the
  enforced limit is `defaultmaximumstates`. Together those showed "Current
  states 0" on a firewall holding 11,169, with no meter.
- `status/interfaces` returns a dotted netmask, so addresses rendered as
  `203.0.113.9/255.255.255.224`.
- A live WAN reports `"enable": false`. That field tracks something other than
  administrative state, and treating it as authoritative greyed out a working
  uplink. Health now follows link state.

Interfaces now show `descr` ("WAN_1") rather than the internal `name` ("wan"),
and the Overview gained a hardware row from `platform` and `cpu_count`.

`Tests/VaktpostTests/LiveShapeTests.swift` pins all of this to payloads pasted
verbatim from `curl`. Hand-written fixtures only test the field names their
author already believed in, which is precisely what failed here.

### Fixed after a second live run

- A cancelled request was reported as a TLS handshake failure. `.cancelled` was
  in the TLS bucket because a rejected certificate pin does surface that way —
  but so does every ordinary cancellation: backgrounding, switching firewalls,
  a refresh superseding the one in flight. The result was "TLS handshake
  failed. Pin the certificate…" above a dashboard showing data fetched seconds
  earlier.
- A fatal connection error now requires that *no* section succeeded. One
  unlucky request should not put "Cannot reach firewall" over a working screen.
  A rejected key or failed pin fails everything, so it still surfaces.
- Throughput no longer samples on a failed interface fetch. `interfaces` keeps
  its previous contents when the fetch fails, so re-ingesting them produced a
  zero delta over the elapsed interval — a confident "0 bit/s" on a link
  passing traffic, and a notch in the chart that never happened.
- CARP is hidden on firewalls that don't do HA. The endpoint answers
  everywhere, so `enabled != nil` was true on a standalone box and the Overview
  carried a permanent "CARP disabled" row about a feature you aren't using.
- With Follow system, the flavour grid now marks which appearance is in effect.
  Both grids looked identical, so tapping a swatch in the one you aren't
  currently in appeared to do nothing.

### Changed

- `make teams` prints the team id rather than the certificate name.
  `security find-identity` shows a common name whose parenthesised code is, for
  a development certificate, the certificate's own id and not the team's —
  pasting it into `TEAM_ID` fails with a provisioning error that blames the
  wrong thing. The team id is the certificate's OU field, which is what the
  target now reads and prints in its own column.
- `make install` and `make archive` validate before generating the project.
  With `project` as a prerequisite, xcodegen ran first and the real message was
  buried under three lines of generator output.
- Both now name the variable when a near-miss is set (`TEAM`, `TEAMS`,
  `TEAMID`, `TEAM_IDS`) and print the exact command to run, with the values you
  already supplied filled in.
- `make devices` notes that only iPhones and iPads are targets, since an Apple
  TV in the list looks equally installable.

- OpenVPN servers no longer show a fabricated "UNKNOWN" status.
  `status/openvpn/servers` returns no status field on 26.07 — a running server
  simply appears in the list — so the pill was a placeholder dressed up as a
  reading. It now shows what the endpoint actually supports: "2 connected", or
  "no clients", which is a normal state for a remote-access server rather than
  a fault. A `status` field is still preferred where one exists, since the
  clients endpoint reports one.
- Each connected OpenVPN client now shows "last seen", taken from the server's
  route table.
- The theme picker is one list of five: Auto, Latte, Frappé, Macchiato, Mocha.
  The previous design had a mode toggle plus separate light and dark grids —
  three controls deep for a decision made once, with two visually identical
  grids so half of every tap landed on the appearance you weren't in. Auto is
  Latte in light and Mocha in dark; anything else is pinned. An existing fixed
  choice carries over. The word "flavour" is gone from the interface; the
  palettes are still Catppuccin's.

### Fixed: snippets crashing on single-entry config sections

pfSense's config parser returns a section holding exactly one entry as that
entry, not as a list of one. `foreach` then walks the entry's *fields*, which
are strings, and indexing a string throws `Cannot access offset of type string
on string`. Every loop over `$config` had the hazard; all eight are now guarded.

The failure was visible because pfSense records an uncaught PHP error as a
system notice — so the app read its own stack trace back out of the firewall
and displayed it as an alert. Two consequences worth handling:

- Long notices collapse to their first line with a "Show full notice" control.
  A backtrace shown whole filled the screen and buried the five alerts under
  it.
- A notice raised by this app is labelled as such. Its own bug arriving as an
  apparent firewall fault is a bad way to be wrong.
- Notice text is HTML-unescaped; pfSense stores it escaped, so traces arrived
  full of `&gt;` and `&#039;`.

Note that these notices persist on the firewall. Clear them from the bell icon
in the webConfigurator once the snippets are fixed.

### A suite that catches members before the compiler does

Three build failures in one afternoon had the same cause: a patch applied by
matching text landed in the wrong struct, or matched nothing and silently did
nothing, and a view kept calling a property that was never written.
`vaktpost-tools/tests/members.sh` resolves every member against the declared
type of its binding and finds these in under a second, where the compiler needs
a project regeneration and reports one file at a time.

It now covers four classes, each of which cost a build today: a member its type
does not declare, an enum case no switch handles, a view using `store` or
`theme` without a binding for it, and a `"""` literal opened and closed on one
line. None is subtle — Swift refuses all four — but the compiler reports them
one file at a time after a project regeneration, and this reports all of them
at once in under a second.

It also checks enum exhaustiveness. Swift enforces that itself, so this is not
about correctness but about when you find out: adding `.haproxy` to `Section`
and forgetting the switch is a two-minute build away from the error, and a
second away here. That happened twice.

`bindDescription` and `routingDescription` had landed in `HAProxyServer`
instead of `HAProxyFrontend` — both structs end with the same `health` line, so
a replace-first matched the wrong one. Fixed, and now caught automatically.

### Alerts can be acknowledged one at a time

Silencing a whole category was the only control, and it is the wrong shape for
what people actually want — "I have seen this one" rather than "never tell me
about capacity again".

Long press an alert to acknowledge it. The identity used is the category, the
severity and the title with digits removed, so "Chipset at 81 °C" and "Chipset
at 83 °C" are the same acknowledgement — otherwise it would need doing again on
every degree. Severity is part of it on purpose: something you decided to live
with as a warning is not something you decided to live with when it turns
critical.

Acknowledgements persist, are listed by name on the Alerts screen with a way to
undo them, and are dropped when the condition clears — otherwise acknowledging
a gateway that was down would silence that gateway going down again next month.

### The settings toggles read backwards

Under a heading saying "silence individual kinds", every switch meant *shown*
and every switch was on. So the screen looked like everything was already
silenced, and turning one off silenced nothing. On now means silenced.

That probably explains the missing thermal alert: the context menu's "silence
all capacity" is one tap away from the alert, and the temperature alert moved
into that category earlier the same day.

### The temperature threshold was guessing

`get_temp()` returns a number without saying which sensor produced it, and the
number alone is not interpretable — 81 °C is unremarkable for a chipset and
worth investigating on a CPU die. The snippet now probes the sysctls first,
because that is what identifies the sensor, and only falls back to `get_temp()`.
An unidentified sensor gets 90/100 rather than 80/95: an alert nobody can act
on is how a list stops being read.

### Seven smaller things

- The "Refreshing…" pill is a plain spinner. It announced something nobody
  asked about, every thirty seconds, over the screen behind it.
- WAN and LAN are pinned to the Overview by default, seeded once so removing
  one sticks. A default that reasserts itself is not a default.
- VPN is split by technology, and only shows tabs for what the firewall runs.
- System Certificates offers CAs / Certificates / Expiring. "All" mixed
  authorities that never expire with the certificates you came to check.
- The System screen can check pfSense's own version on demand.
- The username field no longer suggests `admin` — the setup notes ask for a
  dedicated account, and the field should not argue with them.
- Acknowledged and silenced alerts are counted separately, so the same alert is
  not reported as hidden twice for two different reasons.

### Sensors is an ordinary kind of alert

It had its own heading and a slider, which made a temperature threshold look
like a different class of setting from the switches under it. It is a row like
the rest now, with a thermometer beside it.

That needed a real category: temperature alerts rode under Capacity, so
somebody who wanted to stop hearing about a warm chipset had to silence disk
and memory warnings with it.

The threshold has not gone — it is a long press on the row, in fixed steps
rather than a slider. The useful answers are "follow the sensor" and a handful
of round numbers, and a slider asked somebody to aim for one of them.

"Kinds to show" is "Kinds of alerts".

### The RRD files stopped being written 25 hours ago

The trace settled it: `last written 19:49:24 (90541s ago)`, every value in the
24-hour window NaN, and the file header showing `unknown_sec = 24`. Nothing has
been recorded since. That is a firewall-side condition — pfSense writes these
every minute while monitoring is on — and no fetch argument reaches around it.

So the app was right all along and its message was the only thing wrong. The
snippet now carries each file's last-write time, and both the diagnostics panel
and the empty chart say how long it has been rather than counting series
nobody can act on.

Two faults in the trace script itself, both mine:

- It described `/var/db/rrd/ipsec-traffic.rrd` — the first file alphabetically,
  and quite possibly an interface carrying no traffic at all. It looks at the
  WAN file now, and reports every file's age so one dead interface is not read
  as a dead firewall.
- It blamed a step mismatch. The age check ran *after* the NaN check, and I put
  it there deliberately in the last round while fixing something else. A file
  unwritten for 25 hours explains all-NaN completely; the dull cause has to be
  ruled out before the interesting one is offered.

### A trace script for the RRD history

"207,504 values offered, 0 numeric" rules out the transport, the snippet's
shape and the Swift decoding, and leaves the values themselves — which cannot
be identified by reading code from here. Three rounds have gone on guessing
between the possibilities.

`bin/rrd-trace.sh` asks the firewall directly: the values' PHP types, the first
few as strings, the file's step and archives, and how long since it was last
written. Then it says what that means, because a type dump still leaves
somebody to interpret it.

The NaN check comes before the numeric one, deliberately: `is_numeric(NAN)` is
true in PHP, so a NaN reads as a number right up until `json_encode` refuses
it. That confusion is what put a whole day of unknowns behind a fetch that
looked like it worked.

It runs `check-snippets.sh --only rrd_trace` rather than owning a second copy
of the transport, so the password is prompted for once by the script that
already does that carefully.

### Editing a firewall stopped working

Edit was a `swipeActions`, which does nothing outside a `List` — converting
that screen away from one silently removed the only way to change a firewall's
address. It is a button on the card now, with an entry in the context menu
beside Remove.

Removing the List was right; not checking what the List had been providing was
not.

### The All chip is back, at the end

Taking it out left "no filter" as a state reachable only by tapping the
selected chip again, which nothing on screen suggested. At the far end of the
row it is out of the way of the interfaces without being invisible.

### Every RRD value came back unknown

Eight series per interface, none with a sample in them — so the fetch works and
the data structure parses, and every value inside is being rejected.

The window was asked for as `--start -86400 --end now`. rrdtool's own default
is the last day ending now, which is exactly what is wanted, so the arguments
are gone: `rrd_fetch($path, ["AVERAGE"])`. Whatever the extension made of that
explicit window, not passing one cannot be misread.

The response now also counts values offered against values kept. Nothing
recorded and everything rejected produce the same empty chart, and they need
different fixes.

### The firewalls sheet belonged to a different app

A `List` with `.plain` style keeps the system background — white in light
appearance — where every other screen is a ScrollView over `theme.bg`. It is
one now. The section header went with it: the navigation title already says
"Firewalls", and saying it twice on one screen reads as a mistake.

Removing a firewall moved from swipe to a context menu, since swipe-to-delete
is a List behaviour and the List is gone.

### RRD reads, and the chart was drawing the wrong eight lines

The diagnostics panel answered it: 144 series across 18 interfaces, so
`rrd_fetch` is present and the data arrives. A pfSense traffic file holds eight
data sources — pass and block, in and out, v4 and v6 — and the chart drew all
eight, which puts six near-flat lines under the two worth reading and gives the
app nowhere to say which is which.

It draws the pass series now, coloured by direction, and skips any series with
no samples. A chart with nothing left to draw says so instead of rendering
blank. The diagnostics panel counts samples as well as series, since "144
series" says the fetch worked and nothing about whether any of them carry data.

### Smaller things from a pass on the device

- Search moved below the page heading on Logs and Network. `.searchable` puts
  its field in the navigation bar, above the header these screens draw
  themselves, so the search came first and the title second.
- Floating is a chip beside the interfaces, which is what it is: a rule set
  belonging to no single one of them. "All" is gone — tapping the selected chip
  clears the filter, which is what All did with one chip fewer to read.
- The temperature threshold moved into the alerts card under "Sensors". It is a
  threshold for one kind of alert, and standing alone it looked like a
  different sort of setting.
- Network charts are the same height as the Overview's. A 44-point strip is a
  sparkline; these are the charts somebody opened that tab to read.
- Filter lines in the Overview's firewall card open their detail, like the same
  rows on the Logs tab.
- First-run setup offers to pin the certificate. The edit screen has offered it
  for a while and the first-run screen did not, which is backwards: a first
  connection is when pinning is worth most and when nobody thinks to look for
  it.
- Dragging a section needs two thirds of a neighbour's height rather than half.
  Half means a card swaps the instant it overlaps, so a wobble near a boundary
  flips it back and forth.

### The firewall menu manages firewalls

"Log out" was the only thing that menu offered besides switching, which framed
the app as something you sign in and out of. It is not — it holds a list of
firewalls, and what you want from that menu is to add one, fix an address or
remove one you no longer run. It opens the management page now, and the active
firewall carries a tick, which with three of them the menu previously gave no
clue about.

The bulk "log out" on the management page went too: firewalls are removed
individually by swipe, and removing one clears its credentials, so it did
nothing the swipe does not.

### The drag was jumpy because one height stood for all of them

Sections range from a status banner to a full system card, and the drag divided
the finger's travel by a single 80-point estimate. One number was too large for
half the sections and too small for the rest, so a card would jump two places
or refuse to move.

Each row reports its own height through a preference key now, and the drag
walks the real geometry: a card swaps once it is more than halfway over its
neighbour, where halfway depends on how tall that neighbour actually is. The
offset that keeps the card under the finger sums the real heights it has passed
rather than multiplying a count by an average.

### The RRD state is on the diagnostics screen

A chart that draws nothing cannot explain itself in the space it has. The
diagnostics screen now says which of the five states the last read reached —
not read, reading, failed, unsupported, or working — and in the working case
lists the file names that came back, because those are what the interface
screens match against.

The same panel settled the throughput mystery in one screenshot. It is a better
tool than another round of me reasoning about it.

### Sections move while you drag them

The drag computed a drop target and applied it only on release, so nothing
moved until you let go — and the offset that was meant to nudge the neighbours
returned zero unconditionally, so it never could have.

The list reorders now while the finger is down. Everything else animates into
place because the ForEach re-renders with the new order, which is what makes
the cards move in relation to each other. The dragged card's offset is the
finger's travel minus the distance its own slot has moved, or it runs away from
the cursor by a row each time the list shifts.

The lift, scale and shadow were on the header row rather than the card, so
dragging moved a heading and left its contents behind. They are on the card.

The row height is still an estimate — sections differ a lot, and measuring each
one needs a preference key per section. The comment says so rather than
implying it is measured.

### Tooltip bubbles ran off the edge

`.position` centres a bubble on the x it is given, so a sample at either end
put half of it outside the chart. The marker stays on the sample and the label
slides in far enough to stay readable.

### An empty RRD card said nothing at all

`RRDHistoryView` had no branch for "read, and empty" or "not read yet", so both
rendered as a blank card — which is how a screen can be least useful. Every
state says something now, and the working state lists the file names that came
back, because those are what the interface screens match against.

### The overview's arrangement was never saved

Dragging a section rearranged the screen and the next appearance put it back.
The order lived only in the view's `@State`, and the loader rebuilt it by
filtering `allCases` — which returns declaration order and discards whatever
was stored. Both halves had to agree that the stored array *is* the order.

All three paths that reorder now write it back to the profile, so it is kept
per firewall like the rest of that screen's settings.

### Chart readouts sat off the line

Three faults in the same few lines.

`.offset` on a ZStack child is measured from the *centre* of the stack, while
the paths are drawn from its top-left — so every marker and label was displaced
by half the chart in both directions. `.position` is the one that takes the
same coordinates the line does.

The index truncated instead of rounding, so a tap two thirds of the way between
two samples reported the one on its left. And the marker was drawn at the
tapped x with the sample's y, so it floated off the line by however far the
finger was from a sample. The tap now snaps to the nearest sample and both
coordinates come from it.

The clamp allowed `count`, one past the end: a tap on the right edge of either
chart indexed out of bounds. That one was a crash waiting for somebody to tap
the last pixel.

### "No recorded history" meant three different things

Never read, cannot be read, and read-but-nothing-matched all fell through to
the same sentence. They are separate now, and the last one lists the file names
the firewall actually returned — RRD files are named for pfSense's internal
handle, so if that differs from what the app expects the match is one string
away from working, and an empty chart alone would send us guessing again.

### NaN broke the whole RRD response

The history read failed with "the response wasn't in the expected XML-RPC
format", which is a sentence that fits a PHP fatal, an HTTP error page and a
truncated body equally well.

The likely cause: RRD writes NaN for gaps in its data, `is_numeric(NAN)` is
true in PHP, and `json_encode` fails *outright* on NaN — returning false for
the whole document rather than skipping that value. The wrapper then puts a
boolean where a JSON string belongs, and the app reports a malformed response.
One missing sample poisoned everything. `is_finite` is the check that actually
excludes it, and INF with it.

The other floats the snippets encode all come from `floatval` on a string,
which yields 0.0 rather than NaN, so this was the only exposure.

### A malformed response now says what came back

Whether or not NaN was the cause, "not in the expected format" was never going
to identify it. The error now carries the first 200 characters of what the
firewall actually said — pfSense prints its fatals into the response, so that
usually names the function and the file.

### Every log line opens, not just filter lines

A DHCP or OpenVPN line is a sentence with a syslog prefix, and the list shows
two lines of one that may run to twenty. Tapping any line now splits off the
timestamp, host and process, gives the message room to wrap, and names any IPv4
address in it — a lease going to 172.16.1.161 is more use when the screen also
says which device that is.

IPv4 only. An IPv6 address cannot be told from a MAC or a fragment of a
timestamp without more care than a convenience like this deserves, and a wrong
guess would put a name against the wrong thing.

### "What this app cannot read" is gone

It listed RRD history as unreachable on the same build that now attempts to
read it, which is the kind of stale certainty that makes a whole screen less
trustworthy. Each gap is now said where it comes up, by the screen that has it.

### Smaller things from a pass on the device

- The Network tab's interface cards carry the same chart the Overview does.
  Lifetime counters say how much has gone through an interface since boot and
  nothing about whether anything is going through it now.
- Rule and NAT rows keep FROM, TO and PORT to one line each. A rule whose
  source expands to twenty networks was four lines tall in a list of
  ninety-eight, and the list exists to be scanned.
- Their detail screens put one address per line instead of a wrapped run. A
  wrapped run breaks mid-address, so `198.51.100.0/22` can end one line and
  start the next.
- `WHY` is `DESC`.

### Observing an optional does not compile

Two of the six views held their tracker as an optional, and `@ObservedObject`
cannot wrap one. Both were defensive wrappers around store properties that are
never nil, so the optional bought nothing and cost the redraw — which is how
the staleness got in.

I made the same conversion by hand twice and got the same compile error twice,
so rule 10 now checks both directions: an observable held as a plain `let`, and
something observed that is optional or not observable at all. The fix for one
is the failure mode of the other.

### The chart never redrew, and five others had the same fault

The diagnostics screen settled it in one look: three points recorded for WAN_1,
a card saying "none yet", and VLAN_100 saying "1 so far" — three different
numbers for one tracker. The chart was not stale in the data; it was not
re-rendering at all.

`ThroughputChart` held `let store: DashboardStore`. SwiftUI decides whether to
re-render by comparing a view's stored properties, and a reference never
changes — so the body ran once, when the card was created, and kept whatever it
saw. A card created before the first sample said "none yet" for the rest of the
session. VLAN_100 was created a refresh later and froze at one.

Nothing about that is a compile error. It produces a screen that is quietly,
permanently wrong, which is the worst kind of bug this app has produced, and I
spent four rounds reasoning about PHP field names and tracker arithmetic that
were correct the whole time.

A tenth rule now flags a View holding an ObservableObject as a plain `let`. It
found five more on its first run: gateway latency and three VPN throughput
cards had the same fault and would have been just as wrong. The VPN one held
the tracker as an optional, which cannot be observed at all — the store's
tracker is never nil, so the optional bought nothing and cost the redraw.

The rule also needed tightening: matching `ThemeManager` inside
`ThemeManager.Selection` reported a nested enum as an observable, and a rule
that has to be argued with is a rule that gets ignored.

### Historical traffic, where the firewall will give it up

pfSense records months of per-interface traffic in `/var/db/rrd`, and this app
has only ever shown what it watched since launch. The interface screen now
reads a day of it and draws it under the live chart — separate rather than
merged, because one is five-minute averages over a day and the other is two
seconds, and on a shared axis the live one would be a vertical line.

The read is guarded. RRD is a binary format normally read by `rrdtool`, a shell
binary, and shelling out is what the snippet rules forbid; PHP can read it only
with the `rrd` extension loaded, which is not standard on pfSense. Where
`rrd_fetch` exists it is used, and where it does not the screen says exactly
that instead of showing an empty chart that looks like an interface with no
traffic.

Every interface at once, with no parameter, because a snippet is a constant —
interpolating an interface name would mean assembling PHP at runtime, which is
the one thing that would make the allowlist unreviewable. Downsampled to 120
points a series: a day at RRD's finest resolution is 1440 buckets per direction
per interface, which is a megabyte of JSON to draw a line 200 points wide.

### Rules and NAT read as four labelled lines

FROM, TO, PORT, WHY — in that order, so a column of rules can be read down
rather than across. The port has its own row because it belongs to neither side
and squeezing it beside one made both wrap. NAT cards took the same shape, with
SENDS for the target.

The kind marker went with the alias names: with the names resolved it was
labelling an address as "alias", which describes where the value came from
rather than what it is. The detail screens resolve too — the name above its
members was the same duplication the list had already dropped.

### One chip per interface, not one per combination

A floating rule names every interface it applies to, so the raw values produced
a chip reading "OPENVPN1, OPENVPN2 +11" — a filter for a set nobody thinks in.
The chips are now individual interfaces, and choosing one shows every rule that
applies to it, floating rules included.

### Sharing a log showed a blank page

The button handed `UIActivityViewController` an array of a hundred-odd separate
strings, so it tried to preview a hundred documents at once and rendered an
empty sheet with a placeholder icon. A log excerpt is one thing you are
sharing; it travels as one document now, through `ShareLink`.

### Back from a rule went to More, not the rule list

`MasterDetail` created a `NavigationStack` of its own, and Firewall is pushed
from More — so a stack nested inside a stack, and going back popped the outer
one. A screen that may be pushed cannot own the stack it is pushed into.

It drives the ambient stack now, which works whether the screen is a tab root
or pushed. Clients is wrapped by the shell again, as it was before.

### Rules and NAT show addresses again, not alias names

Adding the kind markers reintroduced the alias names in the rows — the thing
that had already been removed once. Both sides and both ports resolve, with the
kind still marked so an entry expanding to several addresses is not mistaken
for one.

### The dashboard chart reports its own state

The two-second detail chart draws and the thirty-second dashboard chart does
not, and reading the code has not explained why: the keys match, the counters
arrive — the Network tab renders them — and the arithmetic is covered by
passing tests.

So rather than reason about it further, Diagnostics now lists every series the
tracker holds, how many points each has, and which interfaces have a baseline
but no rate. One look at that screen says whether ingest is running at all,
which is the fact I have been guessing at.

### A ninth rule: views used but not defined

Removing the ARP pane with a non-greedy regex matched to the wrong closing
brace and took `InterfaceCard` and `ARPRow` with it. `ARPRow` was meant to go;
`InterfaceCard` was not, and the Network tab stopped compiling.

That is the third edit today to delete more than intended. The members suite
now flags a `*View`, `*Card` or `*Row` that is used but defined nowhere, which
is what all three looked like from the outside.

### Tapping a client went black and bounced back

`MasterDetail`'s compact path was a computed binding whose getter built a fresh
array on every evaluation, so SwiftUI saw the path change identity
mid-transition and unwound it. The path is held now and mirrored to the
selection in both directions.

Tidier code that does not work is worse than plainer code that does, and the
derived binding was chosen for tidiness.

### Filter log lines open

`filterlog` writes a documented CSV and the app was showing it raw — a wall of
commas where the rule, the direction and the ports are countable but not
readable. Tapping one now names them, resolves the addresses to the devices the
firewall knows, and finds the rule the tracker refers to. The raw line stays at
the bottom, because parsing is lenient and the tail varies.

Two offsets were wrong before the real lines were tried: the protocol appears
twice, a number then a name, and taking the number gave a column reading "6"
where "tcp" belonged. IPv6 carries class, flow label and hop limit where IPv4
carries tos, ecn, ttl, id, offset and flags, so reading v6 at the v4 offsets
reported the hop limit as the protocol. Both fixed and covered by tests using
lines from the firewall.

### Firewall rules say more in the list

Interface, protocol, both sides with their ports, and the description. Each
side is marked with what it is — host, network, alias, interface, any —
because four rules that look alike in a list can be doing very different
things, and pfSense does not say which is which anywhere visible. The tracker,
IP version and logging flag stay on the detail screen: they matter when you are
working on a rule, not when you are looking for one.

### Overview charts are taller, and keep four hours

60 samples was chosen when the chart was a sparkline. A pinned interface is
pinned to be looked at, so the tracker keeps 480 points — four hours at the
default refresh — and the Overview draws them at twice the height. pfSense
keeps months in RRD and this app cannot read it, so the history it keeps itself
is all there is.

### The ARP tab is gone from Network

Clients already joins ARP with leases and static mappings, names each device
and shows its filter log. A second, thinner view of the same table was a place
to look that answered less.

### An eighth rule: the snippet catalogue

Regenerating the batches cut from the first batch to a `// MARK:` comment, and
`rrdProbe` had been added between them — so it was deleted while still named in
`all`, which does not compile.

The members suite now checks both directions: a name in `all` that is not
declared, and a snippet declared but missing from `all`. The second matters
independently — `all` is what the publish check audits and what
`check-snippets.sh` exercises, so a snippet absent from it is unaudited.

Two of today's edits have now cut a wider range than intended. Deleting by
index between two markers is fast and does not notice what it passes over.

### The batch accumulator collided with a body's own variable

Clients and the ARP table came back empty on device, with no error anywhere.
The batch had succeeded.

The accumulator was called `$sections`, and `host_overrides` uses that name for
a local — starting with `$sections = [];`. Every section captured before it was
discarded, and its own `$sections[] = …` appends left the result structurally
valid and wrong. So the app decoded a well-formed response containing nothing,
and reported success.

That is the worst shape a bug can take here: an empty network and a broken
fetch look identical, which is the thing this app keeps having to distinguish.

The accumulator is `$vaktpost_batch` now, and a test asserts no other snippet
mentions that name — the accumulator shares scope with every body in its group,
so the collision is structural rather than bad luck. A second test asserts each
capture appears after its own body and before the next, since a capture in the
wrong place stores the previous section's result under this section's name and
decodes cleanly.

Clients and the ARP tab also say when a fetch failed rather than showing their
empty state. ARP already did; Clients did not, and "No clients seen" is a
reassuring sentence to show somebody whose firewall is not answering.

### Floating rules name every interface they apply to

`opt5,opt6,opt7,lan,opt10,opt11,opt12,opt13,opt2,opt3,opt4` was printed raw,
which is both unreadable and the one place the configured names matter most.
A list covering everything now reads "all interfaces"; a shorter one names the
first two and counts the rest.

### The drift test was comparing the wrong thing

Every batch "had drifted from" every one of its parts. Not drift: the test
compared `script`, which is the *wrapped* form — every snippet gets an
`ini_set`, a lock release and a `json_encode` tail, and a batch has one wrapper
rather than five, so comparing scripts compares the wrappers too and can never
match.

`PHPSnippet` now exposes its unwrapped `body`, and the test compares that.

Worth recording how this got shipped: I simulated the assertion before writing
it and the simulation passed, because it compared bodies while the test I then
wrote compared scripts. Checking a test by re-implementing it only works if the
re-implementation does the same thing, and mine quietly did the right thing
where the test did the wrong one.

### The widget is gone

It was the least-used surface and the most expensive: a second target, a shared
snapshot type, an App Group, and its own copy of the palettes and the Dynamic
Type modifier. It also carried a bug found an hour ago — it looked up
throughput by the wrong key and had been showing no rate at all.

Removing it takes the App Group with it, which removes the one thing that made
a first install fail: an App Group must be registered on the developer account
before Xcode will sign against it. The entitlements file is now deliberately
empty, and the layout check warns if anything reappears in it.

### GENERATE_INFOPLIST_FILE was off

Comparing the two projects once more, this time the target settings rather than
the catalogue: a project where icon switching works sets `INFOPLIST_FILE` and
leaves `GENERATE_INFOPLIST_FILE` alone. This one set it to NO.

That setting controls whether the build merges the partial plists other steps
produce — including the one the asset catalogue compiler writes with
`CFBundleIcons`, which is exactly what `setAlternateIconName` reads to find the
alternates. With it off, the alternates can be compiled into the bundle and
still be invisible to the runtime.

It is removed. The layout check now asserts the hand-written plist keeps the
keys only it carries, since the opposite failure — a generated plist replacing
it — is what that setting was there to prevent.

The earlier "Registered: AppIcon-amber, …" reading came from a build where I
had declared the alternates in the plist by hand. That block came out two
rounds later, and nothing has confirmed the keys were present since.

### Every icon set had the same filename

Comparing against a project where switching works, key by key: the build
settings match, the Info.plists are equivalent, the catalogue structure is the
same, the images are 1024, RGB, no alpha. One difference left — six
`appiconset` directories in one catalogue each containing a file called
`icon.png`, where the working project names each after its colour.

`INCLUDE_ALL_APPICON_ASSETS` copies these into the bundle, and six sources
sharing one name is the kind of thing that survives a build and fails at
runtime. Renamed, previews too.

Whether that is the cause I do not know. It is the only difference left between
a build that switches icons and one that does not, which is a better reason to
change it than any of the theories that came before.

The picker also reports whether `CFBundlePrimaryIcon` is declared. iOS refuses
to switch in an app with alternates and no primary to switch back to, and gives
the same unhelpful `EAGAIN` for it. The alternates have been confirmed present
twice; that half has never been looked at.

### Icon switching uses the async call

A working project on the same device does this and nothing else:

    try await UIApplication.shared.setAlternateIconName(icon.alternateName)

This app had the completion-handler variant wrapped in
`DispatchQueue.main.async`, an `applicationState` check, an eight-step retry
loop, a pending icon kept until the scene became active, and a `scenePhase`
observer to apply it. Every piece of that was built to work around `EAGAIN`,
and every piece was a guess at what iOS wanted. The async variant does not
produce that error.

All of it is gone. The build settings and the asset catalogue turned out to
match the working project exactly — the call was the only difference, and it
was the one thing I never compared.

It was not the widget, which was removed several rounds ago.

### Icons: the simulator was never going to work

`NSPOSIXErrorDomain 5` — `EIO`, an I/O error — from the simulator, where the
earlier device attempts gave `EAGAIN`. Two failures that look alike and are
not: the simulator has no Home Screen icon database to write to, so alternate
icons cannot work there at all.

Showing the domain and code is what made this visible. "The operation couldn't
be completed" had been the same sentence for both, and I had spent two rounds
treating a simulator limitation as a timing problem — adding delays, then
waiting for `.foregroundActive`, then a pending retry, none of which could ever
have helped there.

The picker now says so before the tap rather than after: the simulator cannot
change app icons, and the choice will apply on a device. Retrying is not
offered, because a suggestion that can never work is worse than none.

The device path keeps the pending retry, which is still the right answer for
`EAGAIN`.

### Icons: a refused change is remembered

`setAlternateIconName` kept returning `EAGAIN` on a device where the app was
plainly in front and all five alternates were registered. The documented reason
is that the app is not `.foregroundActive`, and waiting for that was not
enough.

So rather than keep guessing at delays: a refused icon is kept and applied when
the app next becomes active. Leaving Settings and coming back does it. That
turns a failure the person can do nothing about into one they can, and costs
nothing when the call works first time. The picker says what is pending.

Errors now include the domain and code. "The operation couldn't be completed"
is the same sentence for a dozen different problems, and knowing which one is
the whole difficulty.

### A diagnostics screen

Every section already recorded why it failed, but that error only appeared on
the card it belonged to — so an empty Gateways card meant finding the Gateways
card to learn why, and "is the app healthy" meant visiting nine screens.
Several of this app's own bugs went unnoticed for a session because the
evidence was scattered.

Under More: what is failing, what has stopped being retried and after how many
attempts, and the connection itself. Nothing is fetched; it is what the last
refresh already found out.

It also writes down what this app cannot read and why — blocked hosts, live
HAProxy status, UPnP maps, historical graphs. Each cost a round of guessing to
establish, and an empty screen looks identical to a broken one without the
explanation.

### The widget was showing no rate at all

It looked up throughput by `device` while the tracker stores by `seriesKey` —
the VLAN-on-a-lagg bug, fixed in the tracker weeks ago and missed in this copy.
The key never matched, so the rate was always absent.

It also follows whatever is pinned to the Overview now rather than always the
uplink, and says which interface it is showing. A bare rate does not say what
it is a rate of.

A test asserts the two keys stay in step.

### The ARP tab searches the name it shows

It displayed the resolved name — DNS override, then lease, then static mapping
— but searched only the announced hostname. Typing the name on the row in front
of you found nothing.

### iPad gets a list and a detail side by side

The app was an enlarged phone: a column of cards down the middle of a 13-inch
screen, and tapping one replaced the whole thing. Clients and Firewall suffer
most, because comparing two entries is most of what you do there.

Both now show the list on the left and the selection on the right at regular
width, and behave exactly as before on a phone.

Two decisions worth recording:

- **An HStack, not a `NavigationSplitView`.** A split view can only be a root,
  and these screens are not all roots — Firewall is pushed from More. Nesting
  one inside a navigation stack puts the detail in the wrong column or drops
  it. An HStack composes anywhere and gives the same thing.
- **Selection is an identifier, not the item.** A stored copy of a row goes
  stale on the next refresh: thirty seconds later the detail pane would be
  showing counters from before the last sample. The id is looked up again each
  time, so the detail follows the data — and the compact path is derived from
  the same selection, so a back swipe clears it and the two layouts cannot
  disagree about what is showing.

Every other screen caps its content at 720 points on iPad. Cards designed for a
phone's width become lines of text a foot wide with a status pill marooned at
the end, which is harder to read than the layout it replaced.

### A seventh rule: assignments to properties that do not exist

The batch decoders assigned `self.arpEntries` where the property is `arp` — a
name I invented rather than checked, in a file with sixty-odd stored properties
to confuse it against.

The members suite could not see it: its typed-binding rule needs a written type
annotation, and `self` has none. It now checks assignments to `self.x` against
the properties the enclosing type declares, which names the same line the
compiler does.

### Text scales with the person's setting

Every font in the app was `Font.system(size:)`, which does not scale — the same
points whether text is set to xSmall or to the largest accessibility size. On a
monitoring app you read on a phone, that meant somebody who needs larger text
got a dashboard they could not read.

All 246 call sites now use a `.scaledFont` modifier that multiplies by the
current Dynamic Type ratio, relative to `.body` throughout: the sizes were
chosen against each other, and scaling them by different curves would pull a
card apart at large sizes. Converted by rewrite rather than by hand — a missed
site leaves one unscaled label that nobody notices until somebody complains.

Three things the conversion needed beyond the fonts:

- The icon wells scale too. A 22pt well clips a symbol that has grown to 30pt.
  The decorative rails down the side of a card stay fixed: they are not text.
- Row summaries allow two lines instead of one. "Allow Cloudflare to HAP…" says
  less than two lines of it.
- The modifier lives in its own file compiled by both targets. The widget uses
  it as well, and it does not compile `Components.swift` — putting it there
  would have broken the extension build.

`Font.custom(_:size:relativeTo:)` scales natively but needs a font name, and
naming the system font by string is fragile across releases. `@ScaledMetric`
gives the ratio directly and keeps the system font.

A test fails the build if a fixed font size reappears, which is how all 246 got
there: one at a time, each looking reasonable on its own.

### A refresh is five calls instead of twenty-two

pfSense serialises XML-RPC, so every request queued behind the last and behind
whatever the webConfigurator was doing. The cost of a refresh was in the round
trips, not the work.

Three of those calls were the *same* telemetry snippet, run separately for
system status, the state table and filesystems. That was free to fix and should
have been noticed long ago.

The rest are grouped into four calls by screen: core (telemetry, firmware,
interfaces, gateways, services), clients (ARP, leases, static mappings, host
overrides, aliases), VPN, and system. The filter log stays on its own because it
takes a parameter.

Grouped rather than combined into one, because a PHP fatal cannot be caught: a
single call would mean one bad section blanking the whole dashboard. Four groups
bound that to the screens they serve, and errors are still recorded against
individual sections — "batch_core failed" would be an implementation detail
leaking onto a screen, and would leave four other cards blank with no
explanation.

The batches were generated from the existing snippet bodies rather than
retyped, so there is no transcription risk — but there are now two copies of
each body, and a test asserts each batch contains its parts verbatim. Without
it, fixing a field name in one and not the other would leave a screen quietly
reading the wrong key. The individual snippets stay because that is what
`check-snippets.sh` exercises when debugging one section against a live
firewall.

Row unwrapping is now shared between the batched and solo paths, so the `data`
envelope, bare lists and keyed-object folding behave identically either way.

### The read-only check failed about once in twelve runs

It forked two greps for every function name it found — well over a hundred
processes — and under load an occasional fork failed, which reads as "not on
the allowlist". It named a different innocent function each time, which is what
made it look like noise.

I dismissed it as flaky three times this session before looking. That is the
wrong instinct: an intermittent check is worse than one that always fails,
because it trains you to ignore the one thing standing between this app and a
snippet that writes to a firewall.

Now a single pass. Zero failures in thirty runs, and it still catches a planted
`system_reboot_now`.

### Interfaces report whether they have byte counters at all

The throughput chart has never charted anything, and said "collecting samples"
throughout — a message that cannot distinguish "this started a moment ago" from
"no sample will ever arrive". The likeliest cause is `get_interface_info()` not
returning the counters the app reads.

The snippet now reports explicitly whether they are present, and the chart says
which situation it is in rather than promising a sample that may never come.

### Icon switching waits for the app to be active

A fixed 0.6s retry was a guess at a delay, and it kept failing. `EAGAIN` from
`setAlternateIconName` means iOS declined at that moment, and the moment that
matters is the scene's state: it refuses unless the app is `.foregroundActive`,
which it is not during a navigation push, a sheet presentation, or while a
screen is still animating in.

So it now waits for the app to actually be active rather than guessing how long
that takes, and retries up to eight times a quarter-second apart. If it still
refuses, the message says how many attempts were made and what the build
registered — the difference between "try again" and "this build is wrong" is
not something to leave a person guessing at.

The registered names are shown on any failure now. Previously they appeared
only when icons were missing, which meant their absence was itself a clue and
nobody could read it.

### Two different icon failures, told apart

`setAlternateIconName` returns the same unhelpful "resource temporarily
unavailable" — POSIX `EAGAIN` — for a transient refusal and reports a generic
error when the icon simply is not in the build. Those need different responses
and the screen said neither.

It now reads `CFBundleIcons` from the running bundle first. If the requested
icon is not registered there, it says which ones are, because no amount of
tapping fixes a packaging problem. If it is registered, the call is deferred to
the next runloop turn — being inside a SwiftUI update is one of the states iOS
declines from — and retried once after a moment, which is usually enough for a
genuine EAGAIN.

The picker shows progress while a change is settling, and says how many
alternates the build registered when that number is short.

### The icons were packaged wrong

"The file doesn't exist" — `setAlternateIconName` could not find them, and the
previews were blank for the same reason. Loose files at the bundle root are the
old way of doing alternate icons and depend on the build system putting them in
exactly the right place, which it did not.

They are asset catalog icon sets now, with
`ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES` listing them. Xcode generates
the plist entries and places the images itself, which is what it has done since
Xcode 14. The hand-written `CFBundleIcons` block came out, since it would fight
the generated one. Previews are ordinary image sets, because an app icon set
cannot be loaded as a normal image.

### The app has an icon, and six of them

A watchtower, in coral, ocean, mint, amber, lavender and silver. Coral is the
primary one in the asset catalog — the app had no catalog at all until now —
and the other five are loose bundle files, which is what `setAlternateIconName`
resolves. Settings has a picker.

Worth noting the filenames matter: `Icon-ocean@2x.png` at the bundle root, not
the size-suffixed names an asset catalog uses. I generated the wrong ones first
and they would have failed silently at runtime.

The website header uses the icon too, switching to whichever of the six is
nearest the chosen accent.

### A firewall rule opens, rather than explaining itself in the list

Ninety-eight rules at five lines each is a list nobody scrolls. Rows are two
lines now — what the rule does, and its description — and everything else moved
to a detail screen: both sides with ports, the interface, IP version, whether
it logs, and the tracker, which is how you find the rule again in the
webConfigurator. Aliases show their name *and* contents there, where there is
room for both.

NAT the same.

### The label field is gone from first-run setup

One more thing to fill in before a connection could be tested, for a name that
matters only once there is a second firewall. Still editable when editing one;
the list falls back to the hostname when it is empty.

### Saving a firewall left you on the edit screen

It saved and reported the connection test inline, so nothing indicated the job
was done. Success dismisses now; failure stays open, because the error is the
reason to still be there.

### It offers to pin the certificate

pfSense ships a self-signed certificate, so the first connection is necessarily
made with untrusted TLS allowed — and that is the one moment the app knows the
certificate is the right one, because the person is looking at the firewall
they just typed in. It now offers to pin it there. Asked rather than done
silently: pinning breaks the connection when the certificate is renewed, and
that should not be a surprise.

### The temperature threshold is yours to set

80.5 °C on a chipset does not trigger the built-in 95 °C warning, which is the
right default and the wrong answer for somebody who knows their board and wants
to hear about it. Settings has a slider; the critical point follows ten degrees
above, so lowering the warning does not lose the difference between warm and
serious.

### UPnP removed

The screen could say whether the service was on and nothing else, because the
port maps live in a pf anchor that only `pfctl` can read. A page that exists to
tell you it cannot tell you anything is not worth a row in the menu. Removed
entirely — snippet, model, view and tests.

The finding stands and is worth keeping in mind: three separate things on this
firewall (blocked hosts, live HAProxy status, UPnP maps) are behind a shell, and
that is the real boundary of what this transport can see.

### Superseded: the UPnP screen

Two guesses were spent finding this out. A lease file that does not exist, then
an accessor function that does not either — the probe reported only
`upnp_running` and `upnp_action`, and no lease file at all.

miniupnpd keeps its port maps in a pf anchor. pfSense's own status page builds
its table by running `pfctl -a miniupnpd -sn` and parsing the output, and
shelling out is exactly what the snippet rules forbid, for the reason that
`exec` cannot be audited as read-only.

So the screen shows what is knowable — installed, enabled, running, which
interface — and says plainly where the mappings are instead of showing an empty
list. That distinction is the point: "no ports are open" and "this app cannot
see which ports are open" render identically, and the first is far more
comforting than it deserves to be. A running UPnP daemon is a standing offer to
open ports on request, so it is coloured as a warning even though the resulting
ports cannot be listed.

The call to `upnp_get_active_mappings` stays, so a package version that gains
one starts working with no other change.

### The old UPnP screen note

The first version read `/var/etc/miniupnpd.leases` directly, which came back
empty against a firewall whose webConfigurator was showing a live mapping. The
lease file is not where pfSense keeps them.

It now calls `upnp_get_active_mappings()` from the package's own include, which
is what the status page uses, and reports which functions and files it found
when that is not there — so a wrong guess is corrected in one round trip
instead of by trying paths one at a time. The model reads both plausible field
namings, since the accessor is undocumented and one guess has already been
wrong.

The expiry column is gone: the lease file had a timestamp and the accessor does
not, and showing "no expiry" for everything would be inventing a fact.

### The old UPnP screen note

Ports opened because a device asked, rather than because somebody wrote a rule
— the one place where what is open and what is in the rules can differ. Shows
the route, what the firewall knows the device as, and how long the lease has
left. Installed-but-off is said plainly rather than shown as an empty list.

### The publish gate caught a leak, and was missing more

The secrets check stopped a publish over an internal hostname in test fixtures
and doc comments — written from live data while debugging, which is exactly how
this happens.

Looking at what else was there found worse: the real WAN address in four test
fixtures, in the changelog, and on the public website's mockup. The check had
missed all of them for two reasons.

- It only matched addresses inside a URL. A bare address in a fixture is the
  same leak without the scheme.
- It scanned `Sources`, `Resources`, `public-web` and `README.md` — not
  `Tests`, not `CHANGELOG.md`. Fixtures are written from live data and the
  changelog quotes what was on screen when something broke; both are as public
  as the code.

Both widened, with the RFC 5737 documentation ranges allowed so examples stay
possible. Everything now uses `203.0.113.x` and `example.se`. Verified by
putting a real address back and watching the check fail.

### Port forwards have a source, and it was being dropped

A sweep against the live firewall showed `source` on every port forward row.
The model never read it, and a comment I had written asserted it did not
exist — I inferred that from the model rather than from the firewall.

It is parsed now and shown when it narrows something. A forward restricted to
one source is exactly the kind of rule worth seeing marked as restricted;
"From any" on all five would be a row that never varies, so it is hidden when
it says nothing.

### Acknowledging one gateway silenced another

The acknowledgement signature stripped every digit from a title, so
"WAN_DHCP is down" and "WAN2_DHCP is down" became the same condition — and
acknowledging one would have hidden the other. The same held for openvpn1 and
openvpn2.

Only whole numeric words are dropped now: a digit inside an identifier is part
of its name, a word that is only a number is a measurement. Checked against
every title the alert builder can emit, which turned up one more — "CARP VHID 1
backup" identifies a virtual IP by a bare number, so alerts can now carry an
explicit key for the cases where the title cannot distinguish them.

### A failing test crashed the whole run

`ServerMigrationTests` force-unwrapped a value that a genuine failure would
leave nil, so instead of a failed assertion the process died, taking every test
after it and producing a macOS crash report. It uses `XCTUnwrap` now.

Underneath it was a missed edit: two `ServerRegistry()` constructions were
nested deeper than the ones I replaced, so those tests built a registry against
the shared defaults while asserting against the isolated suite.

### Rules read as fields, not as one line

`198.51.100.0/24, 198.51.100.0/22, 203.0.113.0/24 +19 → wanip:80, 443` is a
wall: it wraps mid-address, and which side is the source depends on spotting an
arrow in the middle. Rules and NAT now use labelled rows — From, Src port, To,
Port — with a fixed label column so addresses line up down the card, which is
what makes them comparable between rules.

### Address and port were welded together

`FilterAddress` joined them into `host:port` and every consumer split on ":" to
get either back. That cannot work for IPv6: `fe80::1:443` has no unambiguous
split, and every rule with a v6 address was being rendered through exactly
that. They are separate fields now and resolved independently, so the joining
never happens.

### Rules and NAT show addresses, not alias names

`alias_host_pms001:alias_port_plex` now reads `172.16.1.43:32400`. The name is
dropped rather than shown alongside: a rule you are reading to find out what it
permits is answered by the addresses, and carrying both doubled the height of
every row for something you would look up elsewhere anyway.

Nested aliases resolve, duplicates are dropped, and there is a depth limit
because pfSense does not forbid a cycle. Long lists cap at three with a count —
`alias_url_cloudflare` holds twenty-two networks.

Aliases have their own screen under More, since looking one up is a different
task from reading a rule. Searching it matches nested members too, so looking
for a host finds every alias that ends up containing it.

### Previously: rules and NAT showed what their aliases contain

`alias_host_nas_hyperbackup → alias_port_hyper_backup` is precise and says
nothing about what the rule permits without opening two other pages. The alias
name stays — it is what you would search a rule for — and its members are shown
underneath.

Nested aliases are flattened, because that one holds four other aliases.
Duplicates are dropped, since two nested aliases often share a host and listing
it twice reads as a mistake in the rule. There is a depth limit: pfSense does
not forbid a cycle, and a stack overflow is a poor way to render a rule. Long
lists are capped with an honest count.

### The stored alert preferences read inverted

Flipping what the switches meant left anyone who had touched that screen with a
stored set interpreted the opposite way — every kind silenced when they had
silenced nothing. Changing the meaning of a stored value without changing where
it is stored is a migration, and I did not do one. The preference now lives
under a new key and the old one is removed on launch, so everybody starts from
the default: all kinds shown.

### Alert switches turn things on, not off

Under "silence individual kinds" a switch was on when the kind was silenced, so
a default of everything enabled looked like a screen full of off switches —
which reads as nothing working. The master switch had the same problem in
reverse: "Silence all alerts", off by default, is a double negative to parse
before you can tell whether alerts are on.

Now "Show alerts" and "Kinds to show", on by default, off to stop receiving
them. Same behaviour, stated the way people expect to read it.

### VPN peers moved behind a tap

Four instances each listing their connections made the tab a wall of addresses
and byte counts, and the question it is usually opened to answer — is
everything up, how many are on — was buried inside it. Each row now says "2
clients connected" or "1 of 1 connected", and the peers are on a detail screen.

WireGuard counts *connected* peers rather than configured ones: a tunnel with
three peers and none connected is a different situation from three all up, and
a bare count cannot tell them apart.

### One refresh indicator, not two

Every screen is inside a `refreshable` scroll view that draws its own spinner.
The floating one above the tab content was a second copy of the same
information, sitting over the title while scrolling.

### The website shows the app

Three more renderings — Clients, the live interface graph, and VPN — beside the
overview that was already there. Every colour in them is a theme token, so the
picker at the top of the page recolours them along with everything else.

### The exhaustiveness rule was checking almost nothing

`CertificatesView.Filter` lost its `all` case and kept a `case .all:` in the
switch, which is exactly what the members suite exists to catch. It passed.

Three faults stacked on top of each other, each hiding the next:

- The enum had to be written `: String, CaseIterable {` exactly, so one that
  also conformed to `Identifiable` was invisible. Now any CaseIterable enum
  matches, with its body found by brace matching rather than by stopping at the
  first `}` — which lands inside a computed property.
- Cases on one line with raw values parsed as nothing, because the pattern
  stripping `= "..."` ran on text where strings had already been blanked to
  spaces. Everything after `=` is dropped by position now.
- The inner loop reused the variable holding the enum's name, so the one
  message that did get produced said `expiring.certificates` instead of
  `Filter.certificates`.

Of the fourteen CaseIterable enums in the app, the rule previously saw two.

### The website, shorter

- The "What it can't do" section is gone. A list of absences is a strange thing
  to put in front of someone deciding whether to install something.
- The privilege callout is gone; the one sentence that mattered — it is
  administrator-equivalent, use a dedicated account — is in the step it
  qualifies, where somebody following the steps will actually read it.
- Feature cards are one line each. They had grown into paragraphs explaining
  the reasoning behind each feature, which belongs in the changelog.
- "What it reads" was a table of endpoint paths, which told a reader nothing
  about whether the app does what they need. It is now "What each screen shows",
  one short entry per screen.

The CSS for the removed sections went with them rather than being left to rot.

### The website describes the app as it is now

Setup no longer tells people to install a package that is not used. It is an
account with the HA node sync privilege, Max Processes raised, and a pinned
certificate — with a note explaining that the privilege is
administrator-equivalent and why a dedicated account is worth the minute it
takes.

Cut: "Watch the wall, touch nothing", the etymology of the name, and the
section arguing that the app never writes. The first was doing a job the
subtitle already does, the second was interesting to nobody deciding whether to
install it, and the third made a promise the current transport supports less
strongly than the old one did — better made once, plainly, next to the privilege
it qualifies.

Added: the live per-interface graph, HAProxy backend monitoring, ACME renewal
state, per-filesystem usage, dynamic DNS staleness, interfaces named the way the
administrator named them, and alert silencing. The "what it reads" table now
describes what each screen shows rather than listing endpoint paths, which is
what somebody deciding whether to install it actually wants to know.

Two honest additions to the limits: no historical graphs, and no live HAProxy
server status — with the reason, since "the socket that reports status also
accepts commands that disable servers" is a better answer than silence.

### A test that read the real firewall's settings

`testEmptyStateProducesNoServers` asserted the registry starts clean when
nothing is stored, and failed with a profile for a live firewall in it.

In a host-app test bundle `UserDefaults.standard` *is* the app's own store on
that simulator, and the tests wrote and read it directly — so the test passed on
a fresh simulator and failed on one where somebody had configured a firewall. It
was reading real settings. A test whose result depends on the state of the
machine running it is worse than no test, because a failure looks like the app
broke.

`ServerRegistry` now takes its store as an argument, defaulting to `.standard`,
and each test gets a fresh suite that is torn down after it. A sixth rule in the
members suite rejects any test touching `UserDefaults.standard`.

### A fifth rule for the members suite

`@ViewBuilder` written above a doc comment and again below it — the duplicate
hidden by the comment between them. Swift rejects it, and the suite now catches
it first. Attribute lines that also declare something end the run, so two
consecutive `@Published` properties are not mistaken for a duplicate; that
correction came from four false positives on the first attempt.

### Package and firmware updates now alert

The firmware alert already worked — `get_system_pkg_version()` gives the
comparison and the Overview raises it.

Packages did not, and the reason was the design: checking was manual, so an
alert could only appear after somebody pressed a button, which is not an alert.
The check now runs in the background at most every six hours, unawaited so the
rest of the dashboard does not wait behind it. Package releases happen weekly
at most, so this is about being told within a working day rather than within a
minute, at the cost of one repository round trip per six hours.

The time of the last check is persisted and shown, because "no updates" from a
week ago is a different claim from "no updates" from this morning.

Also: package descriptions arrive with `<br />` and hard line breaks —
pfBlockerNG's runs to six lines — which rendered as literal markup in a
one-line summary. Stripped.

### Packages can be checked against the repository

A Check button on the System screen compares installed versions against the
package repository, using `get_pkg_info()`.

That function runs pkg internally, which looks like it should be forbidden and
is not. The snippet rules stop *this app* from sending `exec`, `mwexec` or a
shell; they do not stop pfSense using one inside its own functions. The same
reasoning already covered `wg_get_status()`, which shells out to `wg show`.
What the rules protect is that every line of PHP this app sends is reviewable
and cannot write, and that holds here. Both cases are now named in SECURITY.md
rather than left as an inconsistency somebody would have to notice.

It is a button rather than part of the refresh because the call reaches the
repository over the network and takes seconds. On a thirty-second timer that
would have the firewall fetching a package index all day to answer a question
that changes weekly. The transport gained a per-call timeout for it — two
minutes, since timing out at thirty seconds would report a failure for
something that had not failed.

Results are merged rather than replacing the list, so a package the repository
has dropped does not vanish from what is installed.

### Seven from a session on the device

- **Packages are read again.** They were dropped in the conversion as
  unreachable; they are in `$config` after all. Live version comparison still
  is not — that needs `get_pkg_info()`, which shells out to pkg — so the screen
  shows what is installed and never claims an update is available rather than
  guessing none is.
- **ACME certificates are no longer listed twice.** The certificates snippet
  flags the ones ACME manages, and the general list leaves them to their own
  screen, where the renewal state that matters for them is also shown.
- **Renamed to System Certificates and ACME Certificates**, which is what each
  actually contains.
- **Onboarding still described the REST API.** An earlier edit matched text
  that had already changed and silently did nothing — the same failure as the
  three build breaks, this time in a string nobody compiles.
- **Overview interfaces open the live graph**, as on the Network tab.
- **Interfaces can be pinned to the Overview.** Fifteen is too many for a
  dashboard and one is too few; which three or four matter depends on what you
  run. Starred on the Network card, and the Overview falls back to the uplink
  when nothing is pinned. Note that `swipeActions` was written first and would
  have done nothing — it only works inside a List, and that screen is a
  LazyVStack.
- **The temperature alert was unactionable.** 82 °C is alarming for a CPU die
  and unremarkable for a chipset, and this firewall's only sensor is the PCH —
  so a healthy box raised a permanent warning, which is how an alert list stops
  being read. The snippet now reports which sysctl answered, the label follows
  it, and the thresholds do too: 95/105 for a chipset against 80/95 for a CPU.
- **Alerts can be silenced where you see them.** Long press an alert to quiet
  its kind or all of them. The switches in Settings were real but nobody goes
  to Settings looking for a way to stop something they are looking at.

### The test suite caught up with the app

29 failures, and all but one were tests asserting behaviour that had since been
deliberately changed — the cost of moving quickly on rules like naming priority
without revisiting what encoded the old ones.

- Alias-as-title tests: aliases no longer title clients, so these now assert
  the address is shown and the alias is carried for the detail sheet.
- Static-mapping description tests: the announced hostname and DNS overrides
  both outrank it now, which was a deliberate reversal.
- Throughput tests keyed by device: the tracker keys by interface, since VLANs
  on a lagg share a device.
- A WireGuard test with a fixed handshake timestamp: it went stale the moment
  the label started depending on recency — connected when written, idle a week
  later. It now builds a recent timestamp.
- A lease test expecting `.ok` for a static mapping, which the model colours
  `.info` deliberately.

The one that was a test-design problem rather than a stale expectation: a
line-shape heuristic meant to catch a comment broken by an escape flagged every
continuation of a multi-line ternary as "stranded code" — eight false positives
on valid PHP. Replaced with a brace-and-string balance check, which is the
property that actually broke.

### Tap an interface for a live graph

The Network tab's cards open a full screen that polls that interface every two
seconds and charts both directions against a shared scale — independently
scaled directions look like symmetric traffic when they are not. Current rate,
peak, lifetime counters and errors are alongside.

Two seconds is a floor, not a placeholder. Every poll is an `exec_php` that
pfSense serialises against the webConfigurator, so a tighter loop would make
the firewall's own web UI feel slow while the screen is open. The screen says
so, and the poll stops the moment it is dismissed — the loop is driven by the
view's `.task`, which SwiftUI cancels.

Supporting changes: a counters-only snippet, since the full `interfaces` read
returns fifteen rows of addresses and MAC addresses that do not change between
samples; and a second tracker with a longer history, so a minute spent watching
one interface does not flush the half-hour every other screen draws from.

### Certificates and ACME each have a screen

Sixteen certificates at the bottom of System was a list nobody could find
anything in. Certificates is now its own screen under More, sorted by expiry
rather than by name — the only question anybody opens it to answer is which one
runs out next — with All/Expiring/CAs and a badge for anything close.

ACME is separate from it, because the two answer different questions. The
certificate store says when something expires; ACME says whether anything is
going to renew it. A Let's Encrypt certificate with 40 days left is fine if
renewal is configured and a problem if it is not, and looking at the
certificate alone cannot tell you which. Each entry is joined to the store by
name and shows both, with the worse of the two conditions colouring the card.

Two things the screen flags that nothing else does: an entry with renewal
disabled, which will expire silently; and an account key pointing at Let's
Encrypt staging, whose certificates no browser trusts — a failure that looks
like a certificate error rather than the configuration mistake it is.

### HAProxy backends

A screen under More answering the question that was asked: is backend
monitoring set up? A backend with no health check keeps sending traffic to a
server after it dies, because HAProxy only knows a server is down if something
told it to look. That is configuration, readable from `$config`, and arguably
more useful than live status — live status says a server is down now, this says
you would never find out.

The summary line counts unchecked backends, the More row badges them, and each
card shows the check type, URI and interval or says "no health check".

Verified against a 35-backend configuration: `ha_backends` and `ha_pools` are
the right keys, and `stats_accessors` came back empty — no version of the
package on 26.07 exposes a stats accessor, so live status is not reachable
without the admin socket. That is now a finding rather than an assumption.

Two things the real data corrected. Frontend bind addresses live in a list
(`a_extaddr`), not the single `extaddr` field, which holds nothing once more
than one address is possible — every frontend read as having no bind. And a
blank check interval is HAProxy's own default rather than an absence, so it now
says "default interval" instead of trailing off after the check type.

**Live per-server status is deliberately absent.** It lives in HAProxy's admin
socket, and reading it means writing `show stat` to a socket that also accepts
`disable server backend/srv1`. Nothing reading this app's source could tell
those apart, so the read-only guarantee would stop being a property and become
a promise. Parsing `haproxy_stats.php` was the other option and is worse: it is
a webConfigurator page that changes shape with every package release.

The snippet probes for a package accessor with `function_exists` and reports
what it finds without calling it. If one exists, live status can be added
without guessing at a name — and the screen says so rather than pretending the
gap is not there.

### Dynamic DNS has its own screen, and three fixes

A firewall that hosts anything has twenty or more entries, and at the bottom of
System they were a wall of near-identical cards pushing everything else off the
page. Now under More, with search, an All/Stale/Disabled filter, and a summary
line so "is anything wrong" does not require scrolling twenty cards. The More
row carries a badge when something looks stale.

Three things were wrong in the data:

- **Every entry read DISABLED** while the webConfigurator showed them all
  green. pfSense writes this flag as an empty element, which is falsy in PHP —
  presence of the key is what means enabled, and a disabled entry has no key.
- **The hostname was "@" or "www"**, because `config.xml` keeps host and domain
  apart and the webConfigurator joins them. "@" on its own names nothing.
- **"Last pushed" showed `203.0.113.9|1788038229`.** The cache file holds
  an address and a timestamp separated by a pipe. Splitting it also gives the
  real update time, where the file's modification time only says when it was
  last touched.

The watched interface is labelled too — "WAN_1", not "wan".

### Firewall rules were never fetched

The Firewall tab loads its rules, NAT and aliases on appearing rather than on
the refresh timer, because 98 rules is a large payload for a screen most people
never open — but nothing called the loader, so the tab was permanently empty.
It now loads when the screen opens. The interface chips above the list were
already there; they had no rules to filter.

### Interfaces are called what the firewall calls them

A client on `lagg0.100` is on `VLAN_100`, and a rule on `opt7` is on
`WIREGUARD1`. The device name and pfSense's internal handle are both correct
and neither is what anybody calls the interface — reading them requires a
lookup table nobody carries in their head. Clients, ARP entries, rules, port
forwards and the rule filter chips all show the configured description now,
falling back to the raw value for an interface the app has not seen.

### Aliases are no longer used as client titles

`alias_host_app003` is accurate and useless for recognising a device in a list
of ninety — it is the name a rule refers to, not the name the machine answers
to. When there is no DNS name the address is shown instead, which at least says
where the thing is. The alias stays on the detail sheet, where it is the thing
you would search a rule for.

### Alerts can be silenced

Settings → Alerts silences everything, or individual kinds: gateways, services,
system notices, certificates, updates, capacity, HA, VPN, connection. Silenced
alerts stop driving the tab badge and the Overview banner but remain on the
Alerts screen, which says how many are hidden — an alert that vanishes without
trace is indistinguishable from a condition that cleared.

### Fixed: an empty card above every log

A log file ends with a newline, so splitting it yields an empty final element.
Reversed for display, that became the first row: an empty card sitting above
every log on every tab. Blank lines are dropped.

### DNS names first, aliases on the detail sheet

Client naming now prefers what the device is actually called on the network:
a DNS host override, then the hostname it announced, then a static mapping's
description, then a firewall alias, then its address.

An alias like `alias_host_srv001` is accurate but it is filing rather than
identity — it is the name a rule refers to, not the name the machine answers
to. It is still there, in full, on the detail sheet, which now lists every name
a device has with the source of each. The title also says which source it came
from, so a surprising name can be traced without guessing.

### Charts stay hidden until they have a line

An empty frame with "↓ — ↑ —" beneath it is not a chart waiting to fill; it is
a rectangle that takes vertical space, draws the eye, and says less than the
transfer totals directly above it. VPN cards now render nothing until there are
two samples.

The interface chart keeps its "collecting samples" caption on the Network tab,
where the chart is the point of the card, and drops it on the Overview where it
sits among a dozen other things.

### The ARP table now names things the way the Clients tab does

Every row was titled "?" — the literal string the ARP table writes when reverse
DNS fails, which the Clients tab already filters. The same device was called
"?" on one screen and `alias_host_nas001` on another. Both screens now go
through one lookup.

Two smaller things in the same rows: interface names were being uppercased by
the status pill, turning `ix0` into `IX0` which reads as the letter O — an
interface name is an identifier, not a label. And "Expires 1181" is a count of
seconds; it now reads "19m".

### Temperature, and two charts that drew solid blocks

- **Temperature works on this hardware now.** `get_temp()` returns empty on a
  box whose Thermal Sensors widget is showing 83 °C, because that widget reads
  a sysctl directly and which one depends on the chipset — "PCH 0" is
  `dev.pchtherm.0` on Intel server boards, where `dev.cpu.0` does not exist.
  Three candidates are tried in turn behind `function_exists`.

- **The metric charts scaled to zero**, so memory steady at 8% was a filled
  area covering nine tenths of the frame — a solid grey block that looked like
  a broken chart. They now scale to the data, with a tenth of the span as
  headroom, and a completely flat series is centred rather than pinned to an
  edge. The state-table trend had the same fault: 10,856 against a ceiling of
  1,621,000 was a line on the floor of an empty box.

- **Every VLAN on a lagg shared one throughput series.** They report the same
  `hwif`, so the tracker differenced one VLAN's counters against another's,
  got a negative delta, and cleared the history as if the counter had reset —
  which is why the history never grew past a point. Keyed by interface now.

  "Collecting samples" also names the interface and says how many it has, so a
  series that will never fill can be told from one that started a minute ago.

### Fixed: aliases named nothing because their members never parsed

`config.xml` stores an alias's members as one space-separated string —
`"172.16.1.50 172.16.1.51 172.16.1.52"` — where the REST API returned a list.
Reading it as a list gave an empty alias under XML-RPC: every one of the 56
looked like it had no members, the Firewall tab would have shown counts of
zero, and no client took a name from one.

Per-member descriptions have the same problem with a different separator:
`config.xml` joins them with `||`.

Both forms are now accepted, so a fixture from either transport decodes.

### Fewer calls per refresh

A full refresh ran 26 snippets, one at a time, because pfSense serialises
XML-RPC — so they queue on the firewall no matter how they are issued. Four of
them were log reads of a quarter of a megabyte each, for a tab that is usually
not on screen.

The four secondary logs (system, auth, DHCP, OpenVPN) now load when the Logs
tab appears and refresh while it is visible. The filter log stays on the timer
because the Overview shows its counts.

Still worth doing and not done: most of the remaining calls are small reads of
different corners of `$config`, and could be answered by one snippet instead of
a dozen. That would cut a refresh from roughly twenty round trips to about
five.

"Collecting samples" now says how many it has. On its own the message is
indistinguishable from "this has been stuck for ten minutes" — which is the
ambiguity that made the sparklines hard to reason about.

### Blocked hosts, attempted safely

`loadTables()` still had a `do/catch` around an assignment that could not
throw — dead code from the conversion, and the warning the compiler raised.

Rather than delete the feature, it is attempted the way the WireGuard status
call was: `function_exists` first, so a firewall without an accessor returns
"not available" rather than raising an error that pfSense would keep forever.
The two candidate names are called explicitly, and if neither exists the app
says pf tables cannot be read without a shell instead of showing an empty list
that reads as "nothing is blocked".

Writing it turned up a real hole in the publish check. The first draft picked
an accessor at runtime and called it through a variable — `$found($name)` —
which defeats the allowlist entirely, since nothing reading the source can tell
what it will invoke. `readonly.sh` now rejects variable function calls, and
skips comments when scanning, because the comment explaining this rule was
itself failing it.

### Alerts stopped reporting failures that were already fixed

Notices persist on the firewall until somebody clears them, so eighty entries
from a bug fixed twenty minutes earlier still read as "a snippet is failing".
The crash log made it plain: the last PHP error was at 16:38:24 and the
screenshot was taken at 16:50 — nothing had failed for twelve minutes.

Only notices from the last fifteen minutes now count as a current failure. The
full history stays under System → Notices, where it belongs, and if there is a
pile of old ones with nothing recent the app says so and points at the bell
icon instead of claiming a fault.

Also: the metric sparklines repeated the meter directly above them, printing
"Memory 8%" under a bar reading "Memory 8%". They now show the range the
history covers and how many samples it holds, which is what a chart adds over a
current reading.

### The app no longer writes to the firewall's log because of its own bugs

A snippet that raises a PHP error leaves a permanent notice on the firewall.
With a thirty-second refresh timer that is one notice every thirty seconds —
78 accumulated in an afternoon, filling the bell icon and this app's own alert
list with the same defect.

Retrying less often was not enough. After three faults a section is now
abandoned for the rest of the session, and says so in the card it belongs to.
Pull to refresh, switch firewall or relaunch to try again: all three are a
person saying "try again", which is the only signal worth acting on.

This is the more important half of the `host_overrides` bug. The snippet was
mine to fix; writing to somebody's firewall log every thirty seconds until they
noticed was the part that should never have been possible.

### host_overrides rewritten through pfSense's own accessor

Reading `$config` by hand kept fataling on shapes that were not what they
looked like — an empty element parses to a string, a single entry parses as
itself rather than a list of one — and a fatal inside `exec_php` returns an
empty HTTP 500 with no message to read, so each attempt cost a round trip to
guess again.

Rewritten through `config_get_path()`, pfSense's own null-safe accessor, behind
a `function_exists` guard with the hand-rolled version as fallback. Every value
is coerced with `strval` and no index is nested.

`bin/check-snippets.sh --script FILE` was added for the bisection this needed,
along with four probes in `probes/`. A fatal with no message cannot be reasoned
about; it has to be cut down until it works.

### Fixed: host_overrides faulted on every refresh

An empty element in `config.xml` — `<dnsmasq></dnsmasq>` — parses to an empty
*string*, not an empty array. `$config["dnsmasq"]["hosts"]` then indexes a
string, which is a TypeError in PHP 8. Checking `is_iterable` on the inner
value was too late: reaching it had already thrown.

That is the snippet that was writing a notice on every refresh and filling the
alert badge. Every two-level read of `$config` had the same shape and all seven
are now guarded — the section is assigned to a variable and checked with
`is_array` before anything is read from it.

This is the second time this class of bug has cost a round trip, so
`readonly.sh` now rejects any snippet that indexes two levels into `$config` in
one expression. Verified by reintroducing the pattern and watching it fail.

Two diagnostic fixes came out of chasing it:

- pfSense returns XML-RPC faults with a **500** status, and both the app and
  `check-snippets.sh` were discarding the body — throwing away the firewall's
  own explanation and leaving a bare "HTTP 500". Both now read the fault out of
  it.
- The checker's message for a 500 asserted "the PHP failed to parse, not to
  run", which was a guess presented as a diagnosis. It was also wrong: this was
  a runtime TypeError.

### Fixed after the WireGuard build

- **Firewall aliases never reached the client list.** They were fetched only by
  `loadFirewallObjects()`, which runs when the Firewall tab is opened — so on a
  normal refresh the alias table was empty and no client got a name from it.
  Aliases now load on every refresh; rules and port forwards stay on demand,
  since 98 rules is a large payload for a screen most people never open.
- **The alert list filled with the app's own errors.** A failing snippet writes
  a notice every refresh, so the badge reached 50 and every entry was the same
  PHP error, burying anything real. Notices raised by this app now collapse
  into a single alert that says a snippet is failing and where to clear them.
- **Two more charts rendered before they had a line**, the same fault as the
  duplicate meters: the state-table trend showed an empty box containing
  "10 256 →", and each gateway a stray "0ms →" repeating the figure directly
  above it. Both now render nothing until there are two samples.

### WireGuard: live status, and a secret that nearly travelled

`wg_get_status()` gives everything the Status → WireGuard page shows —
handshake times, transfer counts, endpoints — and one call now replaces the two
config-reading snippets.

**It also returns the private key of every tunnel and the preshared key of
every peer.** Returning the structure whole, which is the obvious way to write
that snippet, would have put those into the app's memory, across the network on
every refresh, and into any payload `check-snippets.sh --save` wrote to disk.
Fields are copied out by name instead, and `readonly.sh` now fails if a snippet
so much as mentions one — verified by adding a private key back and watching
the check refuse it.

Peer state now distinguishes three things that were previously one: connected
(a handshake within five minutes, which is roughly WireGuard's rehandshake
interval), idle (an older handshake — a laptop that closed its lid is not a
fault), and never connected (`latest_handshake` of "0"). Tunnels report their
real `up`/`down` status and lifetime transfer.

The snippet is guarded by `file_exists`, so a firewall without the package
returns empty instead of raising a PHP error that pfSense would keep as a
permanent notice.

### Fixed: WireGuard reported no peers

Peers are a separate section of the WireGuard package's configuration, each
naming its tunnel in `tun` — not nested inside the tunnel rows, which is where
the snippet looked. So every tunnel showed "Peers 0" while the webConfigurator
showed one connected with a handshake 53 seconds earlier.

Peers now decode with their description, public key, endpoint and allowed IPs.

What is still missing is live status. Handshake times and transfer counts come
from `wg show`, not from configuration, and reaching them needs either a shell
or a package function this app has not verified exists — guessing at one would
raise a PHP error on the firewall, which is recorded as a permanent system
notice. So a peer with no handshake data now reads "configured" rather than "no
handshake": absent data must not be reported as a failing peer.

### Added

- Temperature now converts from `temp_f` when `temp_c` is null, and alerts
  above 70 °C (bad above 85). The Resources card says "no sensor loaded"
  rather than leaving a gap — the API returns null until a thermal sensor
  module is enabled under System → Advanced → Miscellaneous, and that is not
  the same as a cold firewall.
- Installed packages under System, with versions and an alert when any has an
  update pending.
- Blocked hosts under System, read from the `sshguard` and `virusprot` pf
  tables. Loaded when that screen appears rather than on the refresh timer —
  the tables payload is dominated by `bogons`, which is large, static and of no
  interest here. Retained entries are capped per table; the count stays honest.
- Three more log sources: auth (webConfigurator, SSH and API login attempts),
  DHCP, and OpenVPN. The Logs tab now offers Filter, System, Auth, DHCP and
  VPN; the pass/block filter appears only for the filter log, since the others
  carry no action.

### Known gaps

- `system/update` and `routing/gateway/groups` both return null on 26.07 with
  nothing configured, so there was no shape to build against. Left alone rather
  than guessed at.
- No Dynamic DNS. The REST API package exposes no dyndns endpoints at all —
  `/api/v2/services/` covers acme, bind, cron, dhcp_server, dns_forwarder,
  dns_resolver, freeradius, haproxy, ntp, service_watchdog, ssh and
  wake_on_lan, and nothing else. Confirmed against the OpenAPI schema on
  26.07, not assumed.

- `services/dhcp_server/static_mappings` is fetched flat. On some REST API
  versions these are per-interface children needing a `parent_id`, in which
  case the Clients list shows no static entries.
- The two `href="#"` placeholders in `public-web/index.html` still need the
  repository URL.
