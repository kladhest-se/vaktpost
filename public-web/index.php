<?php
declare(strict_types=1);

$releaseVersion = '0.1.0';
$releaseStatus = 'preparing for its first public release';
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
<link rel="icon" type="image/png" href="icons/coral.png">
<link rel="apple-touch-icon" href="icons/coral.png">
<link rel="stylesheet" href="styles.css">
<meta property="og:title" content="Vaktpost">
<meta property="og:description" content="An iOS app for monitoring and administering a pfSense firewall. Open source, Catppuccin-themed.">
<meta property="og:type" content="website">
</head>
<body>

<header class="bar">
  <div class="wrap bar__inner">
    <a class="mark" href="#top">
      <img class="mark__icon" id="mark-icon" src="icons/coral.png" alt="" width="26" height="26">
      Vaktpost
    </a>
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
        <a class="btn btn--ghost" href="#features">See version 0.1</a>
      </div>
      <p class="needs">Every firewall starts in monitor-only mode. Administration is enabled separately for each firewall. Nothing is installed on pfSense. Requires iOS 17 or later.</p>
    </div>

    <div class="device" role="img" aria-label="A rendering of the Vaktpost overview screen showing a health banner, an uplink throughput chart, CPU and memory meters, and two gateway rows.">
      <div class="screen">
        <div class="screen__head">
          <span class="screen__title">Overview</span>
          <span class="screen__time">14:02</span>
        </div>

        <div class="banner">
          <div class="banner__row">
            <span class="dot"></span>
            <span class="banner__text">All monitored paths healthy</span>
          </div>
          <div class="banner__meta">fw01 — Stockholm &nbsp; 2.8.1</div>
        </div>

        <div class="group"><span>UPLINK</span><i></i></div>
        <div class="slab">
          <div class="slab__rail" style="background:var(--green)"></div>
          <div class="slab__body">
            <div class="slab__label">WAN <b>igb0</b></div>
            <svg class="spark" viewBox="0 0 240 44" preserveAspectRatio="none" aria-hidden="true">
              <path d="M0 40 L0 31 L20 26 L40 30 L60 17 L80 22 L100 12 L120 20 L140 9 L160 16 L180 11 L200 21 L220 14 L240 19 L240 44 L0 44 Z"
                    fill="var(--green)" fill-opacity=".18"/>
              <path d="M0 31 L20 26 L40 30 L60 17 L80 22 L100 12 L120 20 L140 9 L160 16 L180 11 L200 21 L220 14 L240 19"
                    fill="none" stroke="var(--green)" stroke-width="1.6" stroke-linejoin="round"/>
              <path d="M0 39 L20 41 L40 38 L60 40 L80 36 L100 39 L120 35 L140 38 L160 34 L180 37 L200 33 L220 36 L240 34"
                    fill="none" stroke="var(--sky)" stroke-width="1.6" stroke-linejoin="round"/>
            </svg>
            <div class="legend">
              <div><b style="background:var(--green)"></b><span style="color:var(--text)">18.4 Mbit/s</span></div>
              <div><b style="background:var(--sky)"></b><span style="color:var(--text)">2.1 Mbit/s</span></div>
            </div>
          </div>
        </div>

        <div class="group"><span>SYSTEM</span><i></i></div>
        <div class="slab">
          <div class="slab__rail" style="background:var(--sky)"></div>
          <div class="slab__body">
            <div class="slab__label">RESOURCES <b>up 41d 6h</b></div>
            <div class="meter">
              <div class="meter__row"><span>CPU</span><b>12%</b></div>
              <div class="meter__track"><div class="meter__fill" style="width:12%;background:var(--green)"></div></div>
            </div>
            <div class="meter">
              <div class="meter__row"><span>Memory</span><b>38%</b></div>
              <div class="meter__track"><div class="meter__fill" style="width:38%;background:var(--green)"></div></div>
            </div>
            <div class="meter" style="margin-bottom:0">
              <div class="meter__row"><span>States</span><b>4 102 / 98 000</b></div>
              <div class="meter__track"><div class="meter__fill" style="width:5%;background:var(--green)"></div></div>
            </div>
          </div>
        </div>

        <div class="group"><span>GATEWAYS</span><i></i></div>
        <div class="slab">
          <div class="slab__rail" style="background:var(--green)"></div>
          <div class="slab__body">
            <div class="gw">
              <div>
                <div class="gw__name">WAN_DHCP</div>
                <div class="gw__stat">8.4 ms &nbsp; 0% loss</div>
              </div>
              <span class="pill" style="color:var(--green);background:color-mix(in srgb,var(--green) 18%,transparent)">ONLINE</span>
            </div>
          </div>
        </div>
        <div class="slab" style="margin-bottom:0">
          <div class="slab__rail" style="background:var(--yellow)"></div>
          <div class="slab__body">
            <div class="gw">
              <div>
                <div class="gw__name">VPN_BACKUP</div>
                <div class="gw__stat">112 ms &nbsp; 6% loss</div>
              </div>
              <span class="pill" style="color:var(--yellow);background:color-mix(in srgb,var(--yellow) 18%,transparent)">HIGH LOSS</span>
            </div>
          </div>
        </div>

      </div>
    </div>
  </div>
</section>

<section class="section--sunken" id="features">
  <div class="wrap">
    <h2>Version 0.1</h2>
    <p class="lede">A focused first release: broad visibility, a deliberately small administration surface, and no unattended changes.</p>

    <div class="features">
      <div class="feature">
        <h3>Health and traffic</h3>
        <p>A configurable overview, live and historical interface traffic, gateways, resources, services, freshness, and alerts derived on the phone.</p>
      </div>

      <div class="feature">
        <h3>Clients, in one list</h3>
        <p>DHCP leases, ARP, and static mappings joined into one searchable inventory with offline MAC-vendor names and related traffic.</p>
      </div>

      <div class="feature">
        <h3>Logs and investigation</h3>
        <p>Filter, system, authentication, DHCP, and OpenVPN logs, plus a combined incident timeline and network diagnostics.</p>
      </div>

      <div class="feature">
        <h3>VPN and services</h3>
        <p>OpenVPN, WireGuard and IPsec on their own tabs, with connected peers under each instance.</p>
      </div>

      <div class="feature">
        <h3>Firewall editing</h3>
        <p>Create, edit, duplicate, delete, and reorder filter rules and NAT port forwards, including coloured separators and host, network, and port aliases.</p>
      </div>

      <div class="feature">
        <h3>Staged changes</h3>
        <p>Edits stay inactive until Apply Changes. The review names identifiable Vaktpost edits and warns that pfSense may include other administrators' pending work.</p>
      </div>

      <div class="feature">
        <h3>Audited actions</h3>
        <p>Writes are sent once, read back, attributed to the authenticated pfSense user, and recorded in a protected per-firewall audit trail.</p>
      </div>

      <div class="feature">
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
      <p>Outbound and 1:1 NAT, virtual IPs, schedules, traffic shaping, package configuration, firmware installation, backups and restores, bulk editing, templates, automation, and unattended writes are deliberately deferred.</p>
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

  </div>
</section>

<section id="endpoints">
  <div class="wrap">
    <h2>What each screen shows</h2>

    <div class="gallery">

      <figure class="gallery__item">
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
            <div class="slab">
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
            <div class="slab" style="margin-bottom:0">
              <div class="slab__rail" style="background:var(--overlay0)"></div>
              <div class="slab__body">
                <div class="gw">
                  <div>
                    <div class="gw__name">192.168.202.98</div>
                    <div class="gw__stat">3c:6a:9d:12:6e:44 &nbsp; VLAN_202</div>
                  </div>
                  <span class="pill" style="color:var(--overlay1);background:color-mix(in srgb,var(--overlay0) 22%,transparent)">LEASE</span>
                </div>
              </div>
            </div>
          </div>
        </div>
        <figcaption>Clients — leases, ARP and static mappings as one list</figcaption>
      </figure>

      <figure class="gallery__item">
        <div class="device device--small" role="img" aria-label="The interface detail screen: a large throughput graph with current and peak rates.">
          <div class="screen">
            <div class="screen__head"><span class="screen__title">WAN_1</span><span class="screen__time">14:02</span></div>
            <div class="slab">
              <div class="slab__rail" style="background:var(--green)"></div>
              <div class="slab__body">
                <div class="slab__label">WAN_1 <b>ix0</b></div>
                <div class="gw__stat">203.0.113.9/27 &nbsp; 10Gbase-LR</div>
              </div>
            </div>
            <div class="slab">
              <div class="slab__rail" style="background:var(--sky)"></div>
              <div class="slab__body">
                <div class="slab__label">THROUGHPUT</div>
                <svg class="spark spark--tall" viewBox="0 0 240 76" preserveAspectRatio="none" aria-hidden="true">
                  <path d="M0 70 L0 44 L20 38 L40 52 L60 21 L80 33 L100 14 L120 30 L140 11 L160 26 L180 17 L200 36 L220 22 L240 29 L240 76 L0 76 Z"
                        fill="var(--green)" fill-opacity=".16"/>
                  <path d="M0 44 L20 38 L40 52 L60 21 L80 33 L100 14 L120 30 L140 11 L160 26 L180 17 L200 36 L220 22 L240 29"
                        fill="none" stroke="var(--green)" stroke-width="1.6" stroke-linejoin="round"/>
                  <path d="M0 66 L20 69 L40 62 L60 68 L80 58 L100 65 L120 55 L140 63 L160 54 L180 61 L200 52 L220 59 L240 56"
                        fill="none" stroke="var(--sky)" stroke-width="1.6" stroke-linejoin="round"/>
                </svg>
              </div>
            </div>
            <div class="slab" style="margin-bottom:0">
              <div class="slab__rail" style="background:var(--green)"></div>
              <div class="slab__body">
                <div class="legend legend--wide">
                  <div><b style="background:var(--green)"></b><span style="color:var(--text)">IN 42.0 Mbit/s</span></div>
                  <div><b style="background:var(--sky)"></b><span style="color:var(--text)">OUT 316 Mbit/s</span></div>
                </div>
              </div>
            </div>
          </div>
        </div>
        <figcaption>Tap an interface for a live graph, sampled every two seconds</figcaption>
      </figure>

      <figure class="gallery__item">
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
            <div class="slab">
              <div class="slab__rail" style="background:var(--overlay0)"></div>
              <div class="slab__body">
                <div class="gw">
                  <div>
                    <div class="gw__name">openvpn2 UDP4:1195</div>
                    <div class="gw__stat">no clients connected</div>
                  </div>
                  <span class="pill" style="color:var(--overlay1);background:color-mix(in srgb,var(--overlay0) 22%,transparent)">IDLE</span>
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
        <figcaption>VPN — one tab per technology, peers a tap away</figcaption>
      </figure>

    </div>

    <div class="screens">
      <div>
        <h3>Overview</h3>
        <p>Health at a glance: CPU, memory, per-filesystem usage, load, temperature, uptime, the state table and every gateway. Pin the interfaces you care about and they sit at the top.</p>
      </div>
      <div>
        <h3>Clients</h3>
        <p>Every device the firewall knows about, from DHCP leases, ARP and static mappings, with the filter log for each one.</p>
      </div>
      <div>
        <h3>Network</h3>
        <p>Interfaces with addresses, media, errors and counters. Tap one for a live graph. The ARP table on a second tab.</p>
      </div>
      <div>
        <h3>Logs</h3>
        <p>Filter, system, authentication, DHCP and OpenVPN, searchable, with pass and block filtering on the filter log.</p>
      </div>
      <div>
        <h3>VPN</h3>
        <p>OpenVPN, WireGuard and IPsec, each on its own tab, with peers and their transfer under the instance they belong to.</p>
      </div>
      <div>
        <h3>Firewall</h3>
        <p>Filter rules, NAT port forwards, separators, and aliases. Create, edit, duplicate, delete, and drag into order, then review staged work before applying it.</p>
      </div>
      <div>
        <h3>Certificates</h3>
        <p>The store sorted by expiry, and ACME entries showing whether anything will actually renew them.</p>
      </div>
      <div>
        <h3>Services</h3>
        <p>HAProxy frontends and backends, and which backends would notice a dead server.</p>
      </div>
      <div>
        <h3>System</h3>
        <p>Notices, packages, firmware status, Dynamic DNS, CARP, certificates, ACME, HAProxy, and pfBlockerNG.</p>
      </div>
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
