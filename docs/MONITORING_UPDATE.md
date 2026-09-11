Monitoring update — 9 September 2026

This update builds on the earlier eight audit fixes.

What changed

- CPU, memory, disk, and swap history now treat values as gauges. The first reading is recorded and falling values no longer erase earlier points. Failed dashboard fetches do not manufacture new gauge samples from old values.
- Historical traffic uses a selection-aware loader. Changing time range cancels the earlier request, clears any unrelated chart, and prevents late responses from replacing the chosen range. Cached values expire after five minutes; a failed revalidation retains the selected range's last successful data and timestamp. A failed cache entry is retried rather than treated as newly fresh.
- Pull down on History or an interface detail screen to force a history reload. History now offers the same range picker as interface detail and labels the actual range being displayed.
- Dashboard sections and detail screens display their own successful-update age, loading state, and failed/stale status. Data freshness in More (also linked from Diagnostics) lists every section. Failures keep the earlier success time. Package update checks have a separate freshness record from installed package data. Incomplete grouped responses are rejected rather than marked as fresh empty data.
- All firewalls is available from the server menu, including when the selected firewall is disconnected or needs setup. It shows connection status, CPU/memory/disk usage, uptime, gateway issues, stopped services, and certificate-expiry warnings for each saved firewall. Open firewall selects it explicitly; scanning itself never changes the active dashboard.
- All-firewall checks use independent read-only connections, without interactive certificate prompts or package-repository update checks. A firewall requiring trust or credential changes can be opened explicitly. Checks run sequentially, repeat after a 60-second pause, and stop when the screen is inactive or dismissed. Pull down or use the refresh button for a new scan. Failed checks preserve and date previous readings. CPU percentages require two successful checks when the firewall supplies cumulative CPU counters.
- Removing a firewall from the management list now uses the dashboard's normal rebind path, so deletion also clears the old binding's data and requests.

Validation

- Complete app Swift source passed typechecking and testable-module generation against the iOS simulator SDK.
- All test source files passed typechecking against that module.
- 24 portable tests passed on macOS using the actual production core sources: the 12 audit regression tests plus 12 new monitoring tests. They cover gauge decreases, history range races, cache expiry, forced reloads, failed reloads, reset, freshness failures, independent fleet snapshots, stale fleet responses, CPU baselines, and removed firewalls. Network and credential writes were not used.
- Added four iOS integration tests for independent section freshness, package-check freshness, and incomplete grouped responses. These and the three earlier dashboard-binding tests were typechecked but not executed.
- Full simulator/device UI execution and live pfSense integration remain unverified. Simulator services were inaccessible in this execution environment; compiler checks do not establish runtime layout or network compatibility.

Build with the existing XcodeGen/Makefile workflow. The source archive includes assets, configuration, website files, documentation, and tests; generated projects and build caches are excluded.
