Audit fixes — 9 September 2026

This source package addresses the eight findings from the project audit.

1. Removed the two-second certificate decision timeout. Prompt actions and cancellation now resolve through a once-only callback. Failed presentation cancels explicitly.
2. Moved certificate UI construction, presentation, and dismissal to the main actor. Request cancellation dismisses only the prompt belonging to that request.
3. Persisted accepted certificate pins in ServerRegistry before accepting the connection. Obsolete decisions cannot overwrite an edited endpoint or a newer server binding. System-trusted certificates use normal validation.
4. Reset RRD cache/history, state-table history, live interface history, and server-specific loading/result state when rebinding.
5. Gave each server binding its own transport session and generation. Old sessions are invalidated. Loaders check their generation before requests and before publishing responses or errors; stale cleanup cannot clear a new request's loading flag.
6. Replaced the request queue with a queue that reserves each position before suspension. Cancellation propagates to active work and cancelled queued operations cannot release successors ahead of earlier work.
7. Validate passwords before storage and update existing keychain items without deleting them. Insert only when absent, and report failed updates instead of treating a duplicate insertion as success.
8. Preserve password whitespace in both the firewall editor and onboarding flow.

Also repaired an existing ClientSearchTests helper that referenced a removed NetworkClient initializer; it now uses the production merge API.

Validation performed

- The app's complete Swift source compiled to a testable Swift module against the iOS simulator SDK, with no diagnostics.
- All test source files passed compiler typechecking against that module.
- Twelve new AuditCoreTests executed successfully on macOS using the actual queue, once-only callback, registry, and credential-saving source files in an isolated temporary Swift package. No real keychain records were changed: the credential tests inject storage callbacks, and registry tests use isolated preferences suites.
- Three additional DashboardBindingTests cover history reset and rejection of delayed success/error responses after rebinding. These were typechecked but not executed here.
- Full iOS build, simulator execution, certificate UI interaction, and live pfSense integration remain unverified because simulator services were inaccessible in the execution environment. Compiler checks are not a substitute for those runtime checks.

The original build workflow is retained: generate the Xcode project with XcodeGen (or use make build/make test). Generated Xcode projects, compiled products, temporary test packages, caches, and logs are excluded from this archive. Project source, assets, configuration, documentation, website files, and tests are included.
