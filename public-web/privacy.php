<?php
declare(strict_types=1);

// Update this date whenever the policy's substance changes.
$policyUpdated = '17 September 2026';
?>
<!doctype html>
<html lang="en" data-flavor="macchiato" data-accent="mauve">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Privacy policy — Vaktpost</title>
<meta name="description" content="Vaktpost collects no personal data. This policy explains what the app and this website do with information.">
<meta name="color-scheme" content="dark">
<link rel="icon" href="favicon.svg" type="image/svg+xml">
<link rel="stylesheet" href="styles.css">
</head>
<body>

<header class="bar">
  <div class="wrap bar__inner">
    <a class="mark" href="index.php">
      <img class="mark__icon" src="app-icons/lavender.png" alt="" width="26" height="26">
      Vaktpost
    </a>
    <nav class="site-nav" aria-label="Primary">
      <a href="index.php">App</a>
      <a href="lab.php">XMLAPI Lab</a>
      <a href="privacy.php" aria-current="page">Privacy</a>
      <a href="https://github.com/kladhest-se/vaktpost">GitHub</a>
    </nav>
  </div>
</header>

<main id="top">
<section>
  <div class="wrap prose">
    <h1>Privacy policy</h1>
    <p class="lede">Vaktpost collects no personal data. There are no accounts, analytics, advertising or tracking, and the developer receives nothing from the app.</p>
    <p class="meta">Last updated <?= htmlspecialchars($policyUpdated, ENT_QUOTES, 'UTF-8') ?></p>

    <h2>The app</h2>
    <p>Vaktpost connects only to the pfSense firewalls you add to it. Everything it reads from them — status, clients, logs, rules and history — is shown on your device and stored only there.</p>
    <ul>
      <li><strong>Credentials.</strong> Firewall passwords are stored in the iOS Keychain and are available only on the device where you entered them. Removing a firewall in Vaktpost deletes its password. iOS can keep Keychain entries after an app is deleted, so remove your firewalls first if you want the passwords gone.</li>
      <li><strong>Settings and history.</strong> Firewall addresses, preferences, monitoring history and the audit trail of changes you make are stored on your device, and are deleted with the app.</li>
      <li><strong>Face ID and Touch ID.</strong> Handled entirely by iOS. Vaktpost only learns whether unlocking succeeded.</li>
      <li><strong>Notifications.</strong> Alerts are created on your device. No push service is used.</li>
      <li><strong>Local network.</strong> iOS asks for local network access so Vaktpost can reach firewalls on your network. It is used for nothing else.</li>
      <li><strong>Speed test.</strong> If you start one, your <em>firewall</em> — not your phone — exchanges test data with Cloudflare's speed-test service (<code>speed.cloudflare.com</code>). Cloudflare then sees your firewall's public IP address, under <a href="https://www.cloudflare.com/privacypolicy/">Cloudflare's privacy policy</a>.</li>
    </ul>
    <p>Changes you make through Vaktpost are recorded in your firewall's own configuration history under the account you connected with. That record stays on your firewall.</p>

    <h2>This website</h2>
    <p>This site uses no analytics, advertising, third-party scripts or external fonts. The web server may keep ordinary access logs, such as IP address, time and requested page, for security and troubleshooting.</p>
    <p>To show the latest version, the server itself asks GitHub for the project's release tags at most once an hour. Your browser never contacts GitHub, and nothing about you is sent.</p>
    <p>The XMLAPI Lab sets one session cookie, <code>VAKTPOSTLAB</code>, so that changes you make to its synthetic firewall stay separate from other visitors'. It holds no personal data and expires after 30 minutes. Lab data is fictional and resets after 20 minutes of inactivity.</p>

    <h2>Children</h2>
    <p>Vaktpost is a tool for firewall administrators and is not directed at children.</p>

    <h2>Changes and contact</h2>
    <p>If this policy changes, the new version will be published on this page with a new date. Questions can be raised on the <a href="https://github.com/kladhest-se/vaktpost/issues">project's issue tracker</a>.</p>
  </div>
</section>
</main>

<footer>
  <div class="wrap">
    <p>Vaktpost is not affiliated with Netgate or with the Catppuccin project. pfSense is a trademark of Netgate.</p>
    <p><a href="privacy.php">Privacy policy</a> · <a href="https://github.com/kladhest-se/vaktpost/issues">Support</a> · <a href="https://github.com/kladhest-se/vaktpost">GitHub</a></p>
    <p>Made in Stockholm.</p>
  </div>
</footer>

</body>
</html>
