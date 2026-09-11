# Client investigation update

Open Clients and select a device to investigate it.

- Identity and names include source labels, DNS overrides and direct-address firewall aliases.
- All fetched addresses associated with the device's MAC are retained, including additional DHCP and ARP addresses.
- Lease records show state, start, expiry and interface; ARP records show interface and expiry; static mappings show address and description.
- Matching firewall logs can be searched and filtered to allowed or blocked/rejected entries.
- Per-section freshness identifies missing, stale or failed data. Pull to refresh or use the refresh button to reload the six investigation sources.
- Previously fetched clients remain accessible when a refresh fails. Switching firewalls clears the selected device.

Matching uses exact numeric IP addresses, including equivalent IPv6 spellings, and source/destination endpoints from structured records or the existing filterlog parser. Similar IPv4 addresses no longer match each other. Unparseable free-text log entries are excluded. The obsolete prefix index has been removed so independently refreshed log arrays cannot leave stale row indices.

This page correlates fetched evidence, not historical device ownership. Expired leases and reused addresses may include another device's older traffic. MAC-less devices fall back to exact IP association. Alias subnet/range membership and live connection-state inspection are outside this update.

Validation: iOS app sources and all test sources checked by the Swift compiler; 30 portable regression tests passed, including six new address/identity tests. Three additional iOS model integration tests cover structured and raw log matching plus multiple addresses. Simulator UI execution and live pfSense checks were not available in this environment.
