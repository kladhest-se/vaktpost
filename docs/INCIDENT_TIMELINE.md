# Incident timeline update

Open More → Incident timeline to see events from the filter, system, authentication, DHCP and OpenVPN logs in one view.

- Events from all five sources are normalized and sorted newest first.
- The default Incidents filter shows blocked or rejected traffic, explicit failures and warnings. Attention-only and all-event views are also available.
- Source and text filters narrow the timeline without fetching again.
- Each event opens the existing structured log detail page.
- Freshness is shown for every source. A partial refresh failure preserves and displays the available events.
- Pull to refresh or use the toolbar button to reload all five sources.
- ISO 8601, Unix seconds or milliseconds, common structured dates, and raw syslog dates are supported. Syslog entries around New Year are assigned to the appropriate previous year.

Severity is a local classification intended for triage. It recognizes firewall actions and whole-word failure or warning terms, avoiding substring matches such as treating “download” as “down.” The original log entry remains the source of truth.

Validation: all iOS app sources and test sources pass Swift compiler checks. The portable suite passes 36 tests, including six incident-classification and timestamp tests. Two additional iOS model tests cover cross-source ordering and retention of entries without parseable timestamps. Simulator UI execution and live pfSense checks were not available in this environment.
