# Changelog

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

### UPnP: the mappings are not reachable, and the screen says so

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

### UPnP: the mappings are not reachable, and the screen says so

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
