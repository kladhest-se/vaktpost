# Offline MAC vendor lookup

Client investigation pages now look up a device manufacturer entirely on the iPhone.

- The bundled index contains 58,447 assignments from IEEE's MA-L, MA-M, MA-S and legacy IAB public listings.
- Only the registered prefix, assignment type and organization name are stored. The generated binary is 1,606,187 bytes.
- Lookup uses the longest registered prefix, so newer 28-bit and 36-bit assignments take precedence over a broader 24-bit assignment.
- Locally administered and randomized addresses are labeled before lookup because their prefixes do not reliably identify a manufacturer. Multicast addresses are also excluded.
- No MAC address leaves the device, no API key is required, and there is no rate limit.
- `make oui` downloads fresh CSV files from IEEE and regenerates the resource and provenance manifest.

The source URLs, row counts, download sizes and SHA-256 values for this build are recorded in `Resources/OUI/README.md`.

Validation: the app source passes an iOS Swift compiler check. The portable unit suite includes binary-format, longest-prefix, private-address and corrupt-data coverage. Simulator UI execution was not available in this environment.
