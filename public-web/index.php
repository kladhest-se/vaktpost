<?php
declare(strict_types=1);

$releaseVersion = '1.0.0';
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
      </div>
      <a class="store-badge" href="#">Coming to the App Store — iPhone, iPad &amp; Mac</a>
      <p class="status-line">
        <span>Version <?= htmlspecialchars($releaseVersion, ENT_QUOTES, 'UTF-8') ?></span>
        <span class="dot" aria-hidden="true"></span>
        <span>iOS 17+ · Apple Silicon Macs</span>
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
    <h2>Vaktpost Features</h2>
    <p class="lede">Broad visibility, a small administration surface, and no unattended changes.</p>

    <div class="showcase">
      <div class="showcase__panel">
        <div class="showcase__media device">
          <img class="device__shot" src="screenshots/dnsbl.png"
               alt="The DNSBL section of Overview: a donut chart of blocked domains by count, a legend of the busiest ones, and the busiest hour.">
        </div>
        <div class="showcase__text">
          <h3>Everything, in one overview</h3>
          <p>Live and historical traffic, resource meters, gateway status, alerts, and blocked-domain activity — all in one screen, not spread across several pfSense pages.</p>
        </div>
      </div>

      <div class="showcase__panel showcase__panel--reverse">
        <div class="showcase__media device">
          <img class="device__shot" src="screenshots/ipad-network.png"
               alt="The Network screen on iPad, split-view: the interface list on the left, the selected interface's live throughput and history charts on the right.">
        </div>
        <div class="showcase__text">
          <h3>Built for iPad, not just resized</h3>
          <p>Network, Aliases, VPN, and Incident Timeline get their own split-view layouts. Pick something from the list and its detail stays on screen beside it.</p>
        </div>
      </div>

      <div class="showcase__panel">
        <div class="showcase__media device">
          <img class="device__shot" src="screenshots/ipad-firewall-rules.png"
               alt="The Firewall rules screen on iPad, split-view: the LAN rule list with a pending-changes banner on the left, one rule's full detail — source, destination, and every rule field — on the right.">
        </div>
        <div class="showcase__text">
          <h3>Edits stay reversible</h3>
          <p>Create, edit, and reorder filter rules and NAT port forwards. Nothing takes effect until you review and apply — pfSense's own workflow, not a shortcut around it.</p>
        </div>
      </div>

      <div class="showcase__panel showcase__panel--reverse">
        <div class="showcase__media device">
          <img class="device__shot" src="screenshots/ipad-clients-traffic.png"
               alt="The Clients screen on iPad, traffic view: live bandwidth per device, sorted by bandwidth in, with a search field and interface picker.">
        </div>
        <div class="showcase__text">
          <h3>Every device, one list</h3>
          <p>DHCP leases, ARP, and static mappings combined into one searchable inventory, with vendor names and live traffic per device.</p>
        </div>
      </div>
    </div>

    <div class="capabilities">
      <div class="capability">
        <h4>Logs and investigation</h4>
        <p>Firewall, system, and VPN logs combined into one incident timeline, plus network diagnostics.</p>
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
        <h4>Aliases, side by side</h4>
        <p>The same split-view treatment for host, network, and port aliases.</p>
      </div>
    </div>
  </div>
</section>

<section id="limits">
  <div class="wrap">
    <h2>Kept out of version 1.0</h2>
    <p class="lede">Vaktpost complements the pfSense WebUI rather than replacing it.</p>
    <div class="limit">
      <ul>
        <li>Outbound and 1:1 NAT, virtual IPs</li>
        <li>Schedules and traffic shaping</li>
        <li>Package settings</li>
        <li>Installing or removing packages</li>
        <li>Configuration restore</li>
        <li>CARP synchronization</li>
        <li>Bulk editing, templates, and automation</li>
        <li>Unattended changes</li>
      </ul>
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
        <div><dt>Username</dt><dd><code>review</code> for a healthy firewall, <code>updates</code> for outdated firmware and packages, <code>degraded</code> for gateway/VPN/service problems, or <code>fault</code> to see how the app handles a firewall that stops responding partway through</dd></div>
        <div><dt>Password</dt><dd><code><?= htmlspecialchars($demoPassword, ENT_QUOTES, 'UTF-8') ?></code></dd></div>
      </dl>
    </div>

  </div>
</section>

<section id="build">
  <div class="wrap">
    <h2>Building it</h2>
    <p>The project is SwiftUI, targets iOS 17, and uses <a href="https://github.com/yonaskolb/XcodeGen">XcodeGen</a>. Clone <a href="https://github.com/kladhest-se/vaktpost">the source</a>, run <code>make build</code>, and pass your development team when installing on a device.</p>
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
    <p><a href="privacy.php">Privacy policy</a> · <a href="https://github.com/kladhest-se/vaktpost/issues">Support</a> · <a href="https://github.com/kladhest-se/vaktpost">Source</a></p>
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
