import Foundation

/// Every piece of PHP this app will ever send to a firewall.
///
/// This file is the security boundary. Under the REST transport the old
/// read-only guarantee was structural — the client had no write verb, and a
/// grep could prove it. `exec_php` has no such property: it runs whatever it is
/// given, so the mutation boundary has to come from this file instead.
///
/// The rules, enforced by `vaktpost-tools/tests/write-boundary.sh` on every publish:
///
///   1. Snippets are constants here. Nothing may build one by interpolating a
///      value at runtime — a snippet assembled from input is not a snippet
///      anybody reviewed.
///   2. A snippet may write **only** if its name appears in `writeOperations`
///      below, and then only through `write_config` and `write_filter`.
///      Everything else that can change a box — `mwexec`, `exec(`,
///      `shell_exec`, `system(`, `passthru`, `popen`, `proc_open`, `unlink`,
///      `file_put_contents`, `rename`, `mkdir`, `rmdir`, `chmod`, `chown`,
///      `fopen` in a write mode, `eval` — is forbidden everywhere, including
///      in the write snippets.
///   3. Only functions on the allowlist below may be called.
///
/// Rule 2 used to be "none may write", and for a long time that was true. When
/// the app gained an editor it stopped being true, and the gate was answered
/// with a `READONLY=0` switch that turned the whole suite off. That is the
/// worst available shape: the promise is not weakened, it is unobservable, and
/// a write added by accident looks exactly like the five added on purpose.
///
/// So the writes are named instead. The list below is the complete set of
/// operations this app can perform on a firewall. Adding to it is a one-line
/// change in a reviewed file, which is the point — it cannot happen quietly.
///
/// That is still a weaker guarantee than the REST client's. There, a violation
/// meant inventing a write verb that did not exist; here it means adding a
/// line. The check is real and runs in CI, but it is an allowlist somebody
/// could extend rather than an absence somebody would have to manufacture, and
/// that difference is worth being honest about.
///
/// Parameters are the sharp edge. Where a snippet needs one — a log file, a
/// line count — it is drawn from a closed enum here, never from user input.
/// String interpolation into PHP is how a read-only snippet becomes a shell.
struct PHPSnippet: Sendable {

    /// Every snippet permitted to change a firewall, by name.
    ///
    /// This is the app's complete write surface, and it is deliberately short
    /// enough to read. `write-boundary.sh` checks it in both directions: a snippet
    /// that writes and is not named here fails, and a name here whose snippet
    /// no longer writes fails too — so the list cannot quietly grow, and it
    /// cannot rot into a set of permissions nothing uses any more.
    ///
    /// Adding an entry is the moment to ask whether the operation belongs in
    /// an app that people point at production firewalls from a phone.
    static let writeOperations: Set<String> = [
        "reload_firewall",      // write_filter() — reloads the ruleset in place
        "quick_block",          // adds a block rule for one address
        "delete_rule",          // removes one filter rule by tracker
        "delete_nat_rule",      // removes one NAT rule by tracker
        "save_rule",            // replaces one filter rule by tracker
        "save_nat_rule",        // replaces one NAT rule
        "restart_service",      // restarts one named service
        "flush_states"          // drops the state table, or one interface's
    ]

    // The last two were not on this list when it was first written, and the
    // check found them. That is the argument for having it: the app's write
    // surface was believed to be six operations and was eight, and nothing
    // anywhere said so.
    //
    // The names these snippets carried made that worse — `delete_rule_\(tracker)`
    // and `save_nat_\(descr)` meant every call produced a different name, so
    // the write surface could not be enumerated by name at all. The tracker is
    // in the audit trail, which is where it belongs; the name identifies the
    // operation.

    /// A value on its way into a snippet, encoded so it cannot be read as code.
    ///
    /// This is the fix for the sharpest edge in the app. The write snippets
    /// interpolated their arguments straight into PHP source — a rule's
    /// description went into the middle of a double-quoted PHP string, and a
    /// description containing a quote ended that string. A description
    /// containing the right quote, a semicolon and a call ran it on the
    /// firewall, as root, from a text field in the editor.
    ///
    /// Base64 closes it structurally rather than by escaping. The alphabet is
    /// `A-Z a-z 0-9 + / =` and nothing in it can terminate a PHP string
    /// literal, so the snippet text stays exactly what was reviewed no matter
    /// what a person types. The snippet decodes it back into an array on the
    /// other side.
    ///
    /// Escaping would have been the obvious alternative and is the wrong one:
    /// it has to be right every time, in a language whose string rules differ
    /// from Swift's, and getting it wrong looks like working code.
    static func payload(_ value: JSONDict) -> String {
        let object = JSONValue.object(value.raw)
        guard let data = try? JSONEncoder().encode(object) else { return "" }
        return data.base64EncodedString()
    }

    /// The PHP that turns one of those back into an array.
    ///
    /// Kept here so every write snippet decodes it the same way, and so the
    /// name of the variable it lands in is the app's rather than a guess.
    static let decodePayload = """
    $vaktpost_input = json_decode(base64_decode($vaktpost_payload), true);
    if (!is_array($vaktpost_input)) { $vaktpost_input = []; }
    """

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
    /// Constrained by inspection. The publish check parses this list out of
    /// the source, so adding a call without adding it here fails rather than
    /// passing quietly. Write snippets still use only the explicitly audited
    /// pfSense mutation functions.
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
        // Resolving an interface to its device, and asking whether that device
        // is there. Both are lookups; neither brings an interface up or down.
        "get_real_interface", "does_interface_exist",
        "return_gateways_status", "return_gateways_array",
        "get_services", "get_service_status",
        "get_carp_status", "get_carp_interface_status",
        "openvpn_get_active_servers", "openvpn_get_active_clients",
        "wg_get_status",
        "ipsec_list_sa", "get_notices", "get_system_pkg_version",
        "openssl_x509_parse", "base64_decode", "in_array",
        "extension_loaded", "glob", "basename", "filemtime", "is_numeric", "is_finite",
        // Diagnostic reads: they describe an RRD file, they cannot change one.
        "rrd_last", "rrd_info", "rrd_xport", "gettype", "strpos", "time", "array_keys",
        // Reads an RRD file. There is no writing counterpart in any snippet.
        "rrd_fetch",
        // Probed with function_exists before use; see `pfTables`.
        "pfSense_get_pf_table", "pfr_get_table_addrs",
        // Sorts an array this snippet built itself, in place, by value. It
        // reads nothing and reaches nothing.
        "arsort",
        // Output buffering, so a pfSense function that echoes can be called
        // without its output landing in the XML-RPC response body.
        "ob_start", "ob_get_clean",
        // The one entry on this list that is not a counter read.
        //
        // `printBandwidth` shells out to `/usr/local/bin/rate` for a
        // one-second packet capture. Nothing in the branch this app takes
        // writes, deletes or reconfigures anything — the branch that does
        // (`mode == "iftop"`, which kills PIDs and unlinks logs) is reachable
        // only by passing a mode string the snippet never passes. But it is a
        // process spawn rather than a value read, it is the heaviest thing
        // this app asks of a firewall, and it should be argued for rather than
        // buried: it is exactly what status_graph.php does when that page is
        // open, and there is no other source for per-host rates on pfSense.
        "printBandwidth",
        // Removing one element from a local array, which is how a rule is
        // deleted from a copy before the copy is assigned back. Neither can
        // reach disk. `unset` pointed at `$config` would be a different thing
        // and `write-boundary.sh` fails on it separately.
        "array_filter", "unset",
        // Decoding a base64 payload back into an array. Neither reads a file
        // nor evaluates anything: `json_decode` is a parser, and the second
        // argument makes it return arrays rather than objects.
        "base64_decode", "json_decode",
        // The writes.
        //
        // Reachable only from the snippets named in `writeOperations` above —
        // `write-boundary.sh` fails if one of these appears anywhere else. They are
        // additionally gated in the app by the write rate limiter, a
        // confirmation step, and the audit trail.
        //
        // Listed once. They were here twice, from two separate edits, which is
        // how an allowlist stops being something anybody reads.
        "write_config", "write_filter", "pfctl_clear_states", "pfctl_clear_states_by_if",
        "restart_service",
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
    //
    // Per-core temperatures are read by probing dev.cpu.N.temperature for all
    // cores. The first valid reading is also used as the primary temp_c for
    // backward compatibility.
    $temp = null;
    $temp_source = "";
    $core_temps = [];
    $cpu_count = (int) get_cpu_count();
    if (function_exists("get_single_sysctl")) {
      // First, try to find the best single sensor (chipset > ACPI > first CPU).
      $probes = [
        "dev.pchtherm.0.temperature",
        "hw.acpi.thermal.tz0.temperature",
      ];
      foreach ($probes as $oid) {
        $reading = get_single_sysctl($oid);
        if ($reading !== "" && $reading !== null) {
          $temp = floatval($reading);
          $temp_source = $oid;
          break;
        }
      }
      // If no chipset/ACPI sensor, fall back to first CPU.
      if ($temp === null && $cpu_count > 0) {
        $firstCore = "dev.cpu.0.temperature";
        $reading = get_single_sysctl($firstCore);
        if ($reading !== "" && $reading !== null) {
          $temp = floatval($reading);
          $temp_source = $firstCore;
        }
      }
      // Read all core temperatures.
      for ($i = 0; $i < $cpu_count; $i++) {
        $oid = "dev.cpu.{$i}.temperature";
        $reading = get_single_sysctl($oid);
        if ($reading !== "" && $reading !== null) {
          $core_temps[] = ["core" => $i, "temp" => floatval($reading), "source" => $oid];
        }
      }
    }
    if ($temp === null) { $temp = get_temp(); }

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
      "temp_c" => ($temp === null || $temp === false) ? null : $temp,
      // Which sensor answered. A chipset runs far hotter than a CPU die, so
      // the same number means different things and needs a different label
      // and a different threshold.
      "temp_source" => $temp_source,
      // Per-core temperatures for multi-CPU systems.
      "core_temps" => $core_temps,
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
      // Whether the counters are there at all, said out loud.
      //
      // "No counters on this interface" and "no second sample yet" produce the
      // same empty chart, and the app spent a long session showing the second
      // message for the first condition. This flag is what tells them apart.
      //
      // There were two lines above this one assigning inbytes and outbytes to
      // themselves, under a comment about setting them from the same call the
      // counters snippet uses. It is the same call — get_interface_info() —
      // so the assignments did nothing whatsoever, and the comment described
      // an intent the code never had. Both are gone; the flag below is the
      // part that was doing the work.
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

    // MARK: - Host traffic
    //
    // What Status > Traffic Graph shows under the graph, taken from the same
    // place that page takes it.

    /// Which hosts to keep, matching the webConfigurator's own Filter control.
    ///
    /// The filter is not cosmetic. pfSense passes the interface's own subnet
    /// to `rate` for "local" and the whole of 0.0.0.0/0 otherwise, then keeps
    /// or drops each row by subnet membership. Local and remote are two
    /// different measurements, not two views of one.
    enum HostFilter: String, CaseIterable, Identifiable {
        case local, remote, all

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .local: return "Local"
            case .remote: return "Remote"
            case .all: return "All"
            }
        }
    }

    /// Which column pfSense sorts on before it truncates the list.
    ///
    /// This decides *which* hosts survive, not just their order — the sort
    /// happens inside `rate`, and only the top rows are printed. Sorting by
    /// outbound can therefore return a different set of hosts entirely.
    enum HostSort: String, CaseIterable, Identifiable {
        case inbound = "in", outbound = "out"

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .inbound: return "Bandwidth In"
            case .outbound: return "Bandwidth Out"
            }
        }
    }

    /// Per-host traffic for one interface.
    ///
    /// The previous version of this snippet read `ifhosttraffic` out of
    /// `get_interface_info()`. That key does not exist in pfSense 2.6, 2.7 or
    /// current, and by the look of it never did, which is why the screen was
    /// blank on every firewall it was ever pointed at and why `vaktpost-tools`
    /// accumulated six probes asking where the data was.
    ///
    /// It is in `printBandwidth()`, in `/usr/local/pfSense/include/www/
    /// bandwidth_by_ip.inc`, which is what `status_graph.php` polls every
    /// three seconds to fill its Host IP table. pfSense split that function
    /// into an include specifically so other processes could call it, and the
    /// signature has been unchanged since 2.6.
    ///
    /// Three things about it are worth knowing before reading the rest:
    ///
    ///   1. **It costs a one-second packet capture.** `printBandwidth` shells
    ///      out to `/usr/local/bin/rate`, a pcap-based analyser, and asks for
    ///      one report. There is no counter to read here the way there is for
    ///      interface bytes — the measurement has to be taken, and taking it
    ///      occupies the firewall for a second. This is the heaviest thing the
    ///      app asks of a firewall, and the reason the screen samples on
    ///      demand rather than on a timer.
    ///
    ///   2. **It is capped at ten rows**, by a loop bound inside pfSense. The
    ///      webConfigurator table has the same cap; this is not the app
    ///      truncating something the web UI shows in full.
    ///
    ///   3. **The numbers arrive as text with SI prefixes** — "1.20M", "842" —
    ///      because `rate` is invoked without its exact-values flag. They are
    ///      bits per second. Both the text and a parsed value are returned, so
    ///      a row that the parser does not understand can still be displayed
    ///      exactly as the firewall wrote it.
    ///
    /// `mode` is passed empty and must stay that way. The "iftop" branch of
    /// `printBandwidth` kills processes and unlinks files; the branch this
    /// takes only reads.
    ///
    /// The interface is chosen by position in `get_configured_interface_with_descr()`
    /// rather than by name. A name would mean interpolating a runtime string
    /// into PHP, which is the one thing this file promises not to do; an index
    /// is a clamped integer and the vocabulary is entirely pfSense's own
    /// interface list. The resolved key comes back in the result so the caller
    /// can check it got the interface it asked for — the `interfaces` snippet
    /// walks the same function in the same order, so the positions line up,
    /// but "should line up" is not a thing to rely on silently.
    static func hostTraffic(slot: Int, filter: HostFilter, sort: HostSort) -> PHPSnippet {
        // Clamped here rather than trusted. Sixty-four is well past any real
        // interface count and keeps the value a plain integer either way.
        let index = max(0, min(slot, 63))
        return PHPSnippet("host_traffic_\(filter.rawValue)_\(sort.rawValue)", """
        require_once '/etc/inc/interfaces.inc';
        $vaktpost_rows = [];
        $vaktpost_key = "";
        $vaktpost_descr = "";
        $vaktpost_raw = "";
        $vaktpost_device = "";
        $vaktpost_available = false;
        $vaktpost_reason = "";
        $vaktpost_slot = \(index);

        $vaktpost_map = get_configured_interface_with_descr();
        $vaktpost_keys = is_array($vaktpost_map) ? array_keys($vaktpost_map) : [];
        if (count($vaktpost_keys) > $vaktpost_slot) {
          $vaktpost_key = strval($vaktpost_keys[$vaktpost_slot]);
          $vaktpost_descr = strval($vaktpost_map[$vaktpost_key]);
        }

        if ($vaktpost_key !== "") {
          $vaktpost_device = strval(get_real_interface($vaktpost_key));
        }

        // Every failure gets its own sentence, and none of them is pfSense's.
        //
        // printBandwidth reports its two failures by echoing a phrase into the
        // output it otherwise fills with rows: one for an interface it could
        // not resolve, one for a capture that saw nothing. Both go through
        // gettext, so matching on them would work until somebody set the
        // webConfigurator to another language. Every condition that can be
        // established before the call is therefore established before the
        // call, and whatever the phrase turns out to be is left in "raw" for a
        // person to read rather than parsed for a decision.
        if ($vaktpost_key === "") {
          $vaktpost_reason = "This firewall has no interface in that position.";
        } else {
          if ($vaktpost_device === "" || !does_interface_exist($vaktpost_device)) {
            $vaktpost_reason = "pfSense has no device behind this interface at the moment, so there is nothing to capture on.";
          } else {
            if (!file_exists("/usr/local/pfSense/include/www/bandwidth_by_ip.inc")) {
              $vaktpost_reason = "This pfSense has no bandwidth_by_ip.inc, so per-host traffic cannot be sampled.";
            } else {
              require_once '/usr/local/pfSense/include/www/bandwidth_by_ip.inc';
              if (!function_exists("printBandwidth")) {
                $vaktpost_reason = "bandwidth_by_ip.inc is present but defines no printBandwidth.";
              } else {
                $vaktpost_available = true;
                // printBandwidth writes to standard output. Left unbuffered it
                // would land in the middle of the XML-RPC response body, and
                // the failure would read as a parse error rather than as
                // output.
                ob_start();
                printBandwidth($vaktpost_key, "\(filter.rawValue)", "\(sort.rawValue)", "", "");
                $vaktpost_raw = strval(ob_get_clean());
              }
            }
          }
        }

        // host;in;out|host;in;out| ... with a trailing separator.
        foreach (explode("|", $vaktpost_raw) as $vaktpost_part) {
          $vaktpost_part = trim($vaktpost_part);
          if ($vaktpost_part === "") { continue; }
          $vaktpost_fields = explode(";", $vaktpost_part);
          if (count($vaktpost_fields) < 3) { continue; }
          $vaktpost_rows[] = [
            "ip" => trim($vaktpost_fields[0]),
            "in_text" => trim($vaktpost_fields[1]),
            "out_text" => trim($vaktpost_fields[2]),
          ];
        }

        $toreturn = [
          "available" => $vaktpost_available,
          "interface" => $vaktpost_key,
          "descr" => $vaktpost_descr,
          "device" => $vaktpost_device,
          "slot" => $vaktpost_slot,
          "reason" => $vaktpost_reason,
          "raw" => $vaktpost_raw,
          "data" => array_values($vaktpost_rows),
        ];
        """)
    }

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

    /// pfBlockerNG: what it is blocking, and how much of it.
    ///
    /// The headline number a person wants from pfBlockerNG is how many
    /// addresses are currently blocked and which feed they came from. That is
    /// reachable without parsing anything the package writes: pfBlockerNG
    /// creates firewall aliases named `pfB_*`, and pf holds their contents as
    /// tables, which the app already has an accessor for.
    ///
    /// Counting from pf rather than from the package's own files is also the
    /// more honest number. A feed file on disk says what was downloaded; a pf
    /// table says what is actually loaded into the running firewall, and those
    /// differ whenever an update has been fetched but not applied.
    ///
    /// Everything else here is deliberately shallow. pfBlockerNG and
    /// pfBlockerNG-devel keep their logs and databases in different places
    /// under different names, and this app cannot tell which is installed
    /// without looking. So the paths are probed rather than assumed, and the
    /// result says which were found — enough for a screen to report the state
    /// of the package, and enough for `vaktpost-tools/bin/pfblocker-probe.sh`
    /// to establish what a particular firewall actually has before anything
    /// here starts parsing it.
    static let pfBlocker = PHPSnippet("pfblocker", """
    global $config;
    $installed = $config["installedpackages"];
    $pfb = is_array($installed) ? $installed["pfblockerng"] : "";

    // pfSense package settings live under a "config" list with one element.
    $settings = [];
    if (is_array($pfb)) {
      $list = $pfb["config"];
      if (is_array($list) && is_array($list[0])) { $settings = $list[0]; }
    }

    // DNSBL is a different package section entirely.
    //
    // `pfb_dnsbl` was read out of the main pfblockerng settings, where it does
    // not exist, so DNSBL always read as switched off — on a firewall whose
    // dnsbl.log was 52 KB and being written to that minute. pfBlockerNG keeps
    // it under `pfblockerngdnsblsettings`, which is where its own code looks:
    // `$pfb["dnsblconfig"] = config_get_path("installedpackages/pfblockerngdnsblsettings/config/0")`.
    $dnsblSettings = [];
    $dnsblSection = is_array($installed) ? $installed["pfblockerngdnsblsettings"] : "";
    if (is_array($dnsblSection)) {
      $dnsblList = $dnsblSection["config"];
      if (is_array($dnsblList) && is_array($dnsblList[0])) { $dnsblSettings = $dnsblList[0]; }
    }

    // Installed is a question about the filesystem, not the config: a removed
    // package can leave its settings behind, and a screen that reported it
    // installed on that basis would show zeros forever.
    $paths = [
      "pkg" => "/usr/local/pkg/pfblockerng/pfblockerng.inc",
      "logs" => "/var/log/pfblockerng",
      "db" => "/var/db/pfblockerng",
      "deny" => "/var/db/pfblockerng/deny",
      "dnsbl" => "/var/db/pfblockerng/dnsbl",
    ];
    $found = [];
    foreach ($paths as $label => $path) {
      $found[$label] = file_exists($path);
    }

    $logs = [];
    foreach (["pfblockerng.log", "ip_block.log", "dnsbl.log", "dns_reply.log", "unified.log"] as $name) {
      $path = "/var/log/pfblockerng/" . $name;
      if (!file_exists($path)) { continue; }
      $logs[] = [
        "name" => $name,
        "bytes" => filesize($path),
        // When it was last written. A DNSBL log that has not been touched in
        // a week is a DNSBL that is not running, and no count of its contents
        // says so as plainly.
        "updated" => filemtime($path),
      ];
    }

    // How many addresses each of pfBlockerNG's aliases holds.
    //
    // This asked pf directly, through `pfSense_get_pf_table` or
    // `pfr_get_table_addrs`, and on pfSense Plus neither function exists — so
    // every list reported "not loaded" on a firewall where every list was
    // loaded and working. The accessor is still tried, because where it does
    // exist it is the running state rather than a file on disk.
    //
    // Where it does not, the count comes from the same place pfSense's own
    // alias screens get it. A `urltable` alias keeps its addresses in
    // /var/db/aliastables/<name>.txt, which is the file pf is loaded from; the
    // other types keep theirs inline in the configuration. Neither is quite
    // "what pf holds" — a file written but not applied still counts — so the
    // result says which source answered, and the screen says so too.
    $accessor = "";
    if (function_exists("pfSense_get_pf_table")) { $accessor = "pfSense_get_pf_table"; }
    elseif (function_exists("pfr_get_table_addrs")) { $accessor = "pfr_get_table_addrs"; }

    $feeds = [];
    $aliases = $config["aliases"];
    $items = is_array($aliases) ? $aliases["alias"] : "";
    if (is_iterable($items)) {
      foreach ($items as $alias) {
        if (!is_array($alias)) { continue; }
        $name = strval($alias["name"]);
        if (substr($name, 0, 4) !== "pfB_") { continue; }

        $type = strval($alias["type"]);
        $count = -1;
        $source = "";

        if ($accessor === "pfSense_get_pf_table") {
          $entries = pfSense_get_pf_table($name);
          if (is_array($entries)) { $count = count($entries); $source = "pf"; }
        } elseif ($accessor === "pfr_get_table_addrs") {
          $entries = pfr_get_table_addrs($name);
          if (is_array($entries)) { $count = count($entries); $source = "pf"; }
        }

        if ($count < 0 && substr($type, 0, 8) === "urltable") {
          // The file pf is loaded from. One address per line, with comments.
          $file = "/var/db/aliastables/" . $name . ".txt";
          if (file_exists($file)) {
            $body = file_get_contents($file);
            if ($body !== false) {
              $n = 0;
              foreach (explode(PHP_EOL, $body) as $entry) {
                $entry = trim($entry);
                if ($entry === "") { continue; }
                if (substr($entry, 0, 1) === "#") { continue; }
                $n = $n + 1;
              }
              $count = $n;
              $source = "file";
            }
          }
        }

        if ($count < 0) {
          // Host, network and port aliases keep their members inline, space
          // separated. There is no table file and no pf table for a port
          // alias at all, so this is the only count there has ever been.
          $inline = trim(strval($alias["address"]));
          if ($inline !== "") {
            $n = 0;
            foreach (explode(" ", $inline) as $entry) {
              if (trim($entry) !== "") { $n = $n + 1; }
            }
            $count = $n;
            $source = "config";
          }
        }

        $feeds[] = [
          "name" => $name,
          "descr" => strval($alias["descr"]),
          "type" => $type,
          // Minus one where nothing could answer, which is different from a
          // list that holds nothing. A list configured but never downloaded
          // and a feed that legitimately matched nothing look the same as a
          // zero and are not the same thing.
          "entries" => $count,
          // Which of the three answered: the running firewall, the file it
          // loads from, or the configuration.
          "source" => $source,
        ];
      }
    }

    $toreturn = [
      "installed" => $found["pkg"] || $found["db"],
      "enabled" => strval($settings["enable_cb"]) === "on",
      "dnsbl" => strval($dnsblSettings["pfb_dnsbl"]) === "on",
      "dnsbl_mode" => strval($dnsblSettings["dnsbl_mode"]),
      "mode" => strval($settings["pfb_keep"]),
      "accessor" => $accessor,
      "paths" => $found,
      "logs" => $logs,
      "feeds" => $feeds,
    ];
    """)

    /// pfBlockerNG's DNSBL block statistics.
    ///
    /// The same numbers as `pfblockerng_alerts.php?view=dnsbl_stat`, computed
    /// from the same file. That page shells out to `cut | sort | uniq -c` over
    /// `/var/log/pfblockerng/dnsbl.log`; this reads the tail of the log and
    /// counts in PHP, which needs no process and no allowlist entry beyond a
    /// sort.
    ///
    /// The format is fixed and documented in pfBlockerNG's own source, as
    /// comma-separated fields written by `pfb_dnsbl_log`:
    ///
    ///     [0] prefix   DNSBL-python, DNSBL-Full, DNSBL-1x1, DNSBL-HTTPS
    ///     [1] date     `M j H:i:s` — "Sep 3 01:02:03", with no year
    ///     [2] domain   the name that was blocked
    ///     [3] source   the client that asked for it
    ///     [6] group    the group the feed belongs to
    ///     [8] feed     the list that matched
    ///
    /// Only the tail is read, for the reason the log snippet documents at
    /// length: a busy DNSBL log runs to tens of megabytes and `file()` would
    /// die on PHP's memory limit, which is indistinguishable from an empty
    /// log. So these counts are "the last megabyte of the log", not "today" —
    /// `truncated` says which, and the screen says so rather than implying a
    /// completeness it does not have.
    ///
    /// The date carries no year, so nothing here tries to build a `Date` from
    /// it. Hours are bucketed by their text and kept in the order the log has
    /// them, which is chronological because the file is append-only.
    static let dnsblStats = PHPSnippet("dnsbl_stats", """
    $path = "/var/log/pfblockerng/dnsbl.log";
    $window = 1048576;
    $total = 0;
    $skipped = 0;
    $read = 0;
    $byDomain = [];
    $byClient = [];
    $byGroup = [];
    $byFeed = [];
    $byHour = [];
    $first = "";
    $last = "";

    $size = file_exists($path) ? filesize($path) : -1;
    if ($size > 0) {
      $read = min($size, $window);
      $chunk = file_get_contents($path, false, null, -$read);
      if ($chunk !== false) {
        $lines = explode(PHP_EOL, $chunk);
        // Only a mid-file read starts on a fragment.
        if ($read < $size) { $lines = array_slice($lines, 1); }

        foreach ($lines as $line) {
          $line = trim($line);
          if ($line === "") { continue; }
          $f = explode(",", $line);
          // Nine fields is what a complete record has. Anything shorter is a
          // line still being written or a format this does not know, and it is
          // counted rather than guessed at.
          if (count($f) < 9) { $skipped = $skipped + 1; continue; }

          $total = $total + 1;
          $when = trim($f[1]);
          if ($first === "") { $first = $when; }
          $last = $when;

          $domain = trim($f[2]);
          if ($domain !== "") {
            $byDomain[$domain] = isset($byDomain[$domain]) ? $byDomain[$domain] + 1 : 1;
          }
          $client = trim($f[3]);
          if ($client !== "") {
            $byClient[$client] = isset($byClient[$client]) ? $byClient[$client] + 1 : 1;
          }
          $group = trim($f[6]);
          if ($group !== "") {
            $byGroup[$group] = isset($byGroup[$group]) ? $byGroup[$group] + 1 : 1;
          }
          $feed = trim($f[8]);
          if ($feed !== "") {
            $byFeed[$feed] = isset($byFeed[$feed]) ? $byFeed[$feed] + 1 : 1;
          }

          // "Sep 3 01:02:03" to "Sep 3 01". Built from the text rather than
          // parsed: the timestamp has no year, so anything that turned it into
          // a date would be inventing one.
          $parts = explode(" ", $when);
          if (count($parts) >= 3) {
            $hour = $parts[0] . " " . $parts[1] . " " . substr($parts[2], 0, 2);
            $byHour[$hour] = isset($byHour[$hour]) ? $byHour[$hour] + 1 : 1;
          }
        }
      }
    }

    arsort($byDomain);
    arsort($byClient);
    arsort($byGroup);
    arsort($byFeed);

    $domains = [];
    $n = 0;
    foreach ($byDomain as $k => $v) {
      if ($n >= 20) { break; }
      $domains[] = ["name" => $k, "count" => $v];
      $n = $n + 1;
    }
    $clients = [];
    $n = 0;
    foreach ($byClient as $k => $v) {
      if ($n >= 12) { break; }
      $clients[] = ["name" => $k, "count" => $v];
      $n = $n + 1;
    }
    $groups = [];
    $n = 0;
    foreach ($byGroup as $k => $v) {
      if ($n >= 12) { break; }
      $groups[] = ["name" => $k, "count" => $v];
      $n = $n + 1;
    }
    $feeds = [];
    $n = 0;
    foreach ($byFeed as $k => $v) {
      if ($n >= 12) { break; }
      $feeds[] = ["name" => $k, "count" => $v];
      $n = $n + 1;
    }

    // Insertion order, which is the order the log has them, which is
    // chronological. Sorting these by name would put "Sep 9" before "Sep 10".
    $hours = [];
    foreach ($byHour as $k => $v) {
      $hours[] = ["label" => $k, "count" => $v];
    }
    $hours = array_slice($hours, -24);

    $toreturn = [
      "available" => $size > 0,
      "bytes" => $size,
      "scanned" => $read,
      // True when the log is larger than the window, so the screen can say
      // these counts are the recent tail rather than everything.
      "truncated" => $size > $window,
      "events" => $total,
      "unparsed" => $skipped,
      "first" => $first,
      "last" => $last,
      "domains" => $domains,
      "clients" => array_values($clients),
      "groups" => array_values($groups),
      "feeds" => array_values($feeds),
      "hours" => array_values($hours),
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
    //
    // Per-core temperatures are read by probing dev.cpu.N.temperature for all
    // cores. The first valid reading is also used as the primary temp_c for
    // backward compatibility.
    $temp = null;
    $temp_source = "";
    $core_temps = [];
    $cpu_count = (int) get_cpu_count();
    if (function_exists("get_single_sysctl")) {
      // First, try to find the best single sensor (chipset > ACPI > first CPU).
      $probes = [
        "dev.pchtherm.0.temperature",
        "hw.acpi.thermal.tz0.temperature",
      ];
      foreach ($probes as $oid) {
        $reading = get_single_sysctl($oid);
        if ($reading !== "" && $reading !== null) {
          $temp = floatval($reading);
          $temp_source = $oid;
          break;
        }
      }
      // If no chipset/ACPI sensor, fall back to first CPU.
      if ($temp === null && $cpu_count > 0) {
        $firstCore = "dev.cpu.0.temperature";
        $reading = get_single_sysctl($firstCore);
        if ($reading !== "" && $reading !== null) {
          $temp = floatval($reading);
          $temp_source = $firstCore;
        }
      }
      // Read all core temperatures.
      for ($i = 0; $i < $cpu_count; $i++) {
        $oid = "dev.cpu.{$i}.temperature";
        $reading = get_single_sysctl($oid);
        if ($reading !== "" && $reading !== null) {
          $core_temps[] = ["core" => $i, "temp" => floatval($reading), "source" => $oid];
        }
      }
    }
    if ($temp === null) { $temp = get_temp(); }

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
      "temp_c" => ($temp === null || $temp === false) ? null : $temp,
      // Which sensor answered. A chipset runs far hotter than a CPU die, so
      // the same number means different things and needs a different label
      // and a different threshold.
      "temp_source" => $temp_source,
      // Per-core temperatures for multi-CPU systems.
      "core_temps" => $core_temps,
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
      // Whether the counters are there at all, said out loud.
      //
      // "No counters on this interface" and "no second sample yet" produce the
      // same empty chart, and the app spent a long session showing the second
      // message for the first condition. This flag is what tells them apart.
      //
      // There were two lines above this one assigning inbytes and outbytes to
      // themselves, under a comment about setting them from the same call the
      // counters snippet uses. It is the same call — get_interface_info() —
      // so the assignments did nothing whatsoever, and the comment described
      // an intent the code never had. Both are gone; the flag below is the
      // part that was doing the work.
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
    /// How far back to read.
    ///
    /// pfSense keeps years of these — its own page offers up to four — and the
    /// app was asking for one fixed span. The interesting question changes
    /// with the span: an evening's shape, a working week, a month's growth.
    enum RRDWindow: String, CaseIterable, Identifiable {
        case eightHours = "8h", day = "24h", week = "week", month = "month", year = "year"

        var id: String { rawValue }

        /// Seconds, as an integer this file controls. Nothing a caller passes
        /// reaches the PHP — the enum is the whole vocabulary.
        var seconds: Int {
            switch self {
            case .eightHours: return 28_800
            case .day: return 86_400
            case .week: return 604_800
            case .month: return 2_592_000
            case .year: return 31_536_000
            }
        }

        /// The next span up, for widening past a gap.
        var next: RRDWindow? {
            switch self {
            case .eightHours: return .day
            case .day: return .week
            case .week: return .month
            case .month: return .year
            case .year: return nil
            }
        }

        var displayName: String {
            switch self {
            case .eightHours: return "8 hours"
            case .day: return "Day"
            case .week: return "Week"
            case .month: return "Month"
            case .year: return "Year"
            }
        }
    }

    static func rrdTraffic(_ window: RRDWindow) -> PHPSnippet {
        // The span comes from the enum above and is rendered as an integer, so
        // the only thing varying between these is a number this file chose.
        PHPSnippet("rrd_traffic_\(window.rawValue)", """
    $available = function_exists("rrd_fetch");
    $rows = [];

    if ($available) {
      foreach (glob("/var/db/rrd/*-traffic.rrd") as $path) {
        // When the file was last written, carried with the data.
        //
        // Every value in a day coming back unknown has one dull explanation
        // that no amount of reading the fetch will reveal: the file is not
        // being updated. `rrd_last` says so in one number, and asking for it
        // here saves the person running a separate tool to find out.
        $last = function_exists("rrd_last") ? intval(rrd_last($path)) : 0;
        $age = $last > 0 ? (time() - $last) : -1;
        // Five-minute resolution first, then whatever the defaults give.
        //
        // pfSense's own Status → Monitoring draws a full day from these files
        // at "Resolution: 5 Minutes", while a default fetch of the same file
        // returned nothing but NaN. The finest archive is not the one holding
        // the day: rrdtool picks an RRA to satisfy the request, and asking
        // without a resolution asked for one that has no data in it.
        //
        // So this asks for what the firewall's own page asks for, and falls
        // back only if that comes up empty. Two fetches per file is more work
        // than one, and this runs on demand rather than on the refresh timer.
        // `rrd_fetch` only, for now.
        //
        // The `rrd_xport` path returned HTTP 502 — the request died rather
        // than failing — and it did so again after being guarded on the file
        // declaring the data sources it asks for. Something in that call takes
        // the process down on this firewall, and the app has no business
        // finding out which part on a live box every thirty seconds.
        //
        // So the refresh takes the call that is known not to crash, even
        // though it returns unknowns here. An empty chart is a poor result; an
        // empty chart plus a web server that stops answering is a much worse
        // one, and this app is a monitor — it should be the last thing to
        // disturb the thing it watches.
        //
        // `vaktpost-tools/bin/rrd-probe.sh` establishes what this extension
        // will actually take, one isolated call at a time. When that says
        // which call works, it comes back here.
        // A week, not a day.
        //
        // Every 24-hour window returns nothing but unknowns on this firewall,
        // and a week returns real values — 320 of them, starting
        // `inpass=814758.67`. The traffic files stopped being written about a
        // day ago, so a day-long window lands entirely inside the gap while a
        // week reaches back past it to the data that is there.
        //
        // Asking for a week regardless is also the more honest default: if the
        // recording resumes, this shows the recent data and the gap behind it,
        // which is exactly what somebody wants to see after an outage.
        $result = rrd_fetch($path, ["AVERAGE", "-s", "-\(window.seconds)"]);
        $resolution_used = 0;

        if (!is_array($result) || !is_array($result["data"])) { continue; }

        foreach ($result["data"] as $series => $values) {
          if (!is_iterable($values)) { continue; }

          $points = [];
          foreach ($values as $when => $value) {
            // RRD writes NaN for gaps, and `is_numeric(NAN)` is true in PHP
            // while `json_encode` fails outright on it — returning false for
            // the whole document, not just that value. The wrapper then sends
            // a boolean where a JSON string belongs and the app reports a
            // response that was not XML-RPC, which is a long way from "one
            // sample was missing".
            //
            // `is_finite` is the check that actually excludes it, and INF
            // with it.
            if (!is_numeric($value)) { continue; }
            if (!is_finite(floatval($value))) { continue; }
            $points[] = ["at" => intval($when), "value" => floatval($value)];
          }

          // Counted before filtering, so the app can tell "nothing was
          // recorded" from "everything was rejected on the way in".
          $seen = is_iterable($values) ? count($values) : 0;
          $kept = count($points);

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
            "last_update" => $last,
            "age_seconds" => $age,
            "resolution" => $resolution_used,
            "series" => strval($series),
            "values_seen" => $seen,
            "values_kept" => $kept,
            "points" => $points,
          ];
        }
      }
    }

    $toreturn = ["available" => $available, "data" => $rows];
    """)
    }


    /// What `rrd_fetch` actually hands back, for one file.
    ///
    /// The app reports 207,504 values offered and none numeric — so the fetch
    /// works, the structure parses, and every value inside fails
    /// `is_numeric` or `is_finite`. That narrows it to the values themselves,
    /// and no amount of reading the code from here will say what they are.
    ///
    /// This returns their PHP types and a few of them as strings, plus what
    /// the file says about itself: its step, when it was last updated, and
    /// which archives it keeps. A file whose last update is hours old explains
    /// an all-unknown window on its own.
    ///
    /// Diagnostic only — not called by the app, run from `bin/rrd-trace.sh`.
    static let rrdTrace = PHPSnippet("rrd_trace", """
    $available = function_exists("rrd_fetch");
    $toreturn = ["available" => $available];

    if ($available) {
      $files = glob("/var/db/rrd/*-traffic.rrd");

      // The WAN file, not whichever sorts first.
      //
      // Alphabetical order put `ipsec-traffic.rrd` first — an interface that
      // may carry no traffic at all — so the trace described the least
      // representative file on the firewall. The uplink is the one somebody
      // is asking about.
      $path = "";
      foreach ($files as $candidate) {
        if (strpos(basename($candidate), "wan") === 0) { $path = $candidate; break; }
      }
      if ($path === "" && count($files) > 0) { $path = $files[0]; }
      $toreturn["file"] = $path;

      // Every file's age, so one stale file is not mistaken for a stale
      // firewall, or the other way round.
      $ages = [];
      if (function_exists("rrd_last")) {
        foreach ($files as $candidate) {
          $ages[] = [
            "file" => basename($candidate, "-traffic.rrd"),
            "age_seconds" => time() - intval(rrd_last($candidate)),
          ];
        }
      }
      $toreturn["all_ages"] = $ages;

      if ($path !== "") {
        // What the file believes about itself.
        if (function_exists("rrd_last")) {
          $last = rrd_last($path);
          $toreturn["last_update"] = intval($last);
          $toreturn["last_update_age_seconds"] = time() - intval($last);
        }
        if (function_exists("rrd_info")) {
          $info = rrd_info($path);
          $keys = [];
          if (is_array($info)) {
            foreach ($info as $key => $value) {
              // Step, DS names and RRA definitions; the rest is noise.
              if (strpos($key, "step") !== false
                  || strpos($key, "ds[") !== false
                  || strpos($key, "rra[") !== false) {
                $keys[] = $key . " = " . strval($value);
              }
            }
          }
          $toreturn["info"] = array_slice($keys, 0, 40);
        }

        // Both calls, so the trace shows the difference rather than only
        // whichever the app currently prefers.
        $result = rrd_fetch($path, ["AVERAGE"]);
        $toreturn["fetch_keys"] = is_array($result) ? array_keys($result) : [];

        // Same guard as the real snippet: a DEF naming a data source the file
        // does not have takes the whole request down with it, and a trace that
        // crashes the thing it is tracing is worse than no trace.
        $trace_has_in = false;
        if (function_exists("rrd_info")) {
          $trace_info = rrd_info($path);
          $trace_has_in = is_array($trace_info)
            && array_key_exists("ds[inpass].index", $trace_info);
        }
        $toreturn["has_inpass"] = $trace_has_in;

        if ($trace_has_in && function_exists("rrd_xport")) {
          $xp = rrd_xport([
            "--start", "-86400", "--end", "-60", "--step", "300",
            "DEF:in=" . $path . ":inpass:AVERAGE",
            "XPORT:in:inpass",
          ]);
          $xp_numeric = 0;
          $xp_total = 0;
          if (is_array($xp) && is_array($xp["data"])) {
            foreach ($xp["data"] as $one) {
              if (!is_array($one) || !is_array($one["data"])) { continue; }
              foreach ($one["data"] as $value) {
                $xp_total = $xp_total + 1;
                if (is_numeric($value) && is_finite(floatval($value))) {
                  $xp_numeric = $xp_numeric + 1;
                }
              }
            }
          }
          $toreturn["xport_values"] = $xp_total;
          $toreturn["xport_numeric"] = $xp_numeric;
        }
        $toreturn["fetch_start"] = is_array($result) ? strval($result["start"]) : "";
        $toreturn["fetch_end"] = is_array($result) ? strval($result["end"]) : "";
        $toreturn["fetch_step"] = is_array($result) ? strval($result["step"]) : "";

        $samples = [];
        if (is_array($result) && is_array($result["data"])) {
          foreach ($result["data"] as $ds => $values) {
            if (!is_iterable($values)) {
              $samples[] = ["ds" => strval($ds), "type" => gettype($values)];
              continue;
            }
            // The first few values with their types: a float NAN, the string
            // "nan", and null are three different problems.
            $shown = [];
            $count = 0;
            foreach ($values as $when => $value) {
              $shown[] = [
                "at" => strval($when),
                "type" => gettype($value),
                "as_string" => strval($value),
                "is_numeric" => is_numeric($value),
              ];
              $count = $count + 1;
              if ($count >= 5) { break; }
            }
            $samples[] = [
              "ds" => strval($ds),
              "count" => count($values),
              "first" => $shown,
            ];
          }
        }
        $toreturn["series"] = array_slice($samples, 0, 3);
      }
    }
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
            // Constants avoid the whole class of problem. write-boundary.sh checks
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

    /// Reloads the firewall ruleset without restarting services.
    ///
    /// Calls `write_filter()` which reloads the pf ruleset in place.
    static let reloadFirewall = PHPSnippet("reload_firewall", """
    ini_set('display_errors', 0);
    require_once '/etc/inc/filter.inc';
    write_filter();
    $toreturn = ["status" => "ok"];
    """)

    /// Restarts a pfSense service by name.
    ///
    /// - Parameter serviceName: The service name (e.g. "dnsresolver", "dhcpd").
    static func restartService(serviceName: String) -> PHPSnippet {
        let encoded = payload(JSONDict(["name": .string(serviceName)]))
        return PHPSnippet("restart_service", """
        ini_set('display_errors', 0);
        $toreturn = [];
        $vaktpost_payload = "\(encoded)";
        \(decodePayload)
        $vaktpost_name = strval($vaktpost_input["name"] ?? "");
        if ($vaktpost_name !== "" && function_exists('restart_service')) {
          $result = restart_service($vaktpost_name);
          $toreturn["status"] = $result ? "ok" : "failed";
        } else {
          $toreturn["status"] = "service_not_found";
          $toreturn["error"] = "restart_service function not available";
        }
        """)
    }

    /// Adds a quick-block rule to block an IP address on a specific interface.
    ///
    /// - Parameters:
    ///   - interface: The interface to block on (e.g. "wan", "lan").
    ///   - address: The IP address or subnet to block.
    ///   - description: A description for the rule.
    static func quickBlock(interface: String, address: String, description: String) -> PHPSnippet {
        let encoded = payload(JSONDict([
            "interface": .string(interface),
            "address": .string(address),
            "descr": .string(description)
        ]))
        return PHPSnippet("quick_block", """
        ini_set('display_errors', 0);
        require_once '/etc/inc/util.inc';
        require_once '/etc/inc/filter.inc';
        $toreturn = [];
        $vaktpost_payload = "\(encoded)";
        \(decodePayload)
        $vaktpost_if = strval($vaktpost_input["interface"] ?? "");
        $vaktpost_addr = strval($vaktpost_input["address"] ?? "");
        if ($vaktpost_if === "" || $vaktpost_addr === "") {
          $toreturn["status"] = "invalid";
          $toreturn["error"] = "Interface and address are required";
        } else {
          $section = $config["filter"];
          $vaktpost_rules = (is_array($section) && is_iterable($section["rule"])) ? $section["rule"] : [];
          $vaktpost_tracker = strval(time());
          $vaktpost_collision = true;
          while ($vaktpost_collision) {
            $vaktpost_collision = false;
            foreach ($vaktpost_rules as $vaktpost_existing) {
              if (is_array($vaktpost_existing) && strval($vaktpost_existing["tracker"] ?? "") === $vaktpost_tracker) {
                $vaktpost_tracker = strval(intval($vaktpost_tracker) + 1);
                $vaktpost_collision = true;
                break;
              }
            }
          }
          $vaktpost_source = (strpos($vaktpost_addr, "/") !== false)
            ? ["network" => $vaktpost_addr]
            : ["address" => $vaktpost_addr];
          $block_rule = [
            'type' => 'block',
            'interface' => $vaktpost_if,
            'descr' => strval($vaktpost_input["descr"] ?? ""),
            'ipprotocol' => (strpos($vaktpost_addr, ":") !== false) ? 'inet6' : 'inet',
            'protocol' => 'any',
            'source' => $vaktpost_source,
            'destination' => ['any' => true],
            'tracker' => $vaktpost_tracker,
          ];
          $vaktpost_rules[] = $block_rule;
          $config['filter']['rule'] = array_values($vaktpost_rules);
          write_config("Vaktpost: quick-block rule added");
          write_filter();
          $toreturn["status"] = "ok";
          $toreturn["rule"] = $block_rule;
        }
        """)
    }

    /// Flushes the firewall state table.
    ///
    /// - Parameter interface: Optional interface to flush states for. Empty means all interfaces.
    static func flushStates(interface: String = "") -> PHPSnippet {
        let encoded = payload(JSONDict(["interface": .string(interface)]))
        return PHPSnippet("flush_states", """
        ini_set('display_errors', 0);
        require_once '/etc/inc/filter.inc';
        $toreturn = [];
        $vaktpost_payload = "\(encoded)";
        \(decodePayload)
        $vaktpost_if = strval($vaktpost_input["interface"] ?? "");
        if ($vaktpost_if === "") {
          pfctl_clear_states();
          $toreturn["scope"] = "all";
        } else {
          pfctl_clear_states_by_if($vaktpost_if);
          $toreturn["scope"] = $vaktpost_if;
        }
        $toreturn["status"] = "ok";
        """)
    }

    static func deleteRule(tracker: String) -> PHPSnippet {
        let encoded = payload(JSONDict(["tracker": .string(tracker)]))
        return PHPSnippet("delete_rule", """
        ini_set('display_errors', 0);
        require_once '/etc/inc/util.inc';
        require_once '/etc/inc/filter.inc';
        $toreturn = [];
        $vaktpost_payload = "\(encoded)";
        \(decodePayload)
        $tracker = strval($vaktpost_input["tracker"] ?? "");
        $section = $config["filter"];
        $rules = (is_array($section) && is_iterable($section["rule"])) ? $section["rule"] : [];
        $found = false;
        if ($tracker !== "") {
          foreach ($rules as $idx => $rule) {
            if (is_array($rule) && ($rule["tracker"] ?? "") === $tracker) {
              unset($rules[$idx]);
              $found = true;
              break;
            }
          }
        }
        if ($found) {
          $config["filter"]["rule"] = array_values($rules);
          // The tracker is no longer spliced into this message. It came from
          // the caller and went straight into a PHP string literal, which is
          // the same hole as everywhere else; the audit trail records which
          // rule went, which is where that belongs.
          write_config("Vaktpost: deleted a rule");
          write_filter();
          $toreturn["status"] = "ok";
        } else {
          $toreturn["status"] = "not_found";
        }
        """)
    }

    /// Deletes a NAT/port forward rule by tracker ID.
    static func deleteNatRule(tracker: String) -> PHPSnippet {
        let encoded = payload(JSONDict(["tracker": .string(tracker)]))
        return PHPSnippet("delete_nat_rule", """
        ini_set('display_errors', 0);
        require_once '/etc/inc/util.inc';
        require_once '/etc/inc/filter.inc';
        $toreturn = [];
        $vaktpost_payload = "\(encoded)";
        \(decodePayload)
        $tracker = strval($vaktpost_input["tracker"] ?? "");
        $section = $config["nat"];
        $rules = (is_array($section) && is_iterable($section["rule"])) ? $section["rule"] : [];
        $found = false;
        if ($tracker !== "") {
          foreach ($rules as $idx => $rule) {
            if (is_array($rule) && ($rule["tracker"] ?? "") === $tracker) {
              unset($rules[$idx]);
              $found = true;
              break;
            }
          }
        }
        if ($found) {
          $config["nat"]["rule"] = array_values($rules);
          // The tracker is no longer spliced into this message. It came from
          // the caller and went straight into a PHP string literal, which is
          // the same hole as everywhere else; the audit trail records which
          // rule went, which is where that belongs.
          write_config("Vaktpost: deleted a nat rule");
          write_filter();
          $toreturn["status"] = "ok";
        } else {
          $toreturn["status"] = "not_found";
        }
        """)
    }

    /// Saves a firewall rule by tracker ID.
    ///
    /// The whole rule crosses as one encoded payload. It used to cross as a
    /// dozen interpolations *and three generated fragments of PHP* — the
    /// optional fields were assembled as source text, so the snippet's own
    /// shape depended on the values it carried. A description containing a
    /// double quote ended a PHP string literal; one containing the right
    /// characters ran as code, as root, typed into the editor.
    ///
    /// What is sent is now data, and the snippet below is fixed text that does
    /// the same thing whatever the data says.
    static func saveRule(rule: JSONDict) -> PHPSnippet {
        let encoded = payload(rule)
        return PHPSnippet("save_rule", """
        ini_set('display_errors', 0);
        require_once '/etc/inc/util.inc';
        require_once '/etc/inc/filter.inc';
        $toreturn = [];
        $vaktpost_payload = "\(encoded)";
        \(decodePayload)

        $tracker = strval($vaktpost_input["tracker"] ?? "");
        $vaktpost_create = ($vaktpost_input["create"] ?? false) ? true : false;
        $vaktpost_interface = strval($vaktpost_input["interface"] ?? "");
        $vaktpost_placement = strval($vaktpost_input["placement"] ?? ($vaktpost_create ? "last" : "keep"));
        $vaktpost_before = strval($vaktpost_input["before_tracker"] ?? "");
        $section = $config["filter"];
        $rules = (is_array($section) && is_iterable($section["rule"])) ? $section["rule"] : [];
        $found = false;
        $vaktpost_index = null;
        $rule = [];
        $vaktpost_position_valid = true;

        // Creating means never matching.
        //
        // The tracker is generated here rather than by the app, for the same
        // reason quick-block generates its own: the firewall is the only place
        // that can see the whole ruleset at the moment of writing. A tracker
        // picked on the phone against a list fetched thirty seconds ago can
        // collide with one added since — and a collision here does not append,
        // it silently replaces the rule that already had that tracker.
        if ($vaktpost_create) {
          $tracker = strval(time());
          $vaktpost_collision = true;
          while ($vaktpost_collision) {
            $vaktpost_collision = false;
            foreach ($rules as $vaktpost_existing) {
              if (is_array($vaktpost_existing) && strval($vaktpost_existing["tracker"] ?? "") === $tracker) {
                $tracker = strval(intval($tracker) + 1);
                $vaktpost_collision = true;
                break;
              }
            }
          }
        } elseif ($tracker !== "") {
          foreach ($rules as $idx => $r) {
            if (is_array($r) && ($r["tracker"] ?? "") === $tracker) {
              $rule = $r;
              $vaktpost_index = $idx;
              $found = true;
              break;
            }
          }
        }

        if ($vaktpost_placement !== "keep" && $vaktpost_placement !== "last" && $vaktpost_placement !== "before") {
          $vaktpost_position_valid = false;
        }
        if ($vaktpost_placement === "before") {
          $vaktpost_position_valid = $vaktpost_before !== "" && $vaktpost_before !== $tracker;
          if ($vaktpost_position_valid) {
            $vaktpost_anchor_found = false;
            foreach ($rules as $vaktpost_existing) {
              if (is_array($vaktpost_existing)
                  && strval($vaktpost_existing["tracker"] ?? "") === $vaktpost_before
                  && strval($vaktpost_existing["interface"] ?? "") === $vaktpost_interface) {
                $vaktpost_anchor_found = true;
                break;
              }
            }
            $vaktpost_position_valid = $vaktpost_anchor_found;
          }
        }
        if ($found && $vaktpost_placement === "keep"
            && strval($rule["interface"] ?? "") !== $vaktpost_interface) {
          // "Keep" is an interface-local promise. Once the interface changes
          // there is no current position there to preserve.
          $vaktpost_position_valid = false;
        }

        if (!$vaktpost_create && !$found) {
          // Never turn a stale edit into an append. The rule may have been
          // removed after the app's preflight read and before this write.
          $toreturn["status"] = "not_found";
          $toreturn["error"] = "The rule tracker no longer exists";
        } elseif (!$vaktpost_position_valid) {
          $toreturn["status"] = "position_not_found";
          $toreturn["error"] = "The selected rule position is no longer available";
        } else {
        $rule["interface"] = $vaktpost_interface;
        $rule["type"] = strval($vaktpost_input["type"] ?? "pass");
        $rule["protocol"] = strval($vaktpost_input["protocol"] ?? "any");
        $rule["ipprotocol"] = strval($vaktpost_input["ipprotocol"] ?? "inet");
        $rule["descr"] = strval($vaktpost_input["descr"] ?? "");
        $rule["disabled"] = ($vaktpost_input["disabled"] ?? false) ? true : false;
        $rule["log"] = ($vaktpost_input["log"] ?? false) ? true : false;
        if (!$found) {
          // An append keeps a stable identity so it can be read back, edited
          // and removed. An untracked rule cannot be found again by any of the
          // operations that work by tracker.
          $rule["tracker"] = $tracker;
        }

        $vaktpost_src = $vaktpost_input["source"] ?? [];
        $vaktpost_dst = $vaktpost_input["destination"] ?? [];
        $rule["source"] = ["address" => strval(is_array($vaktpost_src) ? ($vaktpost_src["address"] ?? "any") : "any")];
        $rule["destination"] = ["address" => strval(is_array($vaktpost_dst) ? ($vaktpost_dst["address"] ?? "any") : "any")];

        // Absent means absent. A port key left behind with an empty value is a
        // rule pfSense reads differently from one without the key at all.
        $vaktpost_sport = strval($vaktpost_input["source_port"] ?? "");
        if ($vaktpost_sport !== "") {
          $rule["source_port"] = $vaktpost_sport;
        } else {
          unset($rule["source_port"]);
        }
        $vaktpost_dport = strval($vaktpost_input["destination_port"] ?? "");
        if ($vaktpost_dport !== "") {
          $rule["destination_port"] = $vaktpost_dport;
        } else {
          unset($rule["destination_port"]);
        }

        if ($found && $vaktpost_placement === "keep") {
          $rules[$vaktpost_index] = $rule;
        } else {
          if ($found) {
            unset($rules[$vaktpost_index]);
            $rules = array_values($rules);
          }
          if ($vaktpost_placement === "before") {
            $vaktpost_ordered = [];
            $vaktpost_inserted = false;
            foreach ($rules as $vaktpost_existing) {
              if (!$vaktpost_inserted && is_array($vaktpost_existing)
                  && strval($vaktpost_existing["tracker"] ?? "") === $vaktpost_before
                  && strval($vaktpost_existing["interface"] ?? "") === $vaktpost_interface) {
                $vaktpost_ordered[] = $rule;
                $vaktpost_inserted = true;
              }
              $vaktpost_ordered[] = $vaktpost_existing;
            }
            $rules = $vaktpost_ordered;
          } else {
            $rules[] = $rule;
          }
        }
        $config["filter"]["rule"] = array_values($rules);
        write_config("Vaktpost: saved a rule");
        write_filter();
        $toreturn["status"] = "ok";
        $toreturn["created"] = $vaktpost_create;
        $toreturn["tracker"] = $tracker;
        $toreturn["placement"] = $vaktpost_placement;
        if ($vaktpost_placement === "before") {
          $toreturn["before_tracker"] = $vaktpost_before;
        }
        }
        """)
    }

    /// Saves a NAT/port forward rule.
    ///
    /// Same treatment as `saveRule`, and it had the same hole.
    ///
    /// It also only ever appended. Editing a forward added a second one with
    /// the same description and left the original in place, so "save" grew the
    /// NAT table by one every time it was pressed.
    ///
    /// Existing forwards are matched only by their pfSense tracker. An edit
    /// whose tracker disappeared is rejected rather than becoming an append.
    static func saveNatRule(rule: JSONDict) -> PHPSnippet {
        let encoded = payload(rule)
        return PHPSnippet("save_nat_rule", """
        ini_set('display_errors', 0);
        require_once '/etc/inc/util.inc';
        require_once '/etc/inc/filter.inc';
        $toreturn = [];
        $vaktpost_payload = "\(encoded)";
        \(decodePayload)

        $section = $config["nat"];
        $rules = (is_array($section) && is_iterable($section["rule"])) ? $section["rule"] : [];

        $tracker = strval($vaktpost_input["tracker"] ?? "");
        $vaktpost_if = strval($vaktpost_input["interface"] ?? "");
        $vaktpost_target = strval($vaktpost_input["target"] ?? "");
        $vaktpost_dst = $vaktpost_input["destination"] ?? [];
        $vaktpost_dstaddr = strval(is_array($vaktpost_dst) ? ($vaktpost_dst["address"] ?? "any") : "any");
        // The port is part of what identifies a forward.
        //
        // Without it, two forwards to the same host on the same interface —
        // 80 and 443 to 10.0.0.5, which is an ordinary pair — have identical
        // interface, destination and target, so editing one replaced the
        // other. `PortForward.id` in the app has always included the port;
        // this had dropped it.
        $vaktpost_dstport = strval($vaktpost_input["destination_port"] ?? "");

        $vaktpost_create = ($vaktpost_input["create"] ?? false) ? true : false;
        $found = false;
        $vaktpost_index = null;
        $rule = [];
        if ($vaktpost_create) {
          // Allocate on the firewall, against the current NAT table. A value
          // chosen by the phone could collide with a rule added since refresh.
          $tracker = strval(time());
          $vaktpost_collision = true;
          while ($vaktpost_collision) {
            $vaktpost_collision = false;
            foreach ($rules as $vaktpost_existing) {
              if (is_array($vaktpost_existing) && strval($vaktpost_existing["tracker"] ?? "") === $tracker) {
                $tracker = strval(intval($tracker) + 1);
                $vaktpost_collision = true;
                break;
              }
            }
          }
        }
        // Creating means never matching. In particular, a duplicate must not
        // match the tracker of the forward it was copied from.
        foreach (($vaktpost_create ? [] : $rules) as $idx => $r) {
          if (!is_array($r)) { continue; }
          $vaktpost_match = $tracker !== "" && strval($r["tracker"] ?? "") === $tracker;
          if ($vaktpost_match) {
            $rule = $r;
            $vaktpost_index = $idx;
            $found = true;
            break;
          }
        }

        if (!$vaktpost_create && !$found) {
          $toreturn["status"] = "not_found";
          $toreturn["error"] = "The port-forward tracker no longer exists";
        } else {
        $rule["interface"] = $vaktpost_if;
        $rule["protocol"] = strval($vaktpost_input["protocol"] ?? "any");
        $rule["ipprotocol"] = strval($vaktpost_input["ipprotocol"] ?? "inet");
        $rule["target"] = $vaktpost_target;
        $rule["descr"] = strval($vaktpost_input["descr"] ?? "");
        $rule["disabled"] = ($vaktpost_input["disabled"] ?? false) ? true : false;
        if (!$found) {
          $rule["tracker"] = $tracker;
        }

        $vaktpost_src = $vaktpost_input["source"] ?? [];
        $rule["source"] = ["address" => strval(is_array($vaktpost_src) ? ($vaktpost_src["address"] ?? "any") : "any")];
        $rule["destination"] = ["address" => $vaktpost_dstaddr];

        $vaktpost_dport = strval($vaktpost_input["destination_port"] ?? "");
        if ($vaktpost_dport !== "") {
          $rule["destination_port"] = $vaktpost_dport;
        } else {
          unset($rule["destination_port"]);
        }
        $vaktpost_lport = strval($vaktpost_input["local_port"] ?? "");
        if ($vaktpost_lport !== "") {
          $rule["local_port"] = $vaktpost_lport;
        } else {
          unset($rule["local_port"]);
        }

        if ($found) {
          $rules[$vaktpost_index] = $rule;
        } else {
          $rules[] = $rule;
        }
        $config["nat"]["rule"] = array_values($rules);
        write_config("Vaktpost: saved a nat rule");
        write_filter();
        $toreturn["status"] = "ok";
        $toreturn["created"] = $vaktpost_create;
        $toreturn["tracker"] = $tracker;
        }
        """)
    }

    /// Every snippet, for the publish check to audit and for tests to cover.
    static var all: [PHPSnippet] {
        [telemetry, firmware, packages, packageUpdates, notices, interfaces, interfaceCounters, gateways, arpTable, dhcpLeases,
         staticMappings, hostOverrides, services, openvpnServers, openvpnClients, ipsecSAs,
         wireguard, pfTables, haproxy, acme, pfBlocker, dnsblStats, firewallRules, firewallAliases, portForwards, carp,
         certificates, dyndns, ping, rrdProbe, rrdTrace,
         batchCore, batchClients, batchVpn, batchSystem,
         reloadFirewall]
        + LogSource.allCases.map { log($0, limit: 100) }
        + RRDWindow.allCases.map { rrdTraffic($0) }
        + HostFilter.allCases.map { hostTraffic(slot: 0, filter: $0, sort: .inbound) }
    }
}
