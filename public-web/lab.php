<?php
declare(strict_types=1);

$demoPassword = getenv('VAKTPOST_DEMO_PASSWORD') ?: 'vaktpost-demo';
?>
<!doctype html>
<html lang="en" data-flavor="macchiato" data-accent="mauve">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>XMLAPI Lab — Vaktpost</title>
<meta name="description" content="A public synthetic pfSense XML-RPC endpoint for safely testing the Vaktpost iOS app.">
<meta name="color-scheme" content="dark">
<link rel="icon" href="favicon.svg" type="image/svg+xml">
<link rel="icon" type="image/png" href="app-icons/lavender.png">
<link rel="apple-touch-icon" href="app-icons/lavender.png">
<link rel="stylesheet" href="styles.css">
<link rel="stylesheet" href="lab.css">
</head>
<body data-demo-password="<?= htmlspecialchars($demoPassword, ENT_QUOTES, 'UTF-8') ?>">

<header class="bar">
  <div class="wrap bar__inner">
    <a class="mark" href="index.php">
      <img class="mark__icon" src="app-icons/lavender.png" alt="" width="26" height="26">
      Vaktpost
    </a>
    <nav class="site-nav" aria-label="Primary"><a href="index.php">App</a><a href="lab.php" aria-current="page">XMLAPI Lab</a><a href="privacy.php">Privacy</a><a href="https://github.com/kladhest-se/vaktpost">GitHub</a></nav>
  </div>
</header>

<main class="lab-shell">
  <section class="wrap lab-intro">
    <div>
      <h1>XMLAPI Lab</h1>
      <p class="lab-lede">Connect Vaktpost to realistic pfSense-shaped test data without putting a firewall on the public internet.</p>
    </div>
    <div class="lab-safety"><span aria-hidden="true">✓</span><p><strong>Synthetic endpoint online</strong>No proxy, shell, firewall connection, or stored firewall credentials.</p></div>
  </section>

  <section class="wrap lab-workspace" aria-label="XMLAPI test console">
    <aside class="lab-setup">
      <div class="lab-heading"><div><span>01</span><h2>Connect Vaktpost</h2></div></div>
      <p>Make a separate firewall profile in the app. Use the website address—not the `/xmlrpc.php` path—as its base URL.</p>

      <div class="lab-fields">
        <div class="lab-field"><label>Base URL</label><div><code id="base-url">Loading…</code><button type="button" data-copy="base-url" aria-label="Copy base URL">Copy</button></div></div>
        <div class="lab-field"><label>Username</label><div><code id="username">review</code><button type="button" data-copy="username" aria-label="Copy username">Copy</button></div></div>
        <div class="lab-field"><label>Password</label><div><code id="password" data-copy-value="<?= htmlspecialchars($demoPassword, ENT_QUOTES, 'UTF-8') ?>">•••••••••••••</code><button type="button" data-copy="password" aria-label="Copy password">Copy</button></div></div>
      </div>

      <p class="lab-note"><strong>Safe by construction.</strong> Submitted PHP is never evaluated. The endpoint only recognizes known Vaktpost request signatures and rejects everything else.</p>
    </aside>

    <div class="lab-console">
      <div class="lab-heading lab-heading--row">
        <div><span>02</span><h2 id="scenario-title">Healthy review</h2><p id="scenario-detail">All core services are healthy.</p></div>
        <div class="lab-scenario" role="tablist" aria-label="Test scenario">
          <button type="button" role="tab" aria-selected="true" data-scenario="review">Review</button>
          <button type="button" role="tab" aria-selected="false" data-scenario="updates">Updates</button>
          <button type="button" role="tab" aria-selected="false" data-scenario="degraded">Degraded</button>
          <button type="button" role="tab" aria-selected="false" data-scenario="fault">Fault</button>
        </div>
      </div>

      <div class="lab-probe-layout">
        <div class="lab-probes" role="listbox" aria-label="Probe">
          <button type="button" data-probe="connection"><span>Connection</span><small>Credentials and version</small></button>
          <button type="button" class="is-selected" data-probe="dashboard"><span>Dashboard</span><small>Core batched snapshot</small></button>
          <button type="button" data-probe="interfaces"><span>Interfaces</span><small>WAN, LAN, and VPN</small></button>
          <button type="button" data-probe="clients"><span>Clients</span><small>ARP, DHCP, and aliases</small></button>
          <button type="button" data-probe="packages"><span>Packages</span><small>Installed example packages</small></button>
          <button type="button" data-probe="updates"><span>Package updates</span><small>Repository comparison</small></button>
          <button type="button" data-probe="rules"><span>Firewall rules</span><small>Synthetic rule set</small></button>
          <button type="button" data-probe="logs"><span>Firewall log poll</span><small>Append one live event</small></button>
          <button type="button" data-probe="logBurst"><span>Firewall log burst</span><small>Append five live events</small></button>
          <button type="button" data-probe="logReset"><span>Reset firewall log</span><small>Restore the original fixtures</small></button>
        </div>
        <div class="lab-response">
          <div class="lab-response__head"><span>XML-RPC RESPONSE</span><output id="response-status">Not run</output></div>
          <pre id="response-output">Choose a probe and run it to inspect the JSON Vaktpost receives inside the XML-RPC response.</pre>
          <button type="button" id="run-probe">Run Dashboard probe</button>
        </div>
      </div>
    </div>
  </section>

  <section class="wrap lab-explainer">
    <article><h2>Known calls only</h2><p>The endpoint recognizes Vaktpost’s audited snippets by their signatures. Unknown code receives an XML-RPC fault.</p></article>
    <article><h2>Four useful states</h2><p>Test healthy, outdated, degraded, and deliberate-failure behavior by changing only the profile username.</p></article>
    <article><h2>Updates without risk</h2><p>The Updates profile simulates successful firmware and package completion in an expiring PHP session. No updater runs.</p></article>
    <article><h2>Live logs</h2><p>Each app session grows its own bounded synthetic log stream as Vaktpost polls it, including deterministic bursts for testing follow and unseen-event behavior.</p></article>
  </section>
</main>

<footer>
  <div class="wrap"><p>All XMLAPI Lab data is synthetic. Vaktpost is not affiliated with Netgate.</p><p><a href="index.php">Back to Vaktpost</a></p></div>
</footer>

<script src="lab.js"></script>
</body>
</html>
