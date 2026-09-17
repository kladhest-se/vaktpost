# App Store submission

What App Store Connect needs for Vaktpost, and where each answer comes from.
Values marked **(fill in)** depend on where the website is hosted.

## What the project already provides

| Requirement | Where |
| --- | --- |
| Version and build number | `MARKETING_VERSION` in `Config/iOS.xcconfig`; the build number comes from `build.number` via `make archive` |
| Privacy manifest | `Resources/PrivacyInfo.xcprivacy` — no tracking, no collected data, UserDefaults reason `CA92.1` |
| Export compliance | `ITSAppUsesNonExemptEncryption = NO` in `Info.plist` (only Apple's own encryption) |
| Usage descriptions | Face ID and local network, in `Info.plist` |
| App icon | 1024 × 1024, no transparency, in `Resources/Assets.xcassets` |
| Screenshots | `public-web/app-store-screenshots/` — 6.9-inch iPhone and 13-inch iPad |
| Mac availability | Designed for iPad, enabled in `Config/iOS.xcconfig` |
| Licence compatibility | [APP_STORE_EXCEPTION.md](APP_STORE_EXCEPTION.md) |

## App information

| Field | Value |
| --- | --- |
| Name | Vaktpost |
| Subtitle | pfSense monitoring and admin (30 characters max) |
| Bundle ID | `se.kladhest.vaktpost` |
| SKU | `vaktpost` |
| Primary category | **Utilities** |
| Secondary category | Developer Tools (optional) |
| Content rights | Contains no third-party content |
| Age rating | Answer "None" throughout; the result is 4+ |
| Price | Free |

The category cannot be set from the Xcode project. For iOS it exists only in
App Store Connect. `LSApplicationCategoryType` in `Info.plist` is read by macOS
for the Mac build and does not change the store listing.

## URLs

| Field | Value |
| --- | --- |
| Privacy policy URL | `https://<website>/privacy.php` **(fill in)** |
| Support URL | `https://github.com/kladhest-se/vaktpost/issues` |
| Marketing URL | `https://<website>/` **(fill in)** |

## App Privacy

Choose **Data Not Collected**. This matches the privacy manifest: nothing is
sent to the developer or any third party by the app. The speed test is run by
the user's firewall, not the device, and is described in the privacy policy.

## Review information

App Review cannot reach a real firewall, so point them at the website's
synthetic one.

- **Sign-in required:** yes
- **Username:** `review`
- **Password:** the lab password (`VAKTPOST_DEMO_PASSWORD` on the host,
  `vaktpost-demo` by default)
- **Notes:**

  > Vaktpost is a client for pfSense firewalls. For review, add a firewall
  > with the address `https://<website>` **(fill in)**, username `review` and
  > the password above. This is a synthetic test endpoint on the project's own
  > website; it returns sample data and never connects to a real firewall.
  >
  > If asked, allow local network access and pin the certificate.
  > The app starts in monitor-only mode. To try rule editing, open the
  > firewall's settings, tap "Enable administrative actions", confirm, and
  > tap Save. All changes stay in the test endpoint and reset after
  > 20 minutes.
  >
  > The app needs a pfSense account with the "HA node sync" privilege, which
  > is how pfSense's own XML-RPC service is accessed. No account is created
  > with the developer, and the app collects no data.

Before submitting, add that lab as a firewall on a clean device, go through the
steps in the note, and confirm the review profile loads every tab.

## Mac

Under **Pricing and Availability**, leave **Make this app available on Mac
computers with Apple silicon** enabled. Run `make mac-run` first and check the
ping and traceroute tools, which have not yet been tried on macOS.

## Each release

1. Set `MARKETING_VERSION`, `$releaseVersion` in `public-web/index.php`, and
   the top heading of `CHANGELOG.md` to the same version.
2. Replace `Unreleased` in that heading with the date.
3. `make archive TEAM_ID=…`, then upload from the Xcode Organizer.
4. Use the changelog section as the "What's New" text, shortened to the
   points users will notice.
