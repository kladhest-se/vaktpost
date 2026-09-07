import Foundation

/// Every piece of PHP this app will ever send to a firewall.
///
/// This file is the security boundary. Under the REST transport the read-only
/// guarantee was structural — the client had no write verb, and a grep could
/// prove it. `exec_php` has no such property: it runs whatever it is given, so
/// the guarantee has to come from the contents of this file instead.
///
/// The rules, enforced by `vaktpost-tools/tests/readonly.sh` on every publish:
///
///   1. Snippets are `static let` constants here. Nothing may build one by
///      interpolating a value at runtime — a snippet assembled from input is
///      not a snippet anybody reviewed.
///   2. None may contain `write_config`, `mwexec`, `exec(`, `shell_exec`,
///      `system(`, `passthru`, `popen`, `proc_open`, `unlink`, `file_put_contents`,
///      `rename`, `mkdir`, `rmdir`, `chmod`, `chown`, `fopen` in a write mode,
///      or `eval`.
///   3. Only functions on the allowlist below may be called.
///
/// That is a weaker guarantee than the REST client's. There, a violation meant
/// inventing a write verb that did not exist; here it means adding a line to a
/// file. The check is real and runs in CI, but it is an allowlist somebody
/// could extend rather than an absence somebody would have to manufacture, and
/// that difference is worth being honest about.
///
/// Parameters are the sharp edge. Where a snippet needs one — a log file, a
/// line count — it is drawn from a closed enum here, never from user input.
/// String interpolation into PHP is how a read-only snippet becomes a shell.
struct PHPSnippet {

    /// Named so failures can be reported against something a person recognises.
    let name: String
    let script: String

    /// The PHP as written, without the wrapper.
    ///
    /// Kept because the batches contain their parts' bodies but not their
    /// wrappers — every snippet gets `ini_set`, the lock release and the
    /// `json_encode` tail, and a batch has exactly one of each rather than
    /// five. Anything comparing a snippet to a batch has to compare bodies.
    let body: String

    private init(_ name: String, _ body: String) {
        self.name = name
        self.body = body
        // The wrapper, applied to every snippet.
        //
        // `display_errors` off: a PHP notice printed into the response body
        // corrupts the XML before it reaches us, and the failure looks like a
        // parse error rather than the missing function it actually is.
        //
        // The lock release is from hass-pfsense. pfSense holds a mutex for the
        // duration of an XML-RPC call; releasing it once the snippet's own work
        // is set up stops one slow call blocking the webConfigurator.
        //
        // The `json_encode` at the end is also theirs, and the reason this app
        // can reuse its existing JSON models: XML-RPC's encoding of PHP nulls
        // is inconsistent enough to break parsers, so the result travels as one
        // JSON string instead.
        self.script = """
        ini_set('display_errors', 0);
        require_once '/etc/inc/util.inc';
        global $xmlrpclockkey;
        unlock($xmlrpclockkey);

        \(body)

        $toreturn_real = isset($toreturn) ? $toreturn : ["__error" => "snippet produced no result"];
        $toreturn = [];
        $toreturn["real"] = json_encode($toreturn_real);
        """
    }

    /// PHP functions any snippet in this file is permitted to call.
    ///
    /// Read-only by inspection: each either returns a value from `$config`,
    /// reads a status file, or asks the kernel for a counter. The publish check
    /// parses this list out of the source, so adding a call without adding it
    /// here fails rather than passing quietly.
    static let allowedFunctions: Set<String> = [
        // plumbing present in every snippet
        "ini_set", "require_once", "unlock", "json_encode", "json_decode",
        "is_array", "is_iterable", "count", "explode", "implode", "trim",
        "floatval", "intval", "str_replace", "preg_match", "preg_replace",
        "array_slice", "array_values", "array_keys", "array_reverse", "file",
        "file_exists", "file_get_contents", "filemtime", "glob", "basename",
        "sort", "usort", "strval", "substr", "function_exists", "config_get_path", "strpos", "strlen", "filesize",
        "array_key_exists", "intval",
        "date", "time", "max", "min",
        // pfSense read-only accessors
        "get_pkg_info", "get_uptime_sec", "get_temp", "get_single_sysctl", "get_load_average", "get_cpufreq",
        "get_cpu_speed", "get_cpu_count", "cpu_usage", "mem_usage", "swap_usage",
        "get_mbuf", "get_pfstate", "get_mounted_filesystems", "disk_usage",
        "system_get_serial", "system_get_uniqueid", "system_identify_specific_platform",
        "system_get_arp_table", "system_get_dhcpleases",
        "get_configured_interface_with_descr", "get_interface_info",
        "return_gateways_status", "return_gateways_array",
        "get_services", "get_service_status",
        "get_carp_status", "get_carp_interface_status",
        "openvpn_get_active_servers", "openvpn_get_active_clients",
        "wg_get_status",
        "ipsec_list_sa", "get_notices", "get_system_pkg_version",
        "openssl_x509_parse", "base64_decode", "in_array",
        "extension_loaded", "glob", "basename", "filemtime", "is_numeric",
        // Reads an RRD file. There is no writing counterpart in any snippet.
        "rrd_fetch",
        // Probed with function_exists before use; see `pfTables`.
        "pfSense_get_pf_table", "pfr_get_table_addrs",
    ]

    // MARK: - System

    static let telemetry = PHPSnippet("telemetry", """
    require_once '/usr/local/www/includes/functions.inc.php';
    require_once '/etc/inc/config.inc';
    require_once '/etc/inc/pfsense-utils.inc';
    require_once '/etc/inc/system.inc';
    global $config;

    $mbuf = null; $mbufpercent = null;
    get_mbuf($mbuf, $mbufpercent);
    $mbuf_parts = explode("/", $mbuf);
    $has_mbuf = count($mbuf_parts) > 1;

    $pfstate = get_pfstate();
    $pfstate_parts = explode("/", $pfstate);

    $load = explode(",", get_load_average());

    // cpu_usage() returns "<total ticks>|<idle ticks>", not a percentage.
    // Taking floatval of that gave a CPU meter reading 995026240%. The ticks
    // are passed through and differenced on the device, which is how any
    // FreeBSD CPU figure has to be produced.
    $cpu = explode("|", cpu_usage());

    // Temperature, from whichever source this hardware exposes.
    //
    // `get_temp()` returns empty on a box whose Thermal Sensors widget is
    // happily showing 83 °C, because that widget reads a sysctl directly and
    // the one it finds depends on the chipset — "PCH 0" is dev.pchtherm.0 on
    // Intel server boards, where dev.cpu.0 does not exist.
    //
    // Each candidate is tried in turn and the first that answers wins. Values
    // come back formatted as "83.0C", which floatval reads correctly.
    // Sysctls first, then get_temp().
    //
    // Not because get_temp() is unreliable — it works here — but because it
    // returns a number without saying which sensor produced it, and the number
    // alone is not interpretable. 81 °C is unremarkable for a chipset and
    // worth investigating on a CPU die. Probing the sysctls identifies the
    // sensor, which is what lets the app pick a threshold that is not a guess.
    $temp = "";
    $temp_source = "";
    if (function_exists("get_single_sysctl")) {
      $probes = [
        "dev.pchtherm.0.temperature",
        "hw.acpi.thermal.tz0.temperature",
        "dev.cpu.0.temperature",
      ];
      foreach ($probes as $oid) {
        $reading = get_single_sysctl($oid);
        if ($reading !== "" && $reading !== null) {
          $temp = $reading;
          $temp_source = $oid;
          break;
        }
      }
    }
    if ($temp === "" || $temp === null) { $temp = get_temp(); }

    // An array of ["name" => "1537", "descr" => "Super Micro 1537"].
    $platform = system_identify_specific_platform();

    $system = is_array($config["system"]) ? $config["system"] : [];

    $toreturn = [
      "hostname" => $system["hostname"],
      "domain" => $system["domain"],
      "platform" => is_array($platform) ? $platform["descr"] : $platform,
      "serial" => system_get_serial(),
      "cpu_count" => (int) get_cpu_count(),
      "cpu_ticks_total" => (int) $cpu[0],
      "cpu_ticks_idle" => count($cpu) > 1 ? (int) $cpu[1] : null,
      "mem_usage" => floatval(mem_usage()),
      "swap_usage" => floatval(swap_usage()),
      "uptime_sec" => (int) get_uptime_sec(),
      "temp_c" => ($temp === "" || $temp === null) ? null : floatval($temp),
      // Which sensor answered. A chipset runs far hotter than a CPU die, so
      // the same number means different things and needs a different label
      // and a different threshold.
      "temp_source" => $temp_source,
      "cpu_load_avg" => [
        floatval(trim($load[0])), floatval(trim($load[1])), floatval(trim($load[2])),
      ],
      "mbuf_used" => $has_mbuf ? (int) $mbuf_parts[0] : null,
      "mbuf_total" => $has_mbuf ? (int) $mbuf_parts[1] : null,
      "mbuf_usage" => $has_mbuf ? floatval($mbufpercent) : null,
      "currentstates" => (int) $pfstate_parts[0],
      "maximumstates" => (int) $pfstate_parts[1],
      "filesystems" => get_mounted_filesystems(),
    ];
    """)

    static let firmware = PHPSnippet("firmware", """
    require_once '/etc/inc/pkg-utils.inc';
    // Returns ["installed_version" => "26.07", "version" => "26.07",
    //          "pkg_version_compare" => "="]. The comparison is "<" when the
    //          installed version is behind, which is the only reliable signal —
    //          comparing the two strings fails on release suffixes.
    $update = get_system_pkg_version();
    $toreturn = [
      "version" => trim(file_get_contents("/etc/version")),
      "installed_version" => $update["installed_version"],
      "latest_version" => $update["version"],
      "update_available" => ($update["pkg_version_compare"] === "<"),
    ];
    """)

    /// Installed packages, from `$config` rather than the package manager.
    ///
    /// `get_pkg_info()` would give live version comparisons but shells out to
    /// pkg, which is slow enough to notice and is not something this app should
    /// make a firewall do on a timer. The configuration records what is
    /// installed and the version it was installed at, which answers "what is on
    /// this box" — the question the screen is for.
    static let packages = PHPSnippet("packages", """
    global $config;
    $installed = $config["installedpackages"];
    $rows = [];

    if (is_array($installed) && is_iterable($installed["package"])) {
      foreach ($installed["package"] as $item) {
        if (!is_array($item)) { continue; }
        $rows[] = [
          "name" => strval($item["name"]),
          "descr" => strval($item["descr"]),
          "installed_version" => strval($item["version"]),
          "latest_version" => strval($item["version"]),
          // No live comparison without shelling out, so this never claims an
          // update is available rather than guessing that none is.
          "update_available" => false,
        ];
      }
    }

    $toreturn = ["data" => $rows];
    """)

    /// Package versions against the repository.
    ///
    /// `get_pkg_info()` runs pkg internally, and that is worth being explicit
    /// about: the snippet rules forbid *this app* from sending `exec` or
    /// `mwexec`, not pfSense from using them inside its own functions. The
    /// same reasoning already covers `wg_get_status()`, which shells out to
    /// `wg show`. What the rules protect is that every line of PHP this app
    /// sends is reviewable and does not write — which holds here.
    ///
    /// It is slow, though. The call reaches the package repository over the
    /// network and can take several seconds, which is why this is never on the
    /// refresh timer: it runs when somebody asks for it.
    ///
    /// Guarded by `function_exists` and by an argument-count check, because
    /// the signature has changed across versions and calling it wrongly raises
    /// an error pfSense keeps as a permanent notice.
    static let packageUpdates = PHPSnippet("package_updates", """
    $rows = [];
    $available = false;

    if (file_exists("/etc/inc/pkg-utils.inc")) {
      require_once '/etc/inc/pkg-utils.inc';

      if (function_exists("get_pkg_info")) {
        $available = true;
        $info = get_pkg_info("all", false, true);

        if (is_array($info)) {
          foreach ($info as $item) {
            if (!is_array($item)) { continue; }

            $installed = strval($item["installed_version"]);
            $latest = strval($item["version"]);

            // Only packages actually installed. The repository lists every
            // package pfSense offers, and a list of two hundred things you do
            // not have is not an answer to "what needs updating".
            if ($installed === "") { continue; }

            $rows[] = [
              "name" => strval($item["shortname"]) !== ""
                ? strval($item["shortname"]) : strval($item["name"]),
              "descr" => strval($item["desc"]),
              "installed_version" => $installed,
              "latest_version" => $latest,
              "update_available" => ($latest !== "" && $installed !== $latest),
            ];
          }
        }
      }
    }

    $toreturn = ["available" => $available, "data" => $rows];
    """)

    static let notices = PHPSnippet("notices", """
    require_once '/etc/inc/notices.inc';
    $value = get_notices("all");
    if (!$value) { $value = []; }
    $rows = [];
    foreach ($value as $key => $notice) {
      if (!is_array($notice)) { continue; }
      $notice["created_at"] = $key;
      $rows[] = $notice;
    }
    $toreturn = ["data" => $rows];
    """)

    // MARK: - Network

    static let interfaces = PHPSnippet("interfaces", """
    require_once '/etc/inc/interfaces.inc';
    require_once '/usr/local/www/includes/functions.inc.php';
    $rows = [];
    foreach (get_configured_interface_with_descr() as $ifdescr => $ifname) {
      $data = get_interface_info($ifdescr);
      $data["descr"] = $ifname;
      $data["name"] = $ifdescr;
      // Counters, explicitly.
      //
      // get_interface_info() is documented to include these and the throughput
      // chart has never charted anything, which points at them arriving under
      // a name the app does not read or not arriving at all. Setting them from
      // the same call the counters snippet uses removes the question: if they
      // are absent here they are absent everywhere, and the chart can say so
      // instead of waiting forever for a sample.
      $data["inbytes"] = $data["inbytes"];
      $data["outbytes"] = $data["outbytes"];
      $data["counters_present"] = (isset($data["inbytes"]) && isset($data["outbytes"]));
      $rows[] = $data;
    }
    $toreturn = ["data" => $rows];
    """)

    /// Byte and packet counters only.
    ///
    /// The interface-detail screen polls every couple of seconds, and the full
    /// `interfaces` snippet returns fifteen rows of addresses, media strings
    /// and MAC addresses that do not change between samples. This returns the
    /// five fields a rate needs.
    ///
    /// The saving is on the wire rather than on the firewall — the same PHP
    /// function is called either way, and each poll is still an `exec_php`
    /// that pfSense serialises against the webConfigurator. That is why the
    /// screen polls at two seconds and not at ten times a second.
    static let interfaceCounters = PHPSnippet("interface_counters", """
    require_once '/etc/inc/interfaces.inc';
    $rows = [];
    foreach (get_configured_interface_with_descr() as $ifdescr => $ifname) {
      $data = get_interface_info($ifdescr);
      if (!is_array($data)) { continue; }
      $rows[] = [
        "name" => $ifname,
        "hwif" => $data["hwif"],
        "inbytes" => $data["inbytes"],
        "outbytes" => $data["outbytes"],
        "inpkts" => $data["inpkts"],
        "outpkts" => $data["outpkts"],
      ];
    }
    $toreturn = ["data" => $rows];
    """)

    static let gateways = PHPSnippet("gateways", """
    require_once '/etc/inc/gwlb.inc';
    $toreturn = ["data" => return_gateways_status(true)];
    """)

    static let arpTable = PHPSnippet("arp_table", """
    require_once '/etc/inc/system.inc';
    $toreturn = ["data" => system_get_arp_table(false)];
    """)

    static let dhcpLeases = PHPSnippet("dhcp_leases", """
    require_once '/etc/inc/system.inc';
    $leases = system_get_dhcpleases(false);
    $toreturn = ["data" => is_array($leases["lease"]) ? $leases["lease"] : []];
    """)

    static let staticMappings = PHPSnippet("static_mappings", """
    global $config;
    $rows = [];
    if (is_array($config["dhcpd"])) {
      foreach ($config["dhcpd"] as $iface => $conf) {
        if (!is_array($conf) || !is_iterable($conf["staticmap"])) { continue; }
        foreach ($conf["staticmap"] as $entry) {
          if (!is_array($entry)) { continue; }
          $entry["interface"] = $iface;
          $rows[] = $entry;
        }
      }
    }
    $toreturn = ["data" => $rows];
    """)

    /// DNS host overrides, from both the resolver and the forwarder.
    ///
    /// The webConfigurator's own name for a device. Anything with a static
    /// address usually has one, and it is a better label than a reverse-DNS
    /// lookup that fails.
    ///
    /// Written through `config_get_path()` where it exists — pfSense's own
    /// null-safe accessor, added in 2.7 — because reading `$config` by hand
    /// kept fataling on shapes that were not what they looked like. An empty
    /// element parses to a string, a single entry parses as itself rather than
    /// as a list of one, and a fatal in `exec_php` returns an empty HTTP 500
    /// with no message to read. `function_exists` guards the call so a firewall
    /// without it falls back rather than throwing.
    ///
    /// Everything here is wrapped in a shape that cannot fatal: no nested
    /// index, no assumption about types, and each value coerced with `strval`
    /// before it is used.
    static let hostOverrides = PHPSnippet("host_overrides", """
    $rows = [];
    $sections = [];

    if (function_exists("config_get_path")) {
      $sections[] = config_get_path("unbound/hosts", []);
      $sections[] = config_get_path("dnsmasq/hosts", []);
    } else {
      global $config;
      foreach (["unbound", "dnsmasq"] as $service) {
        $section = $config[$service];
        if (!is_array($section)) { continue; }
        $hosts = $section["hosts"];
        if (!is_array($hosts)) { continue; }
        $sections[] = $hosts;
      }
    }

    foreach ($sections as $hosts) {
      if (!is_array($hosts)) { continue; }
      foreach ($hosts as $entry) {
        if (!is_array($entry)) { continue; }

        $rows[] = [
          "host" => strval($entry["host"]),
          "domain" => strval($entry["domain"]),
          "ip" => strval($entry["ip"]),
          "descr" => strval($entry["descr"]),
        ];

        // Aliases are additional names for the same address.
        $aliases = $entry["aliases"];
        if (!is_array($aliases)) { continue; }
        $items = $aliases["item"];
        if (!is_array($items)) { continue; }

        foreach ($items as $alias) {
          if (!is_array($alias)) { continue; }
          $rows[] = [
            "host" => strval($alias["host"]),
            "domain" => strval($alias["domain"]),
            "ip" => strval($entry["ip"]),
            "descr" => strval($alias["description"]),
          ];
        }
      }
    }

    $toreturn = ["data" => $rows];
    """)

    // MARK: - Services and VPN

    static let services = PHPSnippet("services", """
    require_once '/etc/inc/service-utils.inc';
    $rows = [];
    foreach (get_services() as $service) {
      if (!is_array($service)) { continue; }
      $service["status"] = get_service_status($service) ? "running" : "stopped";
      $rows[] = $service;
    }
    $toreturn = ["data" => $rows];
    """)

    static let openvpnServers = PHPSnippet("openvpn_servers", """
    require_once '/etc/inc/openvpn.inc';
    $toreturn = ["data" => openvpn_get_active_servers()];
    """)

    static let openvpnClients = PHPSnippet("openvpn_clients", """
    require_once '/etc/inc/openvpn.inc';
    $toreturn = ["data" => openvpn_get_active_clients()];
    """)

    static let ipsecSAs = PHPSnippet("ipsec_sas", """
    require_once '/etc/inc/ipsec.inc';
    $toreturn = ["data" => ipsec_list_sa()];
    """)

    /// WireGuard tunnels and peers, with live status.
    ///
    /// `wg_get_status()` returns everything the Status → WireGuard page shows:
    /// handshake times, transfer counts, endpoints. It is confirmed present on
    /// 26.07 with WireGuard 0.2.13_4, and guarded by `file_exists` so a
    /// firewall without the package returns empty rather than raising a PHP
    /// error — which pfSense would record as a permanent system notice.
    ///
    /// **Every field is copied out by name, deliberately.** The structure this
    /// returns contains `privatekey`, `private_key`, `presharedkey` and
    /// `preshared_key` for every tunnel and peer. Passing it through whole
    /// would put the firewall's WireGuard private keys into the app's memory,
    /// into the JSON that crosses the network, and into any payload written by
    /// `check-snippets.sh --save`. A private key is not status, and nothing
    /// here needs one to draw a screen.
    static let wireguard = PHPSnippet("wireguard", """
    $path = "/usr/local/pkg/wireguard/includes/wg.inc";
    $tunnels = [];
    $peers = [];

    if (file_exists($path)) {
      require_once $path;
      $status = wg_get_status();

      if (is_array($status)) {
        foreach ($status as $name => $tunnel) {
          if (!is_array($tunnel)) { continue; }
          $conf = is_array($tunnel["config"]) ? $tunnel["config"] : [];

          $tunnels[] = [
            "name" => $name,
            "descr" => $conf["descr"],
            "enabled" => ($conf["enabled"] == "yes"),
            "listen_port" => $tunnel["listen_port"],
            "mtu" => $tunnel["mtu"],
            "status" => $tunnel["status"],
            "public_key" => $tunnel["public_key"],
            "transfer_rx" => $tunnel["transfer_rx"],
            "transfer_tx" => $tunnel["transfer_tx"],
            "peer_count" => is_array($tunnel["peers"]) ? count($tunnel["peers"]) : 0,
          ];

          if (!is_array($tunnel["peers"])) { continue; }
          foreach ($tunnel["peers"] as $key => $peer) {
            if (!is_array($peer)) { continue; }
            $pconf = is_array($peer["config"]) ? $peer["config"] : [];

            $allowed = [];
            if (is_iterable($pconf["allowedips"]["row"])) {
              foreach ($pconf["allowedips"]["row"] as $row) {
                if (!is_array($row) || !$row["address"]) { continue; }
                $allowed[] = $row["mask"]
                  ? $row["address"] . "/" . $row["mask"]
                  : $row["address"];
              }
            }

            // "(none)" is what wg prints for a peer that has never connected.
            $endpoint = $peer["endpoint"];
            if ($endpoint == "(none)") { $endpoint = ""; }

            $peers[] = [
              "tun" => $name,
              "public_key" => $key,
              "descr" => $pconf["descr"],
              "enabled" => ($pconf["enabled"] == "yes"),
              "endpoint" => $endpoint,
              "latest_handshake" => $peer["latest_handshake"],
              "transfer_rx" => $peer["transfer_rx"],
              "transfer_tx" => $peer["transfer_tx"],
              "allowed_ips" => $allowed,
            ];
          }
        }
      }
    }

    $toreturn = ["tunnels" => $tunnels, "peers" => $peers];
    """)

    /// pf tables, if this pfSense exposes a way to read them.
    ///
    /// `sshguard` holds the addresses Login Protection has blocked, which is
    /// worth seeing — not least because the address it blocks is often your
    /// own, and the symptom is a connection that times out rather than one
    /// that says why.
    ///
    /// Reading them needs `pfctl`, which is a shell, which the snippet rules
    /// forbid. pfSense may expose a PHP accessor instead, but the name has
    /// varied across versions and calling one that is not there raises an
    /// error that pfSense keeps as a permanent notice. So this asks
    /// `function_exists` first, tries each candidate in turn, and returns
    /// which ones it looked for when none is present — a self-diagnosing
    /// snippet that cannot fault.
    static let pfTables = PHPSnippet("pf_tables", """
    // Each accessor is called by name, never through a variable.
    //
    // `$found($name)` would be shorter and is how this was written first, but
    // a variable function call defeats the allowlist completely: nothing
    // reading the source can tell what it will invoke. The publish check
    // rejects it, correctly.
    $accessor = "";
    if (function_exists("pfSense_get_pf_table")) { $accessor = "pfSense_get_pf_table"; }
    elseif (function_exists("pfr_get_table_addrs")) { $accessor = "pfr_get_table_addrs"; }

    $tables = [];
    if ($accessor !== "") {
      foreach (["sshguard", "virusprot", "snort2c"] as $name) {
        $entries = null;
        if ($accessor === "pfSense_get_pf_table") {
          $entries = pfSense_get_pf_table($name);
        } elseif ($accessor === "pfr_get_table_addrs") {
          $entries = pfr_get_table_addrs($name);
        }
        if (!is_array($entries)) { continue; }
        $rows = [];
        foreach ($entries as $entry) {
          if (is_array($entry)) {
            $rows[] = strval($entry["address"]);
          } else {
            $rows[] = strval($entry);
          }
        }
        $tables[] = ["name" => $name, "entries" => $rows];
      }
    }

    $toreturn = [
      "available" => ($accessor !== ""),
      "accessor" => $accessor,
      "data" => $tables,
    ];
    """)

    /// HAProxy: what is configured, and whether live status is reachable.
    ///
    /// Configuration is read from `$config` and is certain. Live backend health
    /// is not: it lives in HAProxy's admin socket, and reading it means writing
    /// `show stat` to a socket that also accepts `disable server`. A checker
    /// cannot distinguish those, so the socket is out of bounds here — the
    /// snippet rules would become advisory.
    ///
    /// The alternative is a function from the package's own includes. Whether
    /// one exists varies by version, so this reports what it found rather than
    /// calling something that may not be there: an undefined function raises a
    /// PHP error that pfSense keeps as a permanent notice.
    ///
    /// The package calls frontends `ha_backends` and backends `ha_pools`,
    /// which is confusing but is what the configuration says.
    static let haproxy = PHPSnippet("haproxy", """
    global $config;
    $installed = $config["installedpackages"];
    $ha = is_array($installed) ? $installed["haproxy"] : "";

    $frontends = [];
    $backends = [];

    if (is_array($ha)) {
      $fe = $ha["ha_backends"];
      if (is_array($fe) && is_iterable($fe["item"])) {
        foreach ($fe["item"] as $item) {
          if (!is_array($item)) { continue; }

          // Bind addresses live in a list, not in a single field. Reading
          // `extaddr` gave an empty string for every frontend — the field
          // exists but holds nothing once more than one address is possible.
          $binds = [];
          $ext = $item["a_extaddr"];
          if (is_array($ext) && is_iterable($ext["item"])) {
            foreach ($ext["item"] as $addr) {
              if (!is_array($addr)) { continue; }
              $one = strval($addr["extaddr"]);
              $port = strval($addr["extaddr_port"]);
              if ($port !== "") { $one = $one . ":" . $port; }
              if (array_key_exists("extaddr_ssl", $addr)) { $one = $one . " ssl"; }
              if ($one !== "") { $binds[] = $one; }
            }
          }

          // A frontend with no default backend routes by ACL instead, so the
          // rule count is what says whether it does anything.
          $aclCount = 0;
          $acls = $item["a_acl"];
          if (is_array($acls) && is_iterable($acls["item"])) { $aclCount = count($acls["item"]); }

          $frontends[] = [
            "name" => strval($item["name"]),
            "descr" => strval($item["desc"]),
            "status" => strval($item["status"]),
            "type" => strval($item["type"]),
            "binds" => $binds,
            "acl_count" => $aclCount,
            "backend" => strval($item["backend_serverpool"]),
          ];
        }
      }

      $be = $ha["ha_pools"];
      if (is_array($be) && is_iterable($be["item"])) {
        foreach ($be["item"] as $item) {
          if (!is_array($item)) { continue; }

          $servers = [];
          $list = $item["ha_servers"];
          if (is_array($list) && is_iterable($list["item"])) {
            foreach ($list["item"] as $server) {
              if (!is_array($server)) { continue; }
              $servers[] = [
                "name" => strval($server["name"]),
                "address" => strval($server["address"]),
                "port" => strval($server["port"]),
                "enabled" => array_key_exists("status", $server)
                  ? (strval($server["status"]) == "active")
                  : true,
                "ssl" => array_key_exists("ssl", $server),
                "weight" => strval($server["weight"]),
              ];
            }
          }

          $backends[] = [
            "name" => strval($item["name"]),
            "descr" => strval($item["desc"]),
            "balance" => strval($item["balance"]),
            // Whether health checking is configured at all. A backend with no
            // check is one HAProxy will keep sending traffic to after it dies.
            "check_type" => strval($item["check_type"]),
            "check_uri" => strval($item["monituri"]),
            "check_interval" => strval($item["checkinter"]),
            "servers" => $servers,
          ];
        }
      }
    }

    // Probed, never called. Reports which accessor this version has so live
    // status can be added without guessing at a name.
    $probes = [
      "haproxy_get_backend_status",
      "haproxy_stats",
      "haproxy_get_stats",
      "get_haproxy_servers",
    ];
    $available = [];
    foreach ($probes as $candidate) {
      if (function_exists($candidate)) { $available[] = $candidate; }
    }

    $toreturn = [
      "installed" => is_array($ha),
      "frontends" => $frontends,
      "backends" => $backends,
      "stats_accessors" => $available,
    ];
    """)

    /// ACME certificates from the acme package.
    ///
    /// Separate from `certificates` because they answer a different question.
    /// The certificate store says when a certificate expires; this says whether
    /// anything is going to renew it. A Let's Encrypt certificate with 40 days
    /// left is fine if renewal is configured and a problem if it is not, and
    /// the store cannot tell you which.
    ///
    /// Renewal history is not in the configuration — the package writes it to
    /// the certificate itself, so the validity dates come from `certificates`
    /// and are joined on the description in the app.
    static let acme = PHPSnippet("acme", """
    global $config;
    $installed = $config["installedpackages"];
    $acme = is_array($installed) ? $installed["acme"] : "";

    $rows = [];
    $accounts = [];

    if (is_array($acme)) {
      $certs = $acme["certificates"];
      if (is_array($certs) && is_iterable($certs["item"])) {
        foreach ($certs["item"] as $item) {
          if (!is_array($item)) { continue; }

          // Domains are rows of a name and a validation method.
          $domains = [];
          $list = $item["a_domainlist"];
          if (is_array($list) && is_iterable($list["item"])) {
            foreach ($list["item"] as $domain) {
              if (!is_array($domain)) { continue; }
              $name = strval($domain["name"]);
              if ($name !== "") { $domains[] = $name; }
            }
          }

          $rows[] = [
            "name" => strval($item["name"]),
            "descr" => strval($item["descr"]),
            "account" => strval($item["acmeaccount"]),
            "keylength" => strval($item["keylength"]),
            "renew_after" => strval($item["renewafter"]),
            // Omitted when disabled, like every other pfSense boolean.
            "enabled" => array_key_exists("status", $item)
              ? (strval($item["status"]) == "active")
              : false,
            "domains" => $domains,
          ];
        }
      }

      $keys = $acme["accountkeys"];
      if (is_array($keys) && is_iterable($keys["item"])) {
        foreach ($keys["item"] as $key) {
          if (!is_array($key)) { continue; }
          $accounts[] = [
            "name" => strval($key["name"]),
            "descr" => strval($key["descr"]),
            // The server URL says production or staging, which is worth
            // knowing: a staging certificate is not trusted by anything.
            "server" => strval($key["acmeserver"]),
          ];
        }
      }
    }

    $toreturn = [
      "installed" => is_array($acme),
      "certificates" => $rows,
      "accounts" => $accounts,
    ];
    """)

    /// Everything the Overview and Network tabs need.
    ///
    /// One call instead of 5. pfSense serialises XML-RPC, so each
    /// request queues behind the last and behind the webConfigurator — the cost
    /// of a refresh was in the round trips, not the work.
    ///
    /// The bodies are the same PHP the individual snippets use, in sequence,
    /// each capturing `$toreturn` before the next overwrites it.
    ///
    /// The accumulator is named `$vaktpost_batch` rather than something ordinary
    /// because it shares scope with every body here. `$sections` was the first
    /// choice and `host_overrides` uses that name for a local, resetting it
    /// halfway through — three sections were discarded and the batch returned
    /// success, so Clients and ARP were empty with nothing reported.
    ///
    /// Grouped rather than combined into one: a PHP fatal cannot be caught, so
    /// a single call would mean one bad section blanking the whole dashboard.
    static let batchCore = PHPSnippet("batch_core", """
    $vaktpost_batch = [];

    require_once '/usr/local/www/includes/functions.inc.php';
    require_once '/etc/inc/config.inc';
    require_once '/etc/inc/pfsense-utils.inc';
    require_once '/etc/inc/system.inc';
    global $config;

    $mbuf = null; $mbufpercent = null;
    get_mbuf($mbuf, $mbufpercent);
    $mbuf_parts = explode("/", $mbuf);
    $has_mbuf = count($mbuf_parts) > 1;

    $pfstate = get_pfstate();
    $pfstate_parts = explode("/", $pfstate);

    $load = explode(",", get_load_average());

    // cpu_usage() returns "<total ticks>|<idle ticks>", not a percentage.
    // Taking floatval of that gave a CPU meter reading 995026240%. The ticks
    // are passed through and differenced on the device, which is how any
    // FreeBSD CPU figure has to be produced.
    $cpu = explode("|", cpu_usage());

    // Temperature, from whichever source this hardware exposes.
    //
    // `get_temp()` returns empty on a box whose Thermal Sensors widget is
    // happily showing 83 °C, because that widget reads a sysctl directly and
    // the one it finds depends on the chipset — "PCH 0" is dev.pchtherm.0 on
    // Intel server boards, where dev.cpu.0 does not exist.
    //
    // Each candidate is tried in turn and the first that answers wins. Values
    // come back formatted as "83.0C", which floatval reads correctly.
    // Sysctls first, then get_temp().
    //
    // Not because get_temp() is unreliable — it works here — but because it
    // returns a number without saying which sensor produced it, and the number
    // alone is not interpretable. 81 °C is unremarkable for a chipset and
    // worth investigating on a CPU die. Probing the sysctls identifies the
    // sensor, which is what lets the app pick a threshold that is not a guess.
    $temp = "";
    $temp_source = "";
    if (function_exists("get_single_sysctl")) {
      $probes = [
        "dev.pchtherm.0.temperature",
        "hw.acpi.thermal.tz0.temperature",
        "dev.cpu.0.temperature",
      ];
      foreach ($probes as $oid) {
        $reading = get_single_sysctl($oid);
        if ($reading !== "" && $reading !== null) {
          $temp = $reading;
          $temp_source = $oid;
          break;
        }
      }
    }
    if ($temp === "" || $temp === null) { $temp = get_temp(); }

    // An array of ["name" => "1537", "descr" => "Super Micro 1537"].
    $platform = system_identify_specific_platform();

    $system = is_array($config["system"]) ? $config["system"] : [];

    $toreturn = [
      "hostname" => $system["hostname"],
      "domain" => $system["domain"],
      "platform" => is_array($platform) ? $platform["descr"] : $platform,
      "serial" => system_get_serial(),
      "cpu_count" => (int) get_cpu_count(),
      "cpu_ticks_total" => (int) $cpu[0],
      "cpu_ticks_idle" => count($cpu) > 1 ? (int) $cpu[1] : null,
      "mem_usage" => floatval(mem_usage()),
      "swap_usage" => floatval(swap_usage()),
      "uptime_sec" => (int) get_uptime_sec(),
      "temp_c" => ($temp === "" || $temp === null) ? null : floatval($temp),
      // Which sensor answered. A chipset runs far hotter than a CPU die, so
      // the same number means different things and needs a different label
      // and a different threshold.
      "temp_source" => $temp_source,
      "cpu_load_avg" => [
        floatval(trim($load[0])), floatval(trim($load[1])), floatval(trim($load[2])),
      ],
      "mbuf_used" => $has_mbuf ? (int) $mbuf_parts[0] : null,
      "mbuf_total" => $has_mbuf ? (int) $mbuf_parts[1] : null,
      "mbuf_usage" => $has_mbuf ? floatval($mbufpercent) : null,
      "currentstates" => (int) $pfstate_parts[0],
      "maximumstates" => (int) $pfstate_parts[1],
      "filesystems" => get_mounted_filesystems(),
    ];
    $vaktpost_batch["telemetry"] = $toreturn;

    require_once '/etc/inc/pkg-utils.inc';
    // Returns ["installed_version" => "26.07", "version" => "26.07",
    //          "pkg_version_compare" => "="]. The comparison is "<" when the
    //          installed version is behind, which is the only reliable signal —
    //          comparing the two strings fails on release suffixes.
    $update = get_system_pkg_version();
    $toreturn = [
      "version" => trim(file_get_contents("/etc/version")),
      "installed_version" => $update["installed_version"],
      "latest_version" => $update["version"],
      "update_available" => ($update["pkg_version_compare"] === "<"),
    ];
    $vaktpost_batch["firmware"] = $toreturn;

    require_once '/etc/inc/interfaces.inc';
    require_once '/usr/local/www/includes/functions.inc.php';
    $rows = [];
    foreach (get_configured_interface_with_descr() as $ifdescr => $ifname) {
      $data = get_interface_info($ifdescr);
      $data["descr"] = $ifname;
      $data["name"] = $ifdescr;
      // Counters, explicitly.
      //
      // get_interface_info() is documented to include these and the throughput
      // chart has never charted anything, which points at them arriving under
      // a name the app does not read or not arriving at all. Setting them from
      // the same call the counters snippet uses removes the question: if they
      // are absent here they are absent everywhere, and the chart can say so
      // instead of waiting forever for a sample.
      $data["inbytes"] = $data["inbytes"];
      $data["outbytes"] = $data["outbytes"];
      $data["counters_present"] = (isset($data["inbytes"]) && isset($data["outbytes"]));
      $rows[] = $data;
    }
    $toreturn = ["data" => $rows];
    $vaktpost_batch["interfaces"] = $toreturn;

    require_once '/etc/inc/gwlb.inc';
    $toreturn = ["data" => return_gateways_status(true)];
    $vaktpost_batch["gateways"] = $toreturn;

    require_once '/etc/inc/service-utils.inc';
    $rows = [];
    foreach (get_services() as $service) {
      if (!is_array($service)) { continue; }
      $service["status"] = get_service_status($service) ? "running" : "stopped";
      $rows[] = $service;
    }
    $toreturn = ["data" => $rows];
    $vaktpost_batch["services"] = $toreturn;

    $toreturn = ["sections" => $vaktpost_batch];
    """)

    /// Everything the Clients tab joins together, plus the aliases it names devices from.
    ///
    /// One call instead of 5. pfSense serialises XML-RPC, so each
    /// request queues behind the last and behind the webConfigurator — the cost
    /// of a refresh was in the round trips, not the work.
    ///
    /// The bodies are the same PHP the individual snippets use, in sequence,
    /// each capturing `$toreturn` before the next overwrites it.
    ///
    /// The accumulator is named `$vaktpost_batch` rather than something ordinary
    /// because it shares scope with every body here. `$sections` was the first
    /// choice and `host_overrides` uses that name for a local, resetting it
    /// halfway through — three sections were discarded and the batch returned
    /// success, so Clients and ARP were empty with nothing reported.
    ///
    /// Grouped rather than combined into one: a PHP fatal cannot be caught, so
    /// a single call would mean one bad section blanking the whole dashboard.
    static let batchClients = PHPSnippet("batch_clients", """
    $vaktpost_batch = [];

    require_once '/etc/inc/system.inc';
    $toreturn = ["data" => system_get_arp_table(false)];
    $vaktpost_batch["arp_table"] = $toreturn;

    require_once '/etc/inc/system.inc';
    $leases = system_get_dhcpleases(false);
    $toreturn = ["data" => is_array($leases["lease"]) ? $leases["lease"] : []];
    $vaktpost_batch["dhcp_leases"] = $toreturn;

    global $config;
    $rows = [];
    if (is_array($config["dhcpd"])) {
      foreach ($config["dhcpd"] as $iface => $conf) {
        if (!is_array($conf) || !is_iterable($conf["staticmap"])) { continue; }
        foreach ($conf["staticmap"] as $entry) {
          if (!is_array($entry)) { continue; }
          $entry["interface"] = $iface;
          $rows[] = $entry;
        }
      }
    }
    $toreturn = ["data" => $rows];
    $vaktpost_batch["static_mappings"] = $toreturn;

    $rows = [];
    $sections = [];

    if (function_exists("config_get_path")) {
      $sections[] = config_get_path("unbound/hosts", []);
      $sections[] = config_get_path("dnsmasq/hosts", []);
    } else {
      global $config;
      foreach (["unbound", "dnsmasq"] as $service) {
        $section = $config[$service];
        if (!is_array($section)) { continue; }
        $hosts = $section["hosts"];
        if (!is_array($hosts)) { continue; }
        $sections[] = $hosts;
      }
    }

    foreach ($sections as $hosts) {
      if (!is_array($hosts)) { continue; }
      foreach ($hosts as $entry) {
        if (!is_array($entry)) { continue; }

        $rows[] = [
          "host" => strval($entry["host"]),
          "domain" => strval($entry["domain"]),
          "ip" => strval($entry["ip"]),
          "descr" => strval($entry["descr"]),
        ];

        // Aliases are additional names for the same address.
        $aliases = $entry["aliases"];
        if (!is_array($aliases)) { continue; }
        $items = $aliases["item"];
        if (!is_array($items)) { continue; }

        foreach ($items as $alias) {
          if (!is_array($alias)) { continue; }
          $rows[] = [
            "host" => strval($alias["host"]),
            "domain" => strval($alias["domain"]),
            "ip" => strval($entry["ip"]),
            "descr" => strval($alias["description"]),
          ];
        }
      }
    }

    $toreturn = ["data" => $rows];
    $vaktpost_batch["host_overrides"] = $toreturn;

    global $config;
    $aliases = $config["aliases"];
    $toreturn = ["data" => (is_array($aliases) && is_iterable($aliases["alias"])) ? $aliases["alias"] : []];
    $vaktpost_batch["firewall_aliases"] = $toreturn;

    $toreturn = ["sections" => $vaktpost_batch];
    """)

    /// Every VPN technology in one pass.
    ///
    /// One call instead of 4. pfSense serialises XML-RPC, so each
    /// request queues behind the last and behind the webConfigurator — the cost
    /// of a refresh was in the round trips, not the work.
    ///
    /// The bodies are the same PHP the individual snippets use, in sequence,
    /// each capturing `$toreturn` before the next overwrites it.
    ///
    /// The accumulator is named `$vaktpost_batch` rather than something ordinary
    /// because it shares scope with every body here. `$sections` was the first
    /// choice and `host_overrides` uses that name for a local, resetting it
    /// halfway through — three sections were discarded and the batch returned
    /// success, so Clients and ARP were empty with nothing reported.
    ///
    /// Grouped rather than combined into one: a PHP fatal cannot be caught, so
    /// a single call would mean one bad section blanking the whole dashboard.
    static let batchVpn = PHPSnippet("batch_vpn", """
    $vaktpost_batch = [];

    require_once '/etc/inc/openvpn.inc';
    $toreturn = ["data" => openvpn_get_active_servers()];
    $vaktpost_batch["openvpn_servers"] = $toreturn;

    require_once '/etc/inc/openvpn.inc';
    $toreturn = ["data" => openvpn_get_active_clients()];
    $vaktpost_batch["openvpn_clients"] = $toreturn;

    require_once '/etc/inc/ipsec.inc';
    $toreturn = ["data" => ipsec_list_sa()];
    $vaktpost_batch["ipsec_sas"] = $toreturn;

    $path = "/usr/local/pkg/wireguard/includes/wg.inc";
    $tunnels = [];
    $peers = [];

    if (file_exists($path)) {
      require_once $path;
      $status = wg_get_status();

      if (is_array($status)) {
        foreach ($status as $name => $tunnel) {
          if (!is_array($tunnel)) { continue; }
          $conf = is_array($tunnel["config"]) ? $tunnel["config"] : [];

          $tunnels[] = [
            "name" => $name,
            "descr" => $conf["descr"],
            "enabled" => ($conf["enabled"] == "yes"),
            "listen_port" => $tunnel["listen_port"],
            "mtu" => $tunnel["mtu"],
            "status" => $tunnel["status"],
            "public_key" => $tunnel["public_key"],
            "transfer_rx" => $tunnel["transfer_rx"],
            "transfer_tx" => $tunnel["transfer_tx"],
            "peer_count" => is_array($tunnel["peers"]) ? count($tunnel["peers"]) : 0,
          ];

          if (!is_array($tunnel["peers"])) { continue; }
          foreach ($tunnel["peers"] as $key => $peer) {
            if (!is_array($peer)) { continue; }
            $pconf = is_array($peer["config"]) ? $peer["config"] : [];

            $allowed = [];
            if (is_iterable($pconf["allowedips"]["row"])) {
              foreach ($pconf["allowedips"]["row"] as $row) {
                if (!is_array($row) || !$row["address"]) { continue; }
                $allowed[] = $row["mask"]
                  ? $row["address"] . "/" . $row["mask"]
                  : $row["address"];
              }
            }

            // "(none)" is what wg prints for a peer that has never connected.
            $endpoint = $peer["endpoint"];
            if ($endpoint == "(none)") { $endpoint = ""; }

            $peers[] = [
              "tun" => $name,
              "public_key" => $key,
              "descr" => $pconf["descr"],
              "enabled" => ($pconf["enabled"] == "yes"),
              "endpoint" => $endpoint,
              "latest_handshake" => $peer["latest_handshake"],
              "transfer_rx" => $peer["transfer_rx"],
              "transfer_tx" => $peer["transfer_tx"],
              "allowed_ips" => $allowed,
            ];
          }
        }
      }
    }

    $toreturn = ["tunnels" => $tunnels, "peers" => $peers];
    $vaktpost_batch["wireguard"] = $toreturn;

    $toreturn = ["sections" => $vaktpost_batch];
    """)

    /// The slower-moving system facts.
    ///
    /// One call instead of 5. pfSense serialises XML-RPC, so each
    /// request queues behind the last and behind the webConfigurator — the cost
    /// of a refresh was in the round trips, not the work.
    ///
    /// The bodies are the same PHP the individual snippets use, in sequence,
    /// each capturing `$toreturn` before the next overwrites it.
    ///
    /// The accumulator is named `$vaktpost_batch` rather than something ordinary
    /// because it shares scope with every body here. `$sections` was the first
    /// choice and `host_overrides` uses that name for a local, resetting it
    /// halfway through — three sections were discarded and the batch returned
    /// success, so Clients and ARP were empty with nothing reported.
    ///
    /// Grouped rather than combined into one: a PHP fatal cannot be caught, so
    /// a single call would mean one bad section blanking the whole dashboard.
    static let batchSystem = PHPSnippet("batch_system", """
    $vaktpost_batch = [];

    require_once '/etc/inc/notices.inc';
    $value = get_notices("all");
    if (!$value) { $value = []; }
    $rows = [];
    foreach ($value as $key => $notice) {
      if (!is_array($notice)) { continue; }
      $notice["created_at"] = $key;
      $rows[] = $notice;
    }
    $toreturn = ["data" => $rows];
    $vaktpost_batch["notices"] = $toreturn;

    global $config;
    $rows = [];

    // Names ACME manages, so the general list can leave them to their own
    // screen. Matching in the app would need ACME loaded first, and the two
    // screens load independently.
    $acmeNames = [];
    $installed = $config["installedpackages"];
    $acme = is_array($installed) ? $installed["acme"] : "";
    if (is_array($acme)) {
      $certs = $acme["certificates"];
      if (is_array($certs) && is_iterable($certs["item"])) {
        foreach ($certs["item"] as $entry) {
          if (!is_array($entry)) { continue; }
          $acmeNames[] = strval($entry["name"]);
          $acmeNames[] = strval($entry["descr"]);
        }
      }
    }
    foreach (["cert", "ca"] as $section) {
      if (!is_iterable($config[$section])) { continue; }
      foreach ($config[$section] as $item) {
        if (!is_array($item) || !$item["crt"]) { continue; }
        $parsed = openssl_x509_parse(base64_decode($item["crt"]));
        if (!is_array($parsed)) { continue; }
        $rows[] = [
          "refid" => $item["refid"],
          "descr" => $item["descr"],
          "is_ca" => $section == "ca",
          "is_acme" => in_array(strval($item["descr"]), $acmeNames),
          "valid_from" => $parsed["validFrom_time_t"],
          "valid_until" => $parsed["validTo_time_t"],
        ];
      }
    }
    $toreturn = ["data" => $rows];
    $vaktpost_batch["certificates"] = $toreturn;

    global $config;
    $rows = [];

    foreach (["dyndnses" => "dyndns", "dnsupdates" => "dnsupdate"] as $section => $key) {
      $conf = $config[$section];
      if (!is_array($conf) || !is_iterable($conf[$key])) { continue; }

      foreach ($conf[$key] as $entry) {
        if (!is_array($entry)) { continue; }

        $host = strval($entry["host"]);
        $domain = strval($entry["domain"]);
        $fqdn = ($domain !== "") ? $host . "." . $domain : $host;

        // The cache file holds "<address>|<unix time>", not just an address.
        // Reading it whole put "203.0.113.9|1788038229" on screen where an
        // address belonged, and threw away the timestamp the firewall had
        // already recorded — the modification time is when the file was
        // touched, which is not the same as when the address last changed.
        $cached = "";
        $when = 0;
        $best = "";
        foreach (glob("/conf/dyndns_*.cache") as $path) {
          $base = basename($path);
          // Prefer a file naming both host and domain; fall back to the host.
          if ($domain !== "" && strpos($base, $domain) !== false && strpos($base, $host) !== false) {
            $best = $path;
          } elseif ($best === "" && strpos($base, $host) !== false) {
            $best = $path;
          }
        }
        if ($best !== "") {
          $raw = trim(file_get_contents($best));
          $parts = explode("|", $raw);
          $cached = $parts[0];
          $when = (count($parts) > 1) ? intval($parts[1]) : filemtime($best);
        }

        $rows[] = [
          "host" => $fqdn,
          "type" => strval($entry["type"]),
          "interface" => strval($entry["interface"]),
          "descr" => strval($entry["descr"]),
          // pfSense stores this as an empty element when on, which reads as
          // false. Presence of the key is what means enabled; a disabled entry
          // has no key at all. Every entry showed DISABLED before this.
          "enabled" => array_key_exists("enable", $entry),
          "cached_address" => $cached,
          "updated_at" => $when,
        ];
      }
    }

    $toreturn = ["data" => $rows];
    $vaktpost_batch["dyndns"] = $toreturn;

    global $config;
    $installed = $config["installedpackages"];
    $rows = [];

    if (is_array($installed) && is_iterable($installed["package"])) {
      foreach ($installed["package"] as $item) {
        if (!is_array($item)) { continue; }
        $rows[] = [
          "name" => strval($item["name"]),
          "descr" => strval($item["descr"]),
          "installed_version" => strval($item["version"]),
          "latest_version" => strval($item["version"]),
          // No live comparison without shelling out, so this never claims an
          // update is available rather than guessing that none is.
          "update_available" => false,
        ];
      }
    }

    $toreturn = ["data" => $rows];
    $vaktpost_batch["packages"] = $toreturn;

    require_once '/etc/inc/interfaces.inc';
    global $config;
    $vips = [];
    $virtualip = $config["virtualip"];
    if (is_array($virtualip) && is_iterable($virtualip["vip"])) {
      foreach ($virtualip["vip"] as $vip) {
        if (!is_array($vip) || $vip["mode"] != "carp") { continue; }
        $vip["status"] = get_carp_interface_status("_vip" . $vip["uniqid"]);
        $vips[] = $vip;
      }
    }
    $toreturn = ["enable" => get_carp_status() ? true : false, "interfaces" => $vips];
    $vaktpost_batch["carp"] = $toreturn;

    $toreturn = ["sections" => $vaktpost_batch];
    """)

    /// Can RRD history be read at all?
    ///
    /// pfSense keeps months of per-interface, per-gateway and system history in
    /// `/var/db/rrd/*.rrd`, and this app shows only what it has watched since
    /// launch. Reading that history is the one thing that would make it better
    /// than the web UI on a phone.
    ///
    /// The obstacle is that RRD files are a binary format read by `rrdtool`,
    /// a shell binary — pfSense's own graph page shells out to it. PHP can read
    /// them directly only if the `rrd` extension is loaded, which is not
    /// standard here.
    ///
    /// So this reports what exists before anything is built on it. Three
    /// features have been designed against a guess about what the firewall
    /// exposes, and two of those guesses were wrong.
    static let rrdProbe = PHPSnippet("rrd_probe", """
    $functions = [];
    foreach (["rrd_fetch", "rrd_info", "rrd_lastupdate", "rrd_graph",
              "rrd_first", "rrd_last"] as $fn) {
      if (function_exists($fn)) { $functions[] = $fn; }
    }

    $extension = extension_loaded("rrd");

    // The catalogue of what could be charted: the names say what each file
    // holds — wan-traffic.rrd, system-processor.rrd, per-gateway quality.
    $files = [];
    $dir = "/var/db/rrd";
    if (file_exists($dir)) {
      foreach (glob($dir . "/*.rrd") as $path) {
        $files[] = [
          "name" => basename($path),
          "bytes" => filesize($path),
          "modified" => filemtime($path),
        ];
      }
    }

    // pfSense's own helpers, in case one returns data rather than a rendered
    // graph. Probed, never called.
    $helpers = [];
    if (file_exists("/etc/inc/rrd.inc")) {
      require_once '/etc/inc/rrd.inc';
      foreach (["rrd_get_data", "get_rrd_data", "rrd_fetch_data"] as $fn) {
        if (function_exists($fn)) { $helpers[] = $fn; }
      }
    }

    $toreturn = [
      "extension_loaded" => $extension,
      "php_functions" => $functions,
      "pfsense_helpers" => $helpers,
      "rrd_inc_present" => file_exists("/etc/inc/rrd.inc"),
      "file_count" => count($files),
      "files" => $files,
    ];
    """)

    /// Historical throughput for every interface, from pfSense's own RRD files.
    ///
    /// pfSense records months of per-interface traffic in
    /// `/var/db/rrd/<iface>-traffic.rrd`, and this app has only ever shown
    /// what it watched since launch. That is the gap this closes — where it
    /// can be closed.
    ///
    /// RRD is a binary format normally read by `rrdtool`, a shell binary, and
    /// shelling out is what the snippet rules forbid. PHP can read it directly
    /// only with the `rrd` extension loaded, which is not standard on pfSense.
    /// The attempt is guarded: where `rrd_fetch` exists it is used, and where
    /// it does not the response says so rather than returning an empty series
    /// that looks like an interface with no traffic.
    ///
    /// Every interface at once, with no parameter, because a snippet is a
    /// constant — interpolating an interface name would mean assembling PHP at
    /// runtime, which is the one thing that would make the allowlist
    /// unreviewable.
    ///
    /// Downsampled to at most 120 points per series. A day at RRD's finest
    /// resolution is 1440 buckets per direction per interface, which is a
    /// megabyte of JSON to draw a line 200 points wide.
    static let rrdTraffic = PHPSnippet("rrd_traffic", """
    $available = function_exists("rrd_fetch");
    $rows = [];

    if ($available) {
      foreach (glob("/var/db/rrd/*-traffic.rrd") as $path) {
        $result = rrd_fetch($path, ["AVERAGE", "--start", "-86400", "--end", "now"]);
        if (!is_array($result) || !is_array($result["data"])) { continue; }

        foreach ($result["data"] as $series => $values) {
          if (!is_iterable($values)) { continue; }

          $points = [];
          foreach ($values as $when => $value) {
            // RRD writes NaN for gaps, which JSON cannot carry.
            if (!is_numeric($value)) { continue; }
            $points[] = ["at" => intval($when), "value" => floatval($value)];
          }

          $total = count($points);
          if ($total > 120) {
            $step = intval($total / 120);
            $thinned = [];
            foreach ($points as $index => $point) {
              if ($index % $step === 0) { $thinned[] = $point; }
            }
            $points = $thinned;
          }

          $rows[] = [
            "file" => basename($path, "-traffic.rrd"),
            "series" => strval($series),
            "points" => $points,
          ];
        }
      }
    }

    $toreturn = ["available" => $available, "data" => $rows];
    """)

    // MARK: - Firewall objects

    static let firewallRules = PHPSnippet("firewall_rules", """
    global $config;
    $filter = $config["filter"];
    $toreturn = ["data" => (is_array($filter) && is_iterable($filter["rule"])) ? $filter["rule"] : []];
    """)

    static let firewallAliases = PHPSnippet("firewall_aliases", """
    global $config;
    $aliases = $config["aliases"];
    $toreturn = ["data" => (is_array($aliases) && is_iterable($aliases["alias"])) ? $aliases["alias"] : []];
    """)

    static let portForwards = PHPSnippet("port_forwards", """
    global $config;
    $nat = $config["nat"];
    $toreturn = ["data" => (is_array($nat) && is_iterable($nat["rule"])) ? $nat["rule"] : []];
    """)

    // MARK: - High availability

    static let carp = PHPSnippet("carp", """
    require_once '/etc/inc/interfaces.inc';
    global $config;
    $vips = [];
    $virtualip = $config["virtualip"];
    if (is_array($virtualip) && is_iterable($virtualip["vip"])) {
      foreach ($virtualip["vip"] as $vip) {
        if (!is_array($vip) || $vip["mode"] != "carp") { continue; }
        $vip["status"] = get_carp_interface_status("_vip" . $vip["uniqid"]);
        $vips[] = $vip;
      }
    }
    $toreturn = ["enable" => get_carp_status() ? true : false, "interfaces" => $vips];
    """)

    // MARK: - Certificates

    static let certificates = PHPSnippet("certificates", """
    global $config;
    $rows = [];

    // Names ACME manages, so the general list can leave them to their own
    // screen. Matching in the app would need ACME loaded first, and the two
    // screens load independently.
    $acmeNames = [];
    $installed = $config["installedpackages"];
    $acme = is_array($installed) ? $installed["acme"] : "";
    if (is_array($acme)) {
      $certs = $acme["certificates"];
      if (is_array($certs) && is_iterable($certs["item"])) {
        foreach ($certs["item"] as $entry) {
          if (!is_array($entry)) { continue; }
          $acmeNames[] = strval($entry["name"]);
          $acmeNames[] = strval($entry["descr"]);
        }
      }
    }
    foreach (["cert", "ca"] as $section) {
      if (!is_iterable($config[$section])) { continue; }
      foreach ($config[$section] as $item) {
        if (!is_array($item) || !$item["crt"]) { continue; }
        $parsed = openssl_x509_parse(base64_decode($item["crt"]));
        if (!is_array($parsed)) { continue; }
        $rows[] = [
          "refid" => $item["refid"],
          "descr" => $item["descr"],
          "is_ca" => $section == "ca",
          "is_acme" => in_array(strval($item["descr"]), $acmeNames),
          "valid_from" => $parsed["validFrom_time_t"],
          "valid_until" => $parsed["validTo_time_t"],
        ];
      }
    }
    $toreturn = ["data" => $rows];
    """)

    // MARK: - Dynamic DNS
    //
    // The reason this transport exists. There is no REST endpoint for any of
    // this: the configuration lives in `$config` and the last address pushed
    // lives in a cache file per entry, so it can only be read by something
    // running on the firewall.

    static let dyndns = PHPSnippet("dyndns", """
    global $config;
    $rows = [];

    foreach (["dyndnses" => "dyndns", "dnsupdates" => "dnsupdate"] as $section => $key) {
      $conf = $config[$section];
      if (!is_array($conf) || !is_iterable($conf[$key])) { continue; }

      foreach ($conf[$key] as $entry) {
        if (!is_array($entry)) { continue; }

        $host = strval($entry["host"]);
        $domain = strval($entry["domain"]);
        $fqdn = ($domain !== "") ? $host . "." . $domain : $host;

        // The cache file holds "<address>|<unix time>", not just an address.
        // Reading it whole put "203.0.113.9|1788038229" on screen where an
        // address belonged, and threw away the timestamp the firewall had
        // already recorded — the modification time is when the file was
        // touched, which is not the same as when the address last changed.
        $cached = "";
        $when = 0;
        $best = "";
        foreach (glob("/conf/dyndns_*.cache") as $path) {
          $base = basename($path);
          // Prefer a file naming both host and domain; fall back to the host.
          if ($domain !== "" && strpos($base, $domain) !== false && strpos($base, $host) !== false) {
            $best = $path;
          } elseif ($best === "" && strpos($base, $host) !== false) {
            $best = $path;
          }
        }
        if ($best !== "") {
          $raw = trim(file_get_contents($best));
          $parts = explode("|", $raw);
          $cached = $parts[0];
          $when = (count($parts) > 1) ? intval($parts[1]) : filemtime($best);
        }

        $rows[] = [
          "host" => $fqdn,
          "type" => strval($entry["type"]),
          "interface" => strval($entry["interface"]),
          "descr" => strval($entry["descr"]),
          // pfSense stores this as an empty element when on, which reads as
          // false. Presence of the key is what means enabled; a disabled entry
          // has no key at all. Every entry showed DISABLED before this.
          "enabled" => array_key_exists("enable", $entry),
          "cached_address" => $cached,
          "updated_at" => $when,
        ];
      }
    }

    $toreturn = ["data" => $rows];
    """)

    // MARK: - Logs
    //
    // pfSense 2.5 and later write plain text logs, so these are read with
    // `file()` rather than shelling out to `clog`. `LogSource` is a closed enum
    // and the only thing that reaches the path — no interpolation of anything
    // a person typed.

    enum LogSource: String, CaseIterable {
        case filter, system, auth, dhcpd, openvpn

        var path: String {
            switch self {
            case .filter: return "/var/log/filter.log"
            case .system: return "/var/log/system.log"
            case .auth: return "/var/log/auth.log"
            case .dhcpd: return "/var/log/dhcpd.log"
            case .openvpn: return "/var/log/openvpn.log"
            }
        }
    }

    static func log(_ source: LogSource, limit: Int) -> PHPSnippet {
        // Both values are constrained here rather than trusted: the path comes
        // from the enum above, and the limit is clamped to a sane range and
        // rendered as an integer. Neither can carry anything else into the PHP.
        let capped = max(10, min(limit, 500))
        return PHPSnippet("log_\(source.rawValue)", """
        $path = "\(source.path)";
        $window = 262144;
        $rows = [];
        $size = file_exists($path) ? filesize($path) : -1;
        if ($size > 0) {
          // Only the tail. `file()` loads the entire log into an array, and a
          // busy filter log runs to tens of megabytes — enough to hit PHP's
          // memory limit, at which point the script dies and the result is
          // indistinguishable from an empty log.
          //
          // The read is clamped to the file size. A negative offset larger
          // than the file makes the seek fail and file_get_contents returns
          // false — so an unclamped window silently emptied every log smaller
          // than 256 KB, which on a normal firewall is all of them.
          $read = min($size, $window);
          $chunk = file_get_contents($path, false, null, -$read);
          if ($chunk !== false) {
            // Split on PHP_EOL, and note that nothing in this file may
            // contain a backslash escape.
            //
            // A Swift string literal processes escapes, so the text here and
            // the text the firewall receives are not the same thing. An escape
            // for a newline becomes an actual newline, which ends a PHP line
            // comment early and turns the rest of the sentence into code. That
            // is a parse error and an HTTP 500 — and it is exactly what the
            // first version of this comment did to itself.
            //
            // Constants avoid the whole class of problem. readonly.sh checks
            // the source file for backslashes, because by the time the string
            // exists at runtime the evidence has already been consumed.
            $lines = explode(PHP_EOL, $chunk);
            // Only a mid-file read starts on a fragment.
            if ($read < $size) { $lines = array_slice($lines, 1); }
            $rows = array_slice($lines, -\(capped));
          }
        }
        $toreturn = [
          "data" => array_values($rows),
          // Reported so an empty result can be told apart from a missing file.
          // Without these, "no such log" and "log has nothing in it" look the
          // same and neither says which.
          "path" => $path,
          "size" => $size,
        ];
        """)
    }

    /// Cheap call used to check credentials during onboarding.
    static let ping = PHPSnippet("ping", """
    $toreturn = ["version" => trim(file_get_contents("/etc/version"))];
    """)

    /// Every snippet, for the publish check to audit and for tests to cover.
    static var all: [PHPSnippet] {
        [telemetry, firmware, packages, packageUpdates, notices, interfaces, interfaceCounters, gateways, arpTable, dhcpLeases,
         staticMappings, hostOverrides, services, openvpnServers, openvpnClients, ipsecSAs,
         wireguard, pfTables, haproxy, acme, firewallRules, firewallAliases, portForwards, carp,
         certificates, dyndns, ping, rrdProbe, rrdTraffic,
         batchCore, batchClients, batchVpn, batchSystem]
        + LogSource.allCases.map { log($0, limit: 100) }
    }
}
