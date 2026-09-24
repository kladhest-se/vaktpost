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
    <p class="lede">Broad visibility, a small administration surface, and no unattended changes.</p>

    <div class="showcase">
      <div class="showcase__panel">
        <div class="showcase__media device">
          <img class="device__shot" src="screenshots/dnsbl.png"
               alt="The DNSBL section of the Overview: a donut of blocked domains by feed, the busiest feeds listed beside it, and the hour with the most blocks.">
        </div>
        <div class="showcase__text">
          <h3>pfBlockerNG, at a glance</h3>
          <p>How much DNSBL is actually blocking, which feed is doing it, and when. The donut is every feed by share of blocks; the list underneath is the same data in order, because a colour is not a number.</p>
        </div>
      </div>

      <div class="showcase__panel showcase__panel--reverse">
        <div class="showcase__media device">
          <img class="device__shot" src="screenshots/network-interfaces.png"
               alt="The Network screen: WAN, LAN and VLAN interfaces, each with its address, link speed and current throughput in and out.">
        </div>
        <div class="showcase__text">
          <h3>Every interface, with its traffic</h3>
          <p>Address, media, link state and live throughput per interface, updated on the refresh interval you choose. Tap one for its history, error counters and the devices behind it.</p>
        </div>
      </div>

      <div class="showcase__panel">
        <div class="showcase__media device">
          <img class="device__shot" src="screenshots/client-investigation.png"
               alt="A client investigation: the device's names and addresses, its manufacturer from the offline IEEE registry, its leases and neighbour entries, and the firewall log lines that match it.">
        </div>
        <div class="showcase__text">
          <h3>One device, everything known about it</h3>
          <p>Names, addresses, vendor, leases, ARP neighbours and the matching firewall log, gathered from every table the firewall keeps. Each log line opens the entry behind it, and the entry opens the rule that decided it.</p>
        </div>
      </div>

      <div class="showcase__panel showcase__panel--reverse">
        <div class="showcase__media device">
          <img class="device__shot" src="screenshots/updates.png"
               alt="The Updates screen: the installed pfSense version against the available one, and the installed packages with updates waiting.">
        </div>
        <div class="showcase__text">
          <h3>Updates you start deliberately</h3>
          <p>Firmware and package versions checked when you ask, and started only after an explicit confirmation. The firewall runs its own updater; the app watches it and reports what happened.</p>
        </div>
      </div>
    </div>

    <div class="capabilities">
      <div class="capability">
        <h4>Logs and investigation</h4>
        <p>Firewall, system and VPN logs on one incident timeline, with live log following and ping, traceroute, DNS and a speed test.</p>
      </div>
      <div class="capability">
        <h4>VPN and services</h4>
        <p>OpenVPN, WireGuard, and IPsec, each with its connected peers.</p>
      </div>
      <div class="capability">
        <h4>Staged changes</h4>
        <p>The review also flags any other administrators' pending work before you apply.</p>
      </div>
      <div class="capability">
        <h4>More than one firewall</h4>
        <p>Each firewall gets its own credential, TLS settings, and administration switch.</p>
      </div>
      <div class="capability">
        <h4>Rules and aliases</h4>
        <p>Filter rules, NAT port forwards, separators and aliases — including URL tables the firewall keeps current itself.</p>
      </div>
      <div class="capability">
        <h4>Built for iPad too</h4>
        <p>Network, Aliases, VPN and the incident timeline use split-view layouts on iPad: pick from the list and the detail stays beside it.</p>
      </div>
    </div>
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
