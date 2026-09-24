<?php
declare(strict_types=1);

// The release this page describes, and the badge's fallback when GitHub has no
// version tag yet or cannot be reached.
$releaseVersion = '1.0.0';
require __DIR__ . '/lib/LatestRelease.php';
$latestVersion = LatestRelease::version($releaseVersion);
$demoPassword = getenv('VAKTPOST_DEMO_PASSWORD') ?: 'vaktpost-demo';
$labOrigin = (!empty($_SERVER['HTTPS']) && $_SERVER['HTTPS'] !== 'off' ? 'https://' : 'http://')
    . ($_SERVER['HTTP_HOST'] ?? 'this site');
?>
<!doctype html>
<html lang="en" data-flavor="macchiato" data-accent="mauve">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Vaktpost — pfSense monitoring and administration for iOS</title>
<meta name="description" content="Vaktpost is an open-source iOS app for monitoring a pfSense firewall and performing a constrained set of confirmed administrative actions.">
<meta name="color-scheme" content="dark">
<link rel="icon" href="favicon.svg" type="image/svg+xml">
<link rel="icon" type="image/png" href="app-icons/lavender.png">
<link rel="apple-touch-icon" href="app-icons/lavender.png">
<link rel="stylesheet" href="styles.css">
<meta property="og:title" content="Vaktpost">
<meta property="og:description" content="An iOS app for monitoring and administering a pfSense firewall. Open source, Catppuccin-themed.">
<meta property="og:type" content="website">
</head>
<body>

<header class="bar">
  <div class="wrap bar__inner">
    <a class="mark" href="#top">
      <img class="mark__icon" src="app-icons/lavender.png" alt="" width="26" height="26">
      Vaktpost
    </a>
    <nav class="site-nav" aria-label="Primary">
      <a href="#top" aria-current="page">App</a>
      <a href="#features">Features</a>
      <a href="lab.php">XMLAPI Lab</a>
      <a href="privacy.php">Privacy</a>
      <a href="https://github.com/kladhest-se/vaktpost">GitHub</a>
    </nav>
  </div>
</header>

<main id="top">

<section class="hero">
  <div class="wrap hero__grid">
    <div>
      <h1>Your firewall,<br>on your phone.</h1>
      <p class="hero__sub">Vaktpost is an open-source iOS companion for pfSense CE and pfSense Plus — for checking in and making careful changes from your phone, not for replacing the web interface.</p>
      <div class="actions">
        <a class="btn btn--solid" href="#setup">Set it up</a>
        <a class="btn btn--ghost" href="#features">See the features</a>
        <a class="btn btn--ghost" href="https://github.com/kladhest-se/vaktpost">View on GitHub</a>
      </div>
      <a class="store-badge" href="#">Coming to the App Store — iPhone &amp; iPad</a>
      <p class="status-line">
        <a class="version-badge" href="https://github.com/kladhest-se/vaktpost/tags" aria-label="Latest version <?= htmlspecialchars($latestVersion, ENT_QUOTES, 'UTF-8') ?>"><span>latest</span><b>v<?= htmlspecialchars($latestVersion, ENT_QUOTES, 'UTF-8') ?></b></a>
        <span class="dot" aria-hidden="true"></span>
        <span>iOS and iPadOS 17+</span>
        <span class="dot" aria-hidden="true"></span>
        <span><b>Monitor-only by default</b> — nothing is installed on pfSense</span>
      </p>
    </div>

    <div class="device">
      <img class="device__shot" src="screenshots/overview.png"
           alt="The Vaktpost Overview screen: a status summary, system resource meters, and a gateway list.">
    </div>
  </div>
</section>

<section class="section--sunken" id="features">
  <div class="wrap">
    <h2>What it does</h2>
    <p class="lede">Broad visibility, a small administration surface, and no unattended changes. Tap any screen to see it full size.</p>

    <div class="features">
      <figure class="feature">
        <button type="button" class="feature__shot">
          <img class="device__shot" src="screenshots/thumbs/overview.png" data-full="screenshots/overview.png"
               loading="lazy" decoding="async" width="460" alt="Overview: Health, resource meters, gateways, services and alerts on one screen. The blocked, rejected and passed counts open the log they count.">
        </button>
        <figcaption>
          <h3>Overview</h3>
          <p>Health, resource meters, gateways, services and alerts on one screen. The blocked, rejected and passed counts open the log they count.</p>
        </figcaption>
      </figure>
      <figure class="feature">
        <button type="button" class="feature__shot">
          <img class="device__shot" src="screenshots/thumbs/network-interfaces.png" data-full="screenshots/network-interfaces.png"
               loading="lazy" decoding="async" width="460" alt="Interfaces: Address, media, link state and live throughput per interface. Tap one for its history, error counters and the devices behind it.">
        </button>
        <figcaption>
          <h3>Interfaces</h3>
          <p>Address, media, link state and live throughput per interface. Tap one for its history, error counters and the devices behind it.</p>
        </figcaption>
      </figure>
      <figure class="feature">
        <button type="button" class="feature__shot">
          <img class="device__shot" src="screenshots/thumbs/clients-traffic.png" data-full="screenshots/clients-traffic.png"
               loading="lazy" decoding="async" width="460" alt="Clients: DHCP leases, ARP and static mappings merged into one searchable list, with vendor names from an offline registry and live bandwidth per device.">
        </button>
        <figcaption>
          <h3>Clients</h3>
          <p>DHCP leases, ARP and static mappings merged into one searchable list, with vendor names from an offline registry and live bandwidth per device.</p>
        </figcaption>
      </figure>
      <figure class="feature">
        <button type="button" class="feature__shot">
          <img class="device__shot" src="screenshots/thumbs/client-investigation.png" data-full="screenshots/client-investigation.png"
               loading="lazy" decoding="async" width="460" alt="Investigation: Everything the firewall knows about one device, gathered from every table it keeps. Each matching log line opens the entry, and the entry opens the rule that decided it.">
        </button>
        <figcaption>
          <h3>Investigation</h3>
          <p>Everything the firewall knows about one device, gathered from every table it keeps. Each matching log line opens the entry, and the entry opens the rule that decided it.</p>
        </figcaption>
      </figure>
      <figure class="feature">
        <button type="button" class="feature__shot">
          <img class="device__shot" src="screenshots/thumbs/dnsbl.png" data-full="screenshots/dnsbl.png"
               loading="lazy" decoding="async" width="460" alt="pfBlockerNG: How much DNSBL is blocking, which feed is doing it and when. The donut is every feed by share; the list beside it is the same data in order, because a colour is not a number.">
        </button>
        <figcaption>
          <h3>pfBlockerNG</h3>
          <p>How much DNSBL is blocking, which feed is doing it and when. The donut is every feed by share; the list beside it is the same data in order, because a colour is not a number.</p>
        </figcaption>
      </figure>
      <figure class="feature">
        <button type="button" class="feature__shot">
          <img class="device__shot" src="screenshots/thumbs/wireguard-peers.png" data-full="screenshots/wireguard-peers.png"
               loading="lazy" decoding="async" width="460" alt="VPN: OpenVPN, WireGuard and IPsec with their tunnels and connected peers, including last handshake and transfer.">
        </button>
        <figcaption>
          <h3>VPN</h3>
          <p>OpenVPN, WireGuard and IPsec with their tunnels and connected peers, including last handshake and transfer.</p>
        </figcaption>
      </figure>
      <figure class="feature">
        <button type="button" class="feature__shot">
          <img class="device__shot" src="screenshots/thumbs/interface-compare.png" data-full="screenshots/interface-compare.png"
               loading="lazy" decoding="async" width="460" alt="Compare: Two or more interfaces on one chart, for when the question is which of them is busy.">
        </button>
        <figcaption>
          <h3>Compare</h3>
          <p>Two or more interfaces on one chart, for when the question is which of them is busy.</p>
        </figcaption>
      </figure>
      <figure class="feature">
        <button type="button" class="feature__shot">
          <img class="device__shot" src="screenshots/thumbs/updates.png" data-full="screenshots/updates.png"
               loading="lazy" decoding="async" width="460" alt="Updates: Firmware and package versions checked when you ask, and started only after an explicit confirmation. The firewall runs its own updater; the app watches it.">
        </button>
        <figcaption>
          <h3>Updates</h3>
          <p>Firmware and package versions checked when you ask, and started only after an explicit confirmation. The firewall runs its own updater; the app watches it.</p>
        </figcaption>
      </figure>
      <figure class="feature">
        <button type="button" class="feature__shot">
          <img class="device__shot" src="screenshots/thumbs/all-firewalls.png" data-full="screenshots/all-firewalls.png"
               loading="lazy" decoding="async" width="460" alt="Several firewalls: Every firewall you have added, each with its own credential and administration switch, and health confirmed over two readings before anything is called a problem.">
        </button>
        <figcaption>
          <h3>Several firewalls</h3>
          <p>Every firewall you have added, each with its own credential and administration switch, and health confirmed over two readings before anything is called a problem.</p>
        </figcaption>
      </figure>
      <figure class="feature">
        <button type="button" class="feature__shot">
          <img class="device__shot" src="screenshots/thumbs/settings-appearance.png" data-full="screenshots/settings-appearance.png"
               loading="lazy" decoding="async" width="460" alt="Appearance: Four Catppuccin flavours, automatic light and dark, accent colours and alternate app icons.">
        </button>
        <figcaption>
          <h3>Appearance</h3>
          <p>Four Catppuccin flavours, automatic light and dark, accent colours and alternate app icons.</p>
        </figcaption>
      </figure>
    </div>

    <ul class="also">
      <li><b>Rules and aliases</b> — filter rules, NAT port forwards, separators and aliases, including URL tables the firewall keeps current itself.</li>
      <li><b>Staged changes</b> — nothing takes effect until Apply Changes, which also flags other administrators' pending work.</li>
      <li><b>Logs and tools</b> — one incident timeline, live log following, ping, traceroute, DNS and a speed test.</li>
      <li><b>Built for iPad too</b> — Network, Aliases, VPN and the timeline use split-view layouts.</li>
    </ul>
  </div>
</section>

<section class="section--sunken" id="setup">
  <div class="wrap">
    <h2>Setting it up</h2>
    <p class="lede">Nothing to install on the firewall. Vaktpost talks to pfSense's built-in XML-RPC service, so setup is an account and a certificate.</p>
    <ol class="steps">
      <li><p>Set <strong>System → Advanced → Admin Access → Max Processes</strong> to 5 or more. XML-RPC competes with the webConfigurator for PHP workers, and the default leaves too few.</p></li>
      <li><p>Create a user under <strong>System → User Manager</strong> and give it the <strong>System - HA node sync</strong> privilege — the one that makes XML-RPC work. Use a dedicated account rather than your own login: it is administrator-equivalent, and the password is stored on the phone. <a href="https://github.com/kladhest-se/vaktpost/blob/main/SECURITY.md">What that credential can do, and how it's protected</a>.</p></li>
      <li><p>Open Vaktpost, enter the firewall address, that username and its password. Allow <strong>local network</strong> access when asked — without it, a firewall on your network is unreachable.</p></li>
      <li><p>Trust the certificate. pfSense's default one is self-signed, so on first connection Vaktpost shows its SHA-256 fingerprint. Compare it with <strong>System → Certificates</strong> in the WebUI, then pin it. After that only that exact certificate is accepted; a different one is blocked until you review it in the firewall's settings.</p></li>
      <li><p>Keep the profile in <strong>monitor-only mode</strong> unless you need administration. Firewall edits are staged and use pfSense's global Apply Changes workflow.</p></li>
    </ol>

    <div class="lab-callout">
      <h3>Try it without a firewall</h3>
      <dl class="lab-details">
        <div><dt>Base URL</dt><dd><code><?= htmlspecialchars($labOrigin, ENT_QUOTES, 'UTF-8') ?></code></dd></div>
        <div><dt>Username</dt><dd>
          <ul class="lab-scenarios">
            <li><code>review</code> — a healthy firewall</li>
            <li><code>updates</code> — outdated firmware and packages</li>
            <li><code>degraded</code> — gateway, VPN and service problems</li>
            <li><code>fault</code> — a firewall that stops responding partway through</li>
            <li><code>noaccess</code> — an account without the XML-RPC privilege</li>
          </ul>
        </dd></div>
        <div><dt>Password</dt><dd><code><?= htmlspecialchars($demoPassword, ENT_QUOTES, 'UTF-8') ?></code></dd></div>
      </dl>
    </div>

  </div>
</section>

<section id="build">
  <div class="wrap">
    <h2>Building it</h2>
    <p>The project is SwiftUI, targets iOS 17, and uses <a href="https://github.com/yonaskolb/XcodeGen">XcodeGen</a>. Clone <a href="https://github.com/kladhest-se/vaktpost">the source from GitHub</a>, run <code>make build</code>, and pass your development team when installing on a device.</p>
    <p>Vaktpost is free software under the <a href="https://github.com/kladhest-se/vaktpost/blob/main/LICENSE">GNU GPL, version 3 or later</a>. The Catppuccin palettes are used under their MIT licence. Everything else — the layout, the design language, the code — is original to this project.</p>
    <div class="actions" style="margin-top:1.6rem">
      <a class="btn btn--solid" href="#setup">Review setup</a>
      <a class="btn btn--ghost" href="https://docs.netgate.com/pfsense/en/latest/">pfSense docs</a>
    </div>
  </div>
</section>

</main>

<footer>
  <div class="wrap">
    <p>Vaktpost is not affiliated with Netgate or with the Catppuccin project. pfSense is a trademark of Netgate.</p>
    <p><a href="privacy.php">Privacy policy</a> · <a href="https://github.com/kladhest-se/vaktpost/issues">Support</a> · <a href="https://github.com/kladhest-se/vaktpost">GitHub</a></p>
    <p>Made in Stockholm.</p>
    <div class="actions" style="margin-top:1.2rem">
      <a class="btn btn--ghost" href="https://ko-fi.com/R7P325M7NE">Support me on Ko-fi</a>
    </div>
  </div>
</footer>

<dialog id="lightbox" aria-label="Enlarged screenshot">
  <button type="button" id="lightbox-close" aria-label="Close">&times;</button>
  <img id="lightbox-img" src="" alt="">
</dialog>

<script src="lightbox.js"></script>
</body>
</html>
