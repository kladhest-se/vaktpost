<?php
declare(strict_types=1);

$releaseVersion = '0.1.0';
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
    </nav>
  </div>
</header>

<main id="top">

<section class="hero">
  <div class="wrap hero__grid">
    <div>
      <h1>Your firewall,<br>on your phone.</h1>
      <p class="hero__sub">Vaktpost is an open-source iOS app for monitoring and administering pfSense CE and pfSense Plus.</p>
      <p class="needs">Version <?= htmlspecialchars($releaseVersion, ENT_QUOTES, 'UTF-8') ?> — feature-frozen while final polish and testing wrap up.</p>
      <div class="actions">
        <a class="btn btn--solid" href="#setup">Set it up</a>
        <a class="btn btn--ghost" href="#features">See the features</a>
      </div>
      <p class="needs">Every firewall starts in monitor-only mode — nothing is installed on pfSense. Requires iOS 17 or later.</p>
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

    <div class="features">
      <div class="feature">
        <div class="device device--small">
          <img class="device__shot" src="screenshots/dnsbl.png"
               alt="The DNSBL section of Overview: a donut chart of blocked domains by count, a legend of the busiest ones, and the busiest hour.">
        </div>
        <h3>Health and traffic</h3>
        <p>Live and historical traffic, resources, gateways, and alerts — all in one overview.</p>
      </div>

      <div class="feature">
        <div class="device device--small">
          <img class="device__shot" src="screenshots/ipad-clients-traffic.png"
               alt="The Clients screen on iPad, traffic view: live bandwidth per device, sorted by bandwidth in, with a search field and interface picker.">
        </div>
        <h3>Clients, in one list</h3>
        <p>DHCP leases, ARP, and static mappings in one searchable list, with vendor names and live traffic.</p>
      </div>

      <div class="feature">
        <div class="device device--small">
          <img class="device__shot" src="screenshots/ipad-incident-timeline.png"
               alt="The incident timeline on iPad, split-view: the list of incidents on the left, a full log entry — traffic, matched rule, and raw log line — on the right.">
        </div>
        <h3>Logs and investigation</h3>
        <p>Firewall, system, and VPN logs combined into one incident timeline, plus network diagnostics.</p>
      </div>

      <div class="feature">
        <div class="device device--small">
          <img class="device__shot" src="screenshots/ipad-vpn.png"
               alt="The VPN screen on iPad, split-view: OpenVPN server and client instances on the left, the selected instance's connected clients on the right.">
        </div>
        <h3>VPN and services</h3>
        <p>OpenVPN, WireGuard, and IPsec, each with its connected peers.</p>
      </div>

      <div class="feature">
        <div class="device device--small">
          <img class="device__shot" src="screenshots/ipad-firewall-rules.png"
               alt="The Firewall rules screen on iPad, split-view: the LAN rule list with a pending-changes banner on the left, one rule's full detail — source, destination, and every rule field — on the right.">
        </div>
        <h3>Firewall editing</h3>
        <p>Create, edit, and reorder filter rules and NAT port forwards, with aliases and separators.</p>
      </div>

      <div class="feature">
        <div class="device device--small">
          <img class="device__shot" src="screenshots/ipad-apply-changes.png"
               alt="The Apply Changes screen on iPad listing pending edits made through the app, each with a summary and a timestamp, above an Apply Changes button.">
        </div>
        <h3>Staged changes</h3>
        <p>Edits stay inactive until you apply them — the review also flags any other administrators' pending work.</p>
      </div>

      <div class="feature">
        <div class="device device--small">
          <img class="device__shot" src="screenshots/all-firewalls.png"
               alt="The All firewalls screen: a connected profile showing CPU, memory and disk, uptime, gateway and service health, and certificate status.">
        </div>
        <h3>More than one firewall</h3>
        <p>Each firewall gets its own credential, TLS settings, and administration switch.</p>
      </div>
    </div>

    <h3 class="ipad-callout">Also built for iPad</h3>
    <p class="lede">Network, Aliases, VPN, and Incident Timeline get dedicated split-view layouts — list and detail side by side, not a stretched phone screen.</p>

    <div class="features">
      <div class="feature">
        <div class="device device--small">
          <img class="device__shot" src="screenshots/ipad-network.png"
               alt="The Network screen on iPad, split-view: the interface list on the left, the selected interface's live throughput and history charts on the right.">
        </div>
        <h3>Network, side by side</h3>
        <p>Pick an interface and its charts stay on screen beside it.</p>
      </div>

      <div class="feature">
        <div class="device device--small">
          <img class="device__shot" src="screenshots/ipad-aliases.png"
               alt="The Aliases screen on iPad, split-view: the alias list on the left, the selected alias's members and a pending-changes note on the right.">
        </div>
        <h3>Aliases, side by side</h3>
        <p>The same split-view treatment for host, network, and port aliases.</p>
      </div>
    </div>
  </div>
</section>

<section id="limits">
  <div class="wrap">
    <h2>Kept out of the first release</h2>
    <p class="lede">Version 0.1 is not intended to replace the complete pfSense WebUI.</p>
    <div class="limit">
      <ul>
        <li>Outbound and 1:1 NAT, virtual IPs</li>
        <li>Schedules and traffic shaping</li>
        <li>Package configuration</li>
        <li>Backups and restores</li>
        <li>Bulk editing, templates, and automation</li>
        <li>Unattended writes</li>
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
      <li><p>Create a user under <strong>System → User Manager</strong> and give it the <strong>System - HA node sync</strong> privilege — the one that makes XML-RPC work. Use a dedicated account rather than your own login: it is administrator-equivalent, and the password is stored on the phone.</p></li>
      <li><p>Open Vaktpost, enter the firewall address, that username and its password.</p></li>
      <li><p>Pin the certificate. pfSense ships a self-signed one, so connect once with untrusted TLS allowed, then tap <strong>Pin last seen certificate</strong> in the firewall's settings. After that the connection is accepted only if that exact certificate is presented. Re-pin when you renew it.</p></li>
      <li><p>Keep the profile in <strong>monitor-only mode</strong> unless you need administration. Firewall edits are staged and use pfSense's global Apply Changes workflow.</p></li>
    </ol>

    <div class="lab-callout">
      <span>NO FIREWALL REQUIRED</span>
      <h3>Try Vaktpost against synthetic pfSense data</h3>
      <p>A public endpoint returns healthy, outdated, degraded, and failure scenarios without exposing a real firewall or accepting executable PHP. Make a separate firewall profile in the app and use the website address — not the <code>/xmlrpc.php</code> path — as its base URL.</p>
      <dl class="lab-details">
        <div><dt>Base URL</dt><dd><code><?= htmlspecialchars($labOrigin, ENT_QUOTES, 'UTF-8') ?></code></dd></div>
        <div><dt>Username</dt><dd><code>review</code> for a healthy firewall, <code>updates</code> for outdated firmware and packages, <code>degraded</code> for gateway/VPN/service problems, or <code>fault</code> to see how the app handles a firewall that stops responding partway through</dd></div>
        <div><dt>Password</dt><dd><code>vaktpost-demo</code></dd></div>
      </dl>
      <p style="margin-top:1rem">Rules, aliases, and port forwards can be created, edited, and deleted to try the app's write flow — nothing to undo afterward. Each session's changes reset to the original fixtures after 20 minutes of inactivity.</p>
    </div>

  </div>
</section>

<section id="build">
  <div class="wrap">
    <h2>Building it</h2>
    <p>The project is SwiftUI, targets iOS 17, and uses <a href="https://github.com/yonaskolb/XcodeGen">XcodeGen</a>. Clone the source, run <code>make build</code>, and pass your development team when installing on a device.</p>
    <p>The Catppuccin palettes are used under their MIT licence. Everything else — the layout, the design language, the code — is original to this project.</p>
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
    <p>Made in Stockholm.</p>
  </div>
</footer>

<dialog id="lightbox" aria-label="Enlarged screenshot">
  <button type="button" id="lightbox-close" aria-label="Close">&times;</button>
  <img id="lightbox-img" src="" alt="">
</dialog>

<script src="lightbox.js"></script>
</body>
</html>
