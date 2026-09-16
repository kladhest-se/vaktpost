<?php
declare(strict_types=1);

$releaseVersion = '0.1.0';
$releaseStatus = 'preparing for its first public release';
$labOrigin = (!empty($_SERVER['HTTPS']) && $_SERVER['HTTPS'] !== 'off' ? 'https://' : 'http://')
    . ($_SERVER['HTTP_HOST'] ?? 'this site');
?>
<!doctype html>
<html lang="en" data-flavor="mocha" data-accent="sapphire">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Vaktpost — pfSense monitoring and administration for iOS</title>
<meta name="description" content="Vaktpost is an open-source iOS app for monitoring a pfSense firewall and performing a constrained set of confirmed administrative actions.">
<meta name="color-scheme" content="dark light">
<link rel="icon" href="favicon.svg" type="image/svg+xml">
<link rel="icon" type="image/png" href="app-icons/coral.png">
<link rel="apple-touch-icon" href="app-icons/coral.png">
<link rel="stylesheet" href="styles.css">
<meta property="og:title" content="Vaktpost">
<meta property="og:description" content="An iOS app for monitoring and administering a pfSense firewall. Open source, Catppuccin-themed.">
<meta property="og:type" content="website">
</head>
<body>

<header class="bar">
  <div class="wrap bar__inner">
    <a class="mark" href="#top">
      <img class="mark__icon" id="mark-icon" src="app-icons/coral.png" alt="" width="26" height="26">
      Vaktpost
    </a>
    <nav class="site-nav" aria-label="Primary">
      <a href="#top" aria-current="page">App</a>
    </nav>
    <div class="picker">
      <span class="picker__label" id="flavor-label">Flavour</span>
      <div class="flavors" role="group" aria-labelledby="flavor-label" id="flavors"></div>
      <span class="picker__label" id="accent-label">Accent</span>
      <div class="accents" role="group" aria-labelledby="accent-label" id="accents"></div>
    </div>
  </div>
</header>

<main id="top">

<section class="hero">
  <div class="wrap hero__grid">
    <div>
      <h1>Your firewall,<br>on your phone.</h1>
      <p class="hero__sub">Vaktpost is an open-source iOS app for monitoring and carefully administering pfSense CE and pfSense Plus.</p>
      <p class="needs">Version <?= htmlspecialchars($releaseVersion, ENT_QUOTES, 'UTF-8') ?> is <?= htmlspecialchars($releaseStatus, ENT_QUOTES, 'UTF-8') ?>. Its feature set is frozen while compatibility, safety, accessibility, and release quality are finished.</p>
      <div class="actions">
        <a class="btn btn--solid" href="#setup">Set it up</a>
        <a class="btn btn--ghost" href="#features">See the features</a>
      </div>
      <p class="needs">Every firewall starts in monitor-only mode. Administration is enabled separately for each firewall. Nothing is installed on pfSense. Requires iOS 17 or later.</p>
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
    <p class="lede">A focused first release: broad visibility, a deliberately small administration surface, and no unattended changes.</p>

    <div class="features">
      <div class="feature">
        <div class="device device--small">
          <img class="device__shot" src="screenshots/dnsbl.png"
               alt="The DNSBL section of Overview: a donut chart of blocked domains by count, a legend of the busiest ones, and the busiest hour.">
        </div>
        <h3>Health and traffic</h3>
        <p>A configurable overview, live and historical interface traffic, gateways, resources, services, freshness, and alerts derived on the phone.</p>
      </div>

      <div class="feature">
        <div class="device device--small" role="img" aria-label="The Clients screen: a search field, a filter, and rows of devices with their names, addresses and interfaces.">
          <div class="screen">
            <div class="screen__head"><span class="screen__title">Clients</span><span class="screen__time">14:02</span></div>
            <div class="fakefield">Name, IP or MAC</div>
            <div class="segments"><span class="is-on">All</span><span>Seen</span><span>Static</span></div>
            <div class="slab">
              <div class="slab__rail" style="background:var(--green)"></div>
              <div class="slab__body">
                <div class="gw">
                  <div>
                    <div class="gw__name">nas001.example.se</div>
                    <div class="gw__stat">172.16.1.31 &nbsp; 00:11:32:c1:73:88</div>
                  </div>
                  <span class="pill" style="color:var(--green);background:color-mix(in srgb,var(--green) 18%,transparent)">IN ARP</span>
                </div>
              </div>
            </div>
            <div class="slab" style="margin-bottom:0">
              <div class="slab__rail" style="background:var(--green)"></div>
              <div class="slab__body">
                <div class="gw">
                  <div>
                    <div class="gw__name">Living Room Soundbar</div>
                    <div class="gw__stat">172.16.1.56 &nbsp; VLAN_100</div>
                  </div>
                  <span class="pill" style="color:var(--green);background:color-mix(in srgb,var(--green) 18%,transparent)">STATIC</span>
                </div>
              </div>
            </div>
          </div>
        </div>
        <h3>Clients, in one list</h3>
        <p>DHCP leases, ARP, and static mappings joined into one searchable inventory with offline MAC-vendor names and related traffic.</p>
      </div>

      <div class="feature">
        <div class="device device--small" role="img" aria-label="The incident timeline: firewall, VPN and system events from separate logs merged into one prioritised, connected list with severity pills.">
          <div class="screen">
            <div class="screen__head"><span class="screen__title">Incident timeline</span><span class="screen__time">14:02</span></div>
            <div class="segments"><span class="is-on">Incidents</span><span>Attention</span><span>All</span></div>
            <div class="tl-row">
              <div class="tl-rail">
                <span class="tl-dot" style="background:var(--red)"></span>
                <span class="tl-line"></span>
              </div>
              <div class="tl-body">
                <div class="tl-head">
                  <span class="tl-source">Firewall</span>
                  <span class="pill" style="color:var(--red);background:color-mix(in srgb,var(--red) 18%,transparent)">ATTENTION</span>
                </div>
                <div class="tl-msg">block,in,4,,tcp,60,GUEST,any,44122,22801</div>
                <div class="tl-time">Sep 13 19:51 · 2 hrs ago</div>
              </div>
            </div>
            <div class="tl-row">
              <div class="tl-rail">
                <span class="tl-dot" style="background:var(--peach)"></span>
                <span class="tl-line"></span>
              </div>
              <div class="tl-body">
                <div class="tl-head">
                  <span class="tl-source">VPN</span>
                  <span class="pill" style="color:var(--peach);background:color-mix(in srgb,var(--peach) 18%,transparent)">ATTENTION</span>
                </div>
                <div class="tl-msg">TLS Error: cannot locate HMAC in packet</div>
                <div class="tl-time">Sep 13 19:20 · 2 hrs ago</div>
              </div>
            </div>
            <div class="tl-row">
              <div class="tl-rail">
                <span class="tl-dot" style="background:var(--yellow)"></span>
              </div>
              <div class="tl-body">
                <div class="tl-head">
                  <span class="tl-source">System</span>
                  <span class="pill" style="color:var(--yellow);background:color-mix(in srgb,var(--yellow) 18%,transparent)">WARNING</span>
                </div>
                <div class="tl-msg">config warning: invalid path</div>
                <div class="tl-time">Sep 13 20:23 · 1 hr ago</div>
              </div>
            </div>
          </div>
        </div>
        <h3>Logs and investigation</h3>
        <p>Filter, system, authentication, DHCP, and OpenVPN logs, plus a combined incident timeline and network diagnostics.</p>
      </div>

      <div class="feature">
        <div class="device device--small" role="img" aria-label="The VPN screen: tabs for OpenVPN, WireGuard and IPsec, with each tunnel showing how many clients are connected.">
          <div class="screen">
            <div class="screen__head"><span class="screen__title">VPN</span><span class="screen__time">14:02</span></div>
            <div class="segments"><span class="is-on">OpenVPN</span><span>WireGuard</span><span>IPsec</span></div>
            <div class="slab">
              <div class="slab__rail" style="background:var(--green)"></div>
              <div class="slab__body">
                <div class="gw">
                  <div>
                    <div class="gw__name">openvpn1 UDP4:1194</div>
                    <div class="gw__stat">2 clients connected</div>
                  </div>
                  <span class="pill" style="color:var(--green);background:color-mix(in srgb,var(--green) 18%,transparent)">2 CONNECTED</span>
                </div>
              </div>
            </div>
            <div class="slab" style="margin-bottom:0">
              <div class="slab__rail" style="background:var(--green)"></div>
              <div class="slab__body">
                <div class="gw">
                  <div>
                    <div class="gw__name">wireguard1</div>
                    <div class="gw__stat">1 of 1 connected &nbsp; 26s ago</div>
                  </div>
                  <span class="pill" style="color:var(--green);background:color-mix(in srgb,var(--green) 18%,transparent)">UP</span>
                </div>
              </div>
            </div>
          </div>
        </div>
        <h3>VPN and services</h3>
        <p>OpenVPN, WireGuard and IPsec on their own tabs, with connected peers under each instance.</p>
      </div>

      <div class="feature">
        <div class="device device--small" role="img" aria-label="The Firewall rules screen for one interface, showing a drag handle beside each rule, labelled FROM/TO/PORT/DESC fields, a coloured separator between two rules, and a caption explaining where the ordering comes from.">
          <div class="screen">
            <div class="screen__head"><span class="screen__title">Firewall</span><span class="screen__time">14:02</span></div>
            <div class="segments"><span>All</span><span class="is-on">LAN</span><span>GUEST</span></div>
            <p class="reorder-hint">Drag ≡ to reorder. Position here is pfSense's own.</p>
            <div class="reorder-row">
              <span class="draghandle">≡</span>
              <div class="slab">
                <div class="slab__rail" style="background:var(--green)"></div>
                <div class="slab__body">
                  <div class="rulecard__head">
                    <span class="pill" style="color:var(--green);background:color-mix(in srgb,var(--green) 18%,transparent)">PASS</span>
                    <span class="rulecard__proto">TCP</span>
                    <span class="rulecard__iface">LAN</span>
                    <span class="rulecard__chevron">›</span>
                  </div>
                  <div class="rfield"><b>FROM</b><span>any</span></div>
                  <div class="rfield"><b>TO</b><span>alias_host_nas002</span></div>
                  <div class="rfield"><b>DESC</b><span class="prose">Allow NAS backup</span></div>
                </div>
              </div>
            </div>
            <div class="reorder-row">
              <span class="draghandle">≡</span>
              <div class="separator" style="background:color-mix(in srgb,var(--teal) 18%,transparent)">Guest devices</div>
            </div>
            <div class="reorder-row" style="margin-bottom:0">
              <span class="draghandle">≡</span>
              <div class="slab" style="margin-bottom:0">
                <div class="slab__rail" style="background:var(--red)"></div>
                <div class="slab__body">
                  <div class="rulecard__head">
                    <span class="pill" style="color:var(--red);background:color-mix(in srgb,var(--red) 18%,transparent)">REJECT</span>
                    <span class="rulecard__proto">ANY</span>
                    <span class="rulecard__iface">GUEST</span>
                    <span class="rulecard__chevron">›</span>
                  </div>
                  <div class="rfield"><b>FROM</b><span>GUEST net</span></div>
                  <div class="rfield"><b>TO</b><span>any</span></div>
                  <div class="rfield"><b>DESC</b><span class="prose">Block unapproved networks</span></div>
                </div>
              </div>
            </div>
          </div>
        </div>
        <h3>Firewall editing</h3>
        <p>Create, edit, duplicate, delete, and reorder filter rules and NAT port forwards, including coloured separators and host, network, and port aliases.</p>
      </div>

      <div class="feature">
        <div class="device device--small" role="img" aria-label="The Apply Changes screen listing two pending edits made through the app, each with a summary, its target, and a timestamp, above an Apply Changes button.">
          <div class="screen">
            <div class="screen__head"><span class="screen__title">Apply Changes</span><span class="screen__time">14:02</span></div>
            <div class="group"><span>CHANGES TO APPLY</span><i></i></div>
            <div class="slab" style="display:block;background:var(--surface0);padding:2px 12px">
              <div class="pending">
                <span class="pending__icon">↕</span>
                <div style="flex:1">
                  <div class="pending__name">Reordered rules on LAN</div>
                  <div class="pending__meta">3 rules, 1 separator</div>
                </div>
                <span class="pending__time">14:01</span>
              </div>
              <div class="pending">
                <span class="pending__icon">+</span>
                <div style="flex:1">
                  <div class="pending__name">Added rule to GUEST</div>
                  <div class="pending__meta">Block unapproved networks</div>
                </div>
                <span class="pending__time">13:58</span>
              </div>
            </div>
            <div class="applybar"><span>Apply Changes</span><span>2</span></div>
          </div>
        </div>
        <h3>Staged changes</h3>
        <p>Edits stay inactive until Apply Changes. The review names identifiable Vaktpost edits and warns that pfSense may include other administrators' pending work.</p>
      </div>

      <div class="feature">
        <div class="device device--small" role="img" aria-label="The audit trail: two verified entries, each with a summary, who made the change, and what it affected.">
          <div class="screen">
            <div class="screen__head"><span class="screen__title">Audit trail</span><span class="screen__time">14:02</span></div>
            <div class="slab">
              <div class="slab__rail" style="background:var(--green)"></div>
              <div class="slab__body">
                <div class="gw">
                  <div>
                    <div class="gw__name">Reordered rules on LAN</div>
                    <div class="gw__stat">frossmant &nbsp; 3 rules, 1 separator</div>
                  </div>
                  <span class="pill" style="color:var(--green);background:color-mix(in srgb,var(--green) 18%,transparent)">VERIFIED</span>
                </div>
              </div>
            </div>
            <div class="slab" style="margin-bottom:0">
              <div class="slab__rail" style="background:var(--green)"></div>
              <div class="slab__body">
                <div class="gw">
                  <div>
                    <div class="gw__name">Added rule to GUEST</div>
                    <div class="gw__stat">frossmant &nbsp; Block unapproved networks</div>
                  </div>
                  <span class="pill" style="color:var(--green);background:color-mix(in srgb,var(--green) 18%,transparent)">VERIFIED</span>
                </div>
              </div>
            </div>
          </div>
        </div>
        <h3>Audited actions</h3>
        <p>Writes are sent once, read back, attributed to the authenticated pfSense user, and recorded in a protected per-firewall audit trail.</p>
      </div>

      <div class="feature">
        <div class="device device--small">
          <img class="device__shot" src="screenshots/all-firewalls.png"
               alt="The All firewalls screen: a connected profile showing CPU, memory and disk, uptime, gateway and service health, and certificate status.">
        </div>
        <h3>More than one firewall</h3>
        <p>Each profile has its own Keychain credential, TLS settings, refresh interval, monitoring history, and administration switch.</p>
      </div>
    </div>
  </div>
</section>

<section id="limits">
  <div class="wrap">
    <h2>Kept out of the first release</h2>
    <p class="lede">Version 0.1 is not intended to replace the complete pfSense WebUI.</p>
    <div class="limit">
      <p>Outbound and 1:1 NAT, virtual IPs, schedules, traffic shaping, package configuration, backups and restores, bulk editing, templates, automation, and unattended writes are deliberately deferred.</p>
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

<script src="theme.js"></script>
</body>
</html>
