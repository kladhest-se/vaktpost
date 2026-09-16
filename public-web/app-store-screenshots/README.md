# App Store screenshots

Source: real captures from the iPhone 18 Pro Max simulator, 2026-09-16.
Verified against Apple's own current spec:
https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications

## iphone-6.9-in/ — done

10 screenshots, 1320 x 2868 px, RGB (no alpha channel — Apple rejects images
with alpha/transparency, and the originals came out of the simulator as
RGBA with a fully-opaque channel, so it was stripped losslessly).

This is Apple's current 6.9" iPhone class (iPhone 18 Pro Max is explicitly
listed in it). Per Apple's own page, providing this one set is enough for
iPhone: every smaller iPhone class ("If screenshots with the accepted sizes
aren't provided, scaled screenshots for 6.9" displays are used") falls back
to scaling this set down automatically. Nothing further is required for
iPhone unless you want hand-tuned screenshots for a specific smaller class.

Numbered in the order they'd read best to a browsing App Store visitor —
the first 2-3 are what show without scrolling, so the most visually dense,
representative screens are first:

1. Overview — the main dashboard
2. Network — interfaces list
3. DNSBL — donut chart, most colorful screen in the set
4. Network — interface comparison charts
5. Clients — traffic view
6. Client investigation
7. Settings — theme/accent/app icon picker
8. Updates
9. All firewalls
10. WireGuard mobile peers

Screenshot 10 has a lot of empty space (only one peer in the lab data) —
worth a look before submitting; it may be worth swapping for something
more visually dense if a better capture becomes available. Everything else
is unchanged from the original simulator capture.

## Still needed — iPad

Vaktpost runs on iPad (the app has dedicated split-view layouts for
Network, Aliases, VPN, and Incident Timeline), and Apple's spec marks the
13" iPad class as "Required if app runs on iPad" — this is not optional
the way smaller iPhone classes are. None of the 10 screenshots in this
upload are from an iPad simulator or device, so this set does not exist
yet.

Accepted sizes, straight from Apple's page:
- 2064 x 2752 px (portrait) — current default (iPad Pro M5/M4, Air M4/M3/M2)
- 2048 x 2732 px (portrait) — also accepted (older Pro/Air generations)

Capture these the same way as the iPhone set — `make ipados-run`, or `xcrun simctl io booted screenshot` — and drop them in a new
`ipad-13-in/` folder alongside this one, following the same numbering
convention.
