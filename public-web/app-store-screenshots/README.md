# App Store screenshots

Source: real captures from the iPhone 18 Pro Max and iPad Air 13-inch (M4)
simulators, 2026-09-16. Verified against Apple's own current spec:
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

## iphone-6.5-in/ — fallback only

The same 10 screenshots at 1284 x 2778 px, RGB, made from the 6.9" set:
scaled to 1284 wide (2790 high), then 6 px trimmed from top and bottom —
inside the status bar and home-indicator margins, so no content is lost.

Upload these only if App Store Connect insists on a 6.5" set. The 6.9" set
belongs in the "iPhone 6.9\" Display" slot; putting it in the 6.5" slot is what
produces "dimensions should be 1242 × 2688px … or 1284 × 2778px". Regenerate
this folder whenever the 6.9" set changes.

## ipad-13-in/ — done

9 screenshots, 2048 x 2732 px, RGB (alpha stripped the same way as the
iPhone set — the originals came out of the simulator as RGBA with a
fully-opaque channel, verified before stripping).

Source: real captures from the iPad Air 13-inch (M4) simulator,
2026-09-16, via `make ipados-run`. This size is Apple's "also accepted
(older Pro/Air generations)" option rather than the "current default"
2064 x 2752 — both are valid within the same required 13" class; which
one a capture produces depends on the specific Pro/Air model simulated,
not on anything wrong with the capture. An earlier attempt at this set
was taken against an "iPad (A16)" simulator, which is an 11"-class
device despite being an iPad — at the time, `ipados-run` picked
whichever iPad happened to be newest without regard to class, and only
iPad Pro and iPad Air ever ship as 13" hardware. That gap is now fixed
in the Makefile; this set was captured after the fix, against whatever
Pro/Air simulator that narrower selection found. The earlier attempt's
screenshots were discarded rather than uploaded here; Apple's cascading
only fills smaller classes in from a larger set that was provided, not
the other way, so 11" screenshots would not have satisfied this required
slot no matter how they were labeled.

Same visual-density ordering as the iPhone set:

1. Overview
2. Network — interface detail with throughput and history charts
3. Clients — traffic view
4. Client investigation
5. Firewall — NAT rule detail, with the Apply Changes banner visible
6. VPN — OpenVPN
7. Aliases
8. Incident timeline
9. Apply firewall changes — the staged-changes review screen

Two things worth a look before submitting, neither fixed here:

- Screenshots 5-8 (and to a lesser extent 9) have a lot of empty space
  below the content — a function of how tall this size is (2732px)
  combined with how little the lab data populates each of these screens
  (one rule, two aliases, one incident). Not wrong, just sparse; worth
  recapturing against richer lab data if a denser look is wanted.
- Screenshot 9 lists a change named "Add rule dsffd" — reads like
  incidental test input rather than a deliberate demo value, unlike the
  named rules and aliases everywhere else in this set. Worth a recapture
  of just that one screen if it's noticeable at the size Apple displays
  these at.
