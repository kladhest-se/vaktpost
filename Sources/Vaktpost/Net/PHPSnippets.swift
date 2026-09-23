import Foundation

// This file is deliberately kept as one security-audited boundary; see below.
// swiftlint:disable file_length type_body_length
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
///      below, and then only through `write_config`, a pfSense dirty marker,
///      or the explicitly requested `filter_configure_sync` apply operation.
///      The sole process-launch exception is `start_update`, which may invoke
///      only pfSense's own fixed background updater after validating its closed
///      firmware/package mode and package identifier. Everything else that can
///      change a box — `mwexec`, `exec(`,
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
///
/// This file is intentionally one file, and intentionally over SwiftLint's
/// size limits. `write-boundary.sh` (via `readonly.sh`) audits it with eleven
/// stateful awk/grep passes — tracking triple-quote nesting, `PHPSnippet(...)`
/// call boundaries and multi-line PHP bodies as one continuous stream — so
/// the complete write surface stays checkable, and reviewable, as a whole.
/// Splitting the struct across files would mean re-deriving all eleven checks
/// to track that same state correctly across file boundaries, where a mistake
/// is not a broken lint gate but a security check silently missing a real
/// vulnerability. That risk is not worth taking to satisfy a size rule.
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
        "reload_firewall",      // filter_configure_sync() — reloads the ruleset in place
        "quick_block",          // adds a block rule for one address
        "delete_rule",          // removes one filter rule by tracker
        "delete_nat_rule",      // removes one NAT rule by tracker
        "save_rule",            // replaces one filter rule by tracker
        "save_nat_rule",        // replaces one NAT rule
        "restart_service",      // restarts one named service
        "flush_states",         // drops the state table, or one interface's
        "reorder_filter_rules", // reorders one interface's rules and separators
        "reorder_nat_rules",    // reorders the complete flat NAT rule table
        "save_filter_separator",// creates or edits one filter separator
        "delete_filter_separator", // removes one filter separator
        "save_nat_separator",   // creates or edits one flat NAT separator
        "delete_nat_separator", // removes one flat NAT separator
        "save_alias",           // creates or edits one inline firewall alias
        "delete_alias",         // removes one unused firewall alias
        "start_update"          // starts pfSense's own background updater
    ]

    // Earlier operations were not on this list when it was first written,
    // and the check found them. That is the argument for having it: the app's
    // write surface was once believed to be six operations and was eight,
    // and nothing anywhere said so. New reorder and separator writes are now
    // explicit here at the moment they are introduced.
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
        "strtoupper", "strtolower",
        "array_key_exists", "intval",
        // Pure, built-in string conversion — no side effects, no file or
        // system access. Used once, to show a submitted interface value as
        // hex in a diagnostic message, since a value that looks identical to
        // "opt5" printed as text could still differ from it byte for byte.
        "bin2hex",
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
        // Native pfSense validators used by the two administrative rule-save
        // snippets before they touch `$config`.
        "get_specialnet", "is_ipaddroralias", "is_ipaddrv4", "is_ipaddrv6",
        "is_subnet", "is_iprange", "is_fqdn",
        "is_port_or_alias", "is_port_or_range_or_alias", "is_alias_inuse",
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
        // Comparing two local arrays of plain strings — this app's own
        // decoded rule trackers and separator keys against pfSense's own —
        // to prove a submitted reorder is an exact permutation before
        // anything is written. It reads two values it already has and
        // returns a third; it touches neither `$config` nor disk.
        "array_diff",
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
        "write_config", "mark_subsystem_dirty", "clear_subsystem_dirty", "filter_configure_sync",
        "pfctl_clear_states", "pfctl_clear_states_by_if",
        "auth_get_authserver",
        "session_status", "session_start", "session_destroy", "is_subsystem_dirty",
        "restart_service",
        // The only process launcher in the boundary. `write-boundary.sh`
        // permits these only inside `start_update`, whose command path and
        // flags are fixed and whose sole value argument passes both
        // `pkg_valid_name` and `escapeshellarg`.
        "g_get", "pkg_valid_name", "pkg_version_compare", "escapeshellarg",
        "isvalidpid", "unlink_if_exists", "mwexec_bg", "posix_kill", "usleep",
        // A DNS lookup, using PHP's own resolver client rather than a shell.
        // `dns_get_record()` asks the system resolver directly and returns a
        // structured array — no `dig`/`nslookup` binary, no `exec`, nothing
        // this boundary would otherwise have to forbid. `microtime` only
        // times how long that call took, the same way other read snippets
        // already read `time()`, and `round` only rounds that duration for
        // display — both pure functions with no reach outside their own
        // arguments.
        "dns_get_record", "microtime", "round",
        // The speed test's own outbound HTTPS request, plus the metadata
        // read alongside it — none of it a shell call. `curl_*` makes an
        // ordinary HTTP request the same way `dns_get_record` above makes
        // an ordinary DNS one; `curl_getinfo`/`curl_error` only read back
        // timing and status from a request already made, never issue one.
        // `random_bytes` generates the upload leg's own throwaway payload
        // in memory — nothing this reads or writes persists anywhere.
        "curl_init", "curl_setopt", "curl_exec", "curl_getinfo", "curl_error", "curl_close",
        "random_bytes",
        // The config backup's own read path. `is_readable` and `php_uname`
        // are pure queries; `base64_encode` only re-encodes a string this
        // snippet already read via `file_get_contents`, already on this
        // list, for safe transport — it does not touch disk itself.
        "is_readable", "php_uname", "base64_encode",
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
              // `name` remains the short value used to merge this repository
              // answer into the configuration list. The update URL separately
              // needs the full pfSense package identifier.
              "name" => strval($item["shortname"]) !== ""
                ? strval($item["shortname"]) : strval($item["name"]),
              "shortname" => strval($item["shortname"]),
              "update_name" => strval($item["name"]),
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

    /// Starts the native pfSense updater for the base system or one package.
    ///
    /// This is deliberately the only snippet allowed to launch a process. It
    /// mirrors `pkg_mgr_install.php`: the executable is pfSense's own updater,
    /// the option vocabulary is fixed here, a package must pass pfSense's
    /// validator and be confirmed outdated by a fresh repository read, and
    /// every shell argument is quoted independently. No caller-provided text
    /// can become a command, path, flag, or firmware branch.
    static func startUpdate(kind: String, packageIdentifier: String = "") -> PHPSnippet {
        let encoded = payload(JSONDict(["kind": .string(kind), "package": .string(packageIdentifier)]))
        return PHPSnippet("start_update", """
        ini_set('display_errors', 0);
        require_once '/etc/inc/pkg-utils.inc';
        require_once '/etc/inc/auth.inc';
        $vaktpost_payload = "\(encoded)";
        \(decodePayload)
        $vaktpost_kind = trim(strval($vaktpost_input["kind"] ?? ""));
        $vaktpost_package = trim(strval($vaktpost_input["package"] ?? ""));
        $vaktpost_product = trim(strval(g_get("product_name")));
        $vaktpost_pidfile = strval(g_get("varrun_path")) . "/" . $vaktpost_product
          . "-upgrade-GUI.pid";
        $vaktpost_sock = strval(g_get("tmp_path")) . "/" . $vaktpost_product . "-upgrade.sock";
        $vaktpost_target = ""; $vaktpost_ready = false;

        if (($vaktpost_kind !== "firmware" && $vaktpost_kind !== "package")
            || preg_match('/^[A-Za-z0-9_-]+$/D', $vaktpost_product) !== 1) {
          $toreturn = ["status" => "validation_failed", "error" => "Invalid update mode"];
        } else if (isvalidpid($vaktpost_pidfile)) {
          $toreturn = ["status" => "busy", "error" => "Another update is already running"];
        } else {
          if ($vaktpost_kind === "firmware") {
            $vaktpost_version = get_system_pkg_version();
            $vaktpost_ready = is_array($vaktpost_version)
              && strval($vaktpost_version["pkg_version_compare"] ?? "") === "<";
            $vaktpost_target = strval($vaktpost_version["version"] ?? "");
          } else if ($vaktpost_package !== "" && pkg_valid_name($vaktpost_package)) {
            $vaktpost_info = get_pkg_info([$vaktpost_package], false, true);
            if (is_array($vaktpost_info)) {
              foreach ($vaktpost_info as $vaktpost_item) {
                if (!is_array($vaktpost_item)
                    || strval($vaktpost_item["name"] ?? "") !== $vaktpost_package) { continue; }
                $vaktpost_installed = strval($vaktpost_item["installed_version"] ?? "");
                $vaktpost_target = strval($vaktpost_item["version"] ?? "");
                $vaktpost_ready = $vaktpost_installed !== "" && $vaktpost_target !== ""
                  && pkg_version_compare($vaktpost_installed, $vaktpost_target) === "<";
              }
            }
          }

          if (!$vaktpost_ready) {
            $toreturn = ["status" => "no_update",
              "error" => "The requested update is no longer available"];
          } else {
            $vaktpost_log = strval(g_get("cf_conf_path")) . ($vaktpost_kind === "firmware"
              ? "/upgrade_log" : "/pkg_log_" . $vaktpost_package);
            unlink_if_exists($vaktpost_log . ".txt");
            unlink_if_exists($vaktpost_log . ".json");
            unlink_if_exists($vaktpost_sock);

            $vaktpost_audit_session_started = false;
            if (session_status() !== PHP_SESSION_ACTIVE) {
              $vaktpost_audit_session_started = session_start(["use_cookies" => 0,
                "use_only_cookies" => 0, "use_strict_mode" => 0]);
            }
            $vaktpost_authenticated_user = trim(strval($_SERVER["PHP_AUTH_USER"] ?? ""));
            if ($vaktpost_authenticated_user !== "") {
              $_SESSION["Username"] = $vaktpost_authenticated_user;
              $vaktpost_authcfg = auth_get_authserver(config_get_path("system/webgui/authmode"));
              if (is_array($vaktpost_authcfg)) {
                $vaktpost_auth_type = trim(strval($vaktpost_authcfg["type"] ?? ""));
                $vaktpost_auth_name = trim(strval($vaktpost_authcfg["name"] ?? ""));
                if ($vaktpost_auth_type === "" || $vaktpost_auth_type === "Local Auth") {
                  $_SESSION["authsource"] = "Local Database";
                } else {
                  $_SESSION["authsource"] = strtoupper($vaktpost_auth_type)
                    . ($vaktpost_auth_name === "" ? "" : "/" . $vaktpost_auth_name);
                }
              }
            }
            write_config($vaktpost_kind === "firmware" ? "Vaktpost: restore point before pfSense update"
              : "Vaktpost: restore point before package update " . $vaktpost_package);
            if ($vaktpost_audit_session_started) {
              if (session_status() !== PHP_SESSION_ACTIVE) {
                session_start(["use_cookies" => 0, "use_only_cookies" => 0, "use_strict_mode" => 0]);
              }
              if (session_status() === PHP_SESSION_ACTIVE) {
                $_SESSION = [];
                session_destroy();
              }
            }

            $vaktpost_upgrade = "/usr/local/sbin/" . $vaktpost_product . "-upgrade";
            $vaktpost_command = escapeshellarg($vaktpost_upgrade) . " -y -l "
              . escapeshellarg($vaktpost_log . ".txt")
              . " -p " . escapeshellarg($vaktpost_sock);
            if ($vaktpost_kind === "package") {
              $vaktpost_command = $vaktpost_command
                . " -i " . escapeshellarg($vaktpost_package);
            }
            $vaktpost_pid = intval(mwexec_bg($vaktpost_command));
            $vaktpost_running = false; $vaktpost_exit = null;
            for ($vaktpost_attempt = 0; $vaktpost_attempt < 10; $vaktpost_attempt++) {
              $vaktpost_running = $vaktpost_pid > 0 && posix_kill($vaktpost_pid, 0);
              $vaktpost_log_output = file_exists($vaktpost_log . ".txt") ?
                strval(file_get_contents($vaktpost_log . ".txt")) : "";
              $vaktpost_rc_match = [];
              if (preg_match('/__RC=([0-9]+)/', $vaktpost_log_output, $vaktpost_rc_match) === 1) {
                $vaktpost_exit = intval($vaktpost_rc_match[1]);
                break;
              }
              if ($vaktpost_running) { break; }
              usleep(100000);
            }
            if ($vaktpost_exit !== null && $vaktpost_exit !== 0) {
              $toreturn = ["status" => "launch_failed", "started" => false,
                "error" => "pfSense updater exited with status " . strval($vaktpost_exit)];
            } else if ($vaktpost_pid > 0) {
              $vaktpost_phase = $vaktpost_exit === 0 ? "completed"
                : ($vaktpost_running ? "running" : "accepted");
              $toreturn = ["status" => "ok", "started" => true,
                "phase" => $vaktpost_phase, "mode" => $vaktpost_kind,
                "package" => $vaktpost_package, "target" => $vaktpost_target];
            } else {
              $toreturn = ["status" => "launch_failed", "started" => false,
                "error" => "pfSense did not accept the updater process"];
            }
          }
        }
        """)
    }

    /// Whether pfSense's native GUI updater process is currently active.
    static let updateProcessStatus = PHPSnippet("update_process_status", """
    require_once '/etc/inc/pkg-utils.inc';
    $product = trim(strval(g_get("product_name")));
    $pidfile = strval(g_get("varrun_path")) . "/" . $product . "-upgrade-GUI.pid";
    $version = get_system_pkg_version(false);
    $package_busy = is_array($version)
      && strval($version["pkg_busy"] ?? "") === "1";
    $toreturn = ["running" => isvalidpid($pidfile) || $package_busy];
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

    /// The grouping bars pfSense draws between rules — "Teamspeak" in a list
    /// of port forwards, for instance. Filter and NAT separators can both be
    /// created, edited, deleted and reordered. NAT uses a flat cross-interface
    /// position model, so its separators participate in the same drag order as
    /// every port-forward rule.
    ///
    /// Confirmed against pfSense's actual `filter.inc` (`display_separator`,
    /// `separator_rows`), not inferred, because the first version of this
    /// snippet guessed wrong on two structural points at once:
    ///
    ///   - `row` is an **array**, not a string. pfSense stores the position
    ///     as `row/0`, e.g. `["fr3"]`, and reads it with
    ///     `array_get_path($separator, 'row/0')`. Treating it as a plain
    ///     string made every position unparseable.
    ///   - Filter and NAT separators are **not** stored the same shape. Filter
    ///     really is grouped by interface, at `filter/separator/<if>`. NAT is
    ///     a single flat list at `nat/separator` with no interface grouping
    ///     at all — confirmed from `firewall_nat.php`, which reads
    ///     `config_get_path('nat/separator', [])` directly and numbers
    ///     separators against one counter (`$nnats`) that runs across every
    ///     forward regardless of interface. Iterating NAT the same way as
    ///     filter treated each separator's own field names as if they were
    ///     separate interfaces, which is where the earlier "Separator — sep0"
    ///     output came from: `sep0` is that separator's own key, read out
    ///     as though it were an interface name.
    ///
    /// The row prefix is confirmed as exactly two characters, `"fr"`, by
    /// `separator_rows()`'s own `substr(..., 2)` — not a guess, not "whatever
    /// prefix, tolerantly stripped" as the first version hedged.
    static let ruleSeparators = PHPSnippet("rule_separators", """
    require_once '/etc/inc/util.inc';
    global $config;
    $toreturn = [
      "filter" => [],
      "nat" => [],
      "apply_pending" => is_subsystem_dirty("filter") || is_subsystem_dirty("natconf")
        || is_subsystem_dirty("aliases"),
    ];

    // Filter: genuinely grouped by interface. Position is the count of rules
    // that precede the separator within that interface's own subset,
    // matching how the rules list is itself scoped per interface.
    $vaktpost_filter_root = $config["filter"];
    $vaktpost_filter_seps = is_array($vaktpost_filter_root) ? ($vaktpost_filter_root["separator"] ?? []) : [];
    if (is_array($vaktpost_filter_seps)) {
      foreach ($vaktpost_filter_seps as $vaktpost_if => $vaktpost_entries) {
        if (!is_array($vaktpost_entries)) { continue; }
        foreach ($vaktpost_entries as $vaktpost_key => $vaktpost_entry) {
          if (!is_array($vaktpost_entry)) { continue; }
          // pfSense reads `row/0` and strips exactly the first two
          // characters (`separator_rows()`, `substr(..., 2)`) — confirmed
          // from source, not a tolerant guess at a prefix.
          $vaktpost_position = "";
          $vaktpost_row = $vaktpost_entry["row"] ?? null;
          if (is_array($vaktpost_row) && isset($vaktpost_row[0])) {
            $vaktpost_raw_row = strval($vaktpost_row[0]);
            if (substr($vaktpost_raw_row, 0, 2) === "fr") {
              $vaktpost_position = substr($vaktpost_raw_row, 2);
            }
          }
          $toreturn["filter"][] = [
            "interface" => strval($vaktpost_if),
            "key" => strval($vaktpost_key),
            "text" => strval($vaktpost_entry["text"] ?? ""),
            "color" => strval($vaktpost_entry["color"] ?? ""),
            "position" => $vaktpost_position,
          ];
        }
      }
    }

    // NAT: one flat list, no interface grouping. Position is a count against
    // the *whole* forward list, because that is what firewall_nat.php itself
    // counts against — one counter, incremented once per forward regardless
    // of which interface it is on. There is no interface field to report per
    // separator because pfSense does not store one; the position alone is
    // what places it.
    $vaktpost_nat_root = $config["nat"];
    $vaktpost_nat_seps = is_array($vaktpost_nat_root) ? ($vaktpost_nat_root["separator"] ?? []) : [];
    if (is_array($vaktpost_nat_seps)) {
      foreach ($vaktpost_nat_seps as $vaktpost_key => $vaktpost_entry) {
        if (!is_array($vaktpost_entry)) { continue; }
        $vaktpost_position = "";
        $vaktpost_row = $vaktpost_entry["row"] ?? null;
        if (is_array($vaktpost_row) && isset($vaktpost_row[0])) {
          $vaktpost_raw_row = strval($vaktpost_row[0]);
          if (substr($vaktpost_raw_row, 0, 2) === "fr") {
            $vaktpost_position = substr($vaktpost_raw_row, 2);
          }
        }
        $toreturn["nat"][] = [
          "key" => strval($vaktpost_key),
          "text" => strval($vaktpost_entry["text"] ?? ""),
          "color" => strval($vaktpost_entry["color"] ?? ""),
          "position" => $vaktpost_position,
        ];
      }
    }
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

    /// Looks up one DNS record type for a host, using the firewall's own
    /// resolver — usually Unbound, forwarding through whatever upstream or
    /// split-DNS rules are configured there.
    ///
    /// `dns_get_record()` is PHP's own resolver client. It needs no shell —
    /// unlike `dig` or `nslookup`, which is what this app's write boundary
    /// would otherwise have to forbid here the same way it forbids `exec`
    /// everywhere else. Populates both `records` (name/class/type/value,
    /// the shape a `dig`-style tool would show) and `answers`
    /// (name/address) with the same rows, so a view can read whichever
    /// shape suits the record type without a second round trip.
    ///
    /// - Parameters:
    ///   - host: The hostname to look up.
    ///   - recordType: One of A, AAAA, CNAME, MX, NS, PTR, SOA, TXT.
    ///     Anything else is treated as A.
    static func dnsLookup(host: String, recordType: String) -> PHPSnippet {
        let encoded = payload(JSONDict(["host": .string(host), "type": .string(recordType)]))
        return PHPSnippet("dns_lookup", """
        ini_set('display_errors', 0);
        $toreturn = ["records" => [], "answers" => [], "serverTimings" => []];
        $vaktpost_payload = "\(encoded)";
        \(decodePayload)
        $vaktpost_host = trim(strval($vaktpost_input["host"] ?? ""));
        $vaktpost_type_name = strtoupper(trim(strval($vaktpost_input["type"] ?? "A")));
        $vaktpost_types = ["A" => DNS_A, "AAAA" => DNS_AAAA, "MX" => DNS_MX, "TXT" => DNS_TXT,
          "CNAME" => DNS_CNAME, "NS" => DNS_NS, "PTR" => DNS_PTR, "SOA" => DNS_SOA];
        $vaktpost_dnstype = isset($vaktpost_types[$vaktpost_type_name]) ? $vaktpost_types[$vaktpost_type_name] : DNS_A;
        $toreturn["host"] = $vaktpost_host;
        if ($vaktpost_host === "" || strlen($vaktpost_host) > 253) {
          $toreturn["error"] = "Enter a valid hostname.";
        } else {
          $vaktpost_start = microtime(true);
          $vaktpost_results = @dns_get_record($vaktpost_host, $vaktpost_dnstype);
          $vaktpost_elapsed = intval(round((microtime(true) - $vaktpost_start) * 1000));
          $toreturn["queryTime"] = $vaktpost_elapsed;
          $toreturn["serverTimings"][] = ["server" => "Firewall's own resolver", "time" => $vaktpost_elapsed . " msec"];
          if (!is_array($vaktpost_results) || count($vaktpost_results) === 0) {
            $toreturn["error"] = "No " . $vaktpost_type_name . " records found.";
          } else {
            foreach ($vaktpost_results as $vaktpost_r) {
              $vaktpost_rtype = isset($vaktpost_r["type"]) ? strval($vaktpost_r["type"]) : $vaktpost_type_name;
              $vaktpost_rname = isset($vaktpost_r["host"]) ? strval($vaktpost_r["host"]) : $vaktpost_host;
              $vaktpost_value = "";
              if (isset($vaktpost_r["ip"])) { $vaktpost_value = strval($vaktpost_r["ip"]); }
              elseif (isset($vaktpost_r["ipv6"])) { $vaktpost_value = strval($vaktpost_r["ipv6"]); }
              elseif (isset($vaktpost_r["txt"])) { $vaktpost_value = strval($vaktpost_r["txt"]); }
              elseif (isset($vaktpost_r["target"]) && isset($vaktpost_r["pri"])) {
                $vaktpost_value = strval($vaktpost_r["pri"]) . " " . strval($vaktpost_r["target"]);
              }
              elseif (isset($vaktpost_r["target"])) { $vaktpost_value = strval($vaktpost_r["target"]); }
              elseif (isset($vaktpost_r["mname"])) { $vaktpost_value = strval($vaktpost_r["mname"]); }
              $toreturn["records"][] = ["name" => $vaktpost_rname, "class" => "IN", "type" => $vaktpost_rtype, "value" => $vaktpost_value];
              $toreturn["answers"][] = ["name" => $vaktpost_rname, "address" => $vaktpost_value];
            }
          }
        }
        """)
    }

    /// Reloads the firewall ruleset without restarting services.
    ///
    /// Calls `filter_configure_sync()` which reloads the pf ruleset in place.
    static let reloadFirewall = PHPSnippet("reload_firewall", """
    ini_set('display_errors', 0);
    require_once '/etc/inc/filter.inc';
    $vaktpost_reload_result = filter_configure_sync();
    if ($vaktpost_reload_result === 0) {
      // Alias edits use pfSense's own dirty subsystem and remain staged until
      // this explicit Apply Changes action succeeds.
      clear_subsystem_dirty("aliases");
      $toreturn = ["status" => "ok"];
    } else {
      $toreturn = [
        "status" => "reload_failed",
        "error" => "pfSense did not complete the filter reload. Check Status > Filter Reload."
      ];
    }
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
        global $config;
        $toreturn = [];
        // Overwritten by every ending below. If it survives, this snippet
        // stopped partway — something between the config write and the dirty
        // mark did not return — and the app is told that, rather than being
        // handed a reply with no status at all to explain.
        $toreturn["status"] = "incomplete";
        $toreturn["error"] = "the quick-block snippet stopped before it finished";
        $vaktpost_payload = "\(encoded)";
        \(decodePayload)
        $vaktpost_if = trim(strval($vaktpost_input["interface"] ?? ""));
        $vaktpost_addr = trim(strval($vaktpost_input["address"] ?? ""));
        $vaktpost_direct = $vaktpost_addr;
        $vaktpost_address_valid = is_ipaddrv4($vaktpost_addr) || is_ipaddrv6($vaktpost_addr);
        if (!$vaktpost_address_valid && strpos($vaktpost_addr, "/") !== false) {
          $vaktpost_cidr = explode("/", $vaktpost_addr, 2);
          $vaktpost_direct = strval($vaktpost_cidr[0] ?? "");
          $vaktpost_bits = strval($vaktpost_cidr[1] ?? "");
          $vaktpost_address_valid = count($vaktpost_cidr) === 2
            && preg_match('/^[0-9]+$/', $vaktpost_bits) === 1
            && ((is_ipaddrv4($vaktpost_direct) && intval($vaktpost_bits) <= 32)
              || (is_ipaddrv6($vaktpost_direct) && intval($vaktpost_bits) <= 128));
        }
        if (!array_key_exists($vaktpost_if, get_configured_interface_with_descr())
            || !$vaktpost_address_valid) {
          $toreturn["status"] = "validation_failed";
          $toreturn["error"] = "The interface or literal IP address/network is invalid";
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
          $block_rule = [
            'type' => 'block',
            'interface' => $vaktpost_if,
            'descr' => strval($vaktpost_input["descr"] ?? ""),
            'ipprotocol' => is_ipaddrv6($vaktpost_direct) ? 'inet6' : 'inet',
            'protocol' => 'any',
            // Literal hosts and CIDRs both use the native address key.
            // `network` is reserved for pfSense system selectors such as
            // `wanip`, `lan` and `self`.
            'source' => ['address' => $vaktpost_addr],
            'destination' => ['any' => true],
            'tracker' => $vaktpost_tracker,
          ];
          $vaktpost_rules[] = $block_rule;
          $config['filter']['rule'] = array_values($vaktpost_rules);
          // XML-RPC authenticates PHP_AUTH_USER but does not populate the
          // webConfigurator session fields read by write_config(). Use only
          // pfSense's already-authenticated request identity and configured
          // provider; do not create or persist a GUI login session.
          $vaktpost_audit_session_started = false;
          if (session_status() !== PHP_SESSION_ACTIVE) {
            $vaktpost_audit_session_started = session_start([
              "use_cookies" => 0, "use_only_cookies" => 0, "use_strict_mode" => 0
            ]);
          }
          $vaktpost_authenticated_user = trim(strval($_SERVER["PHP_AUTH_USER"] ?? ""));
          if ($vaktpost_authenticated_user !== "") {
            $_SESSION["Username"] = $vaktpost_authenticated_user;
            $vaktpost_authcfg = auth_get_authserver(config_get_path("system/webgui/authmode"));
            if (is_array($vaktpost_authcfg)) {
              $vaktpost_auth_type = trim(strval($vaktpost_authcfg["type"] ?? ""));
              $vaktpost_auth_name = trim(strval($vaktpost_authcfg["name"] ?? ""));
              if ($vaktpost_auth_type === "" || $vaktpost_auth_type === "Local Auth") {
                $_SESSION["authsource"] = "Local Database";
              } else {
                $_SESSION["authsource"] = strtoupper($vaktpost_auth_type)
                  . ($vaktpost_auth_name === "" ? "" : "/" . $vaktpost_auth_name);
              }
            }
          }
          write_config("Vaktpost: quick-block rule added");
          if ($vaktpost_audit_session_started) {
            if (session_status() !== PHP_SESSION_ACTIVE) {
              session_start(["use_cookies" => 0, "use_only_cookies" => 0, "use_strict_mode" => 0]);
            }
            if (session_status() === PHP_SESSION_ACTIVE) {
              $_SESSION = [];
              session_destroy();
            }
          }
          mark_subsystem_dirty("filter");
          $toreturn["status"] = "ok";
          $toreturn["error"] = "";
          $toreturn["apply_pending"] = true;
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
        $vaktpost_if = trim(strval($vaktpost_input["interface"] ?? ""));
        if ($vaktpost_if === "") {
          pfctl_clear_states();
          $toreturn["scope"] = "all";
          $toreturn["status"] = "ok";
        } elseif (!does_interface_exist($vaktpost_if)) {
          $toreturn["status"] = "validation_failed";
          $toreturn["error"] = "The selected interface device is unavailable";
        } else {
          pfctl_clear_states_by_if($vaktpost_if);
          $toreturn["scope"] = $vaktpost_if;
          $toreturn["status"] = "ok";
        }
        """)
    }

    static func deleteRule(tracker: String) -> PHPSnippet {
        let encoded = payload(JSONDict(["tracker": .string(tracker)]))
        return PHPSnippet("delete_rule", """
        ini_set('display_errors', 0);
        require_once '/etc/inc/util.inc';
        require_once '/etc/inc/filter.inc';
        global $config;
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
          $vaktpost_audit_session_started = false;
          if (session_status() !== PHP_SESSION_ACTIVE) {
            $vaktpost_audit_session_started = session_start([
              "use_cookies" => 0, "use_only_cookies" => 0, "use_strict_mode" => 0
            ]);
          }
          $vaktpost_authenticated_user = trim(strval($_SERVER["PHP_AUTH_USER"] ?? ""));
          if ($vaktpost_authenticated_user !== "") {
            $_SESSION["Username"] = $vaktpost_authenticated_user;
            $vaktpost_authcfg = auth_get_authserver(config_get_path("system/webgui/authmode"));
            if (is_array($vaktpost_authcfg)) {
              $vaktpost_auth_type = trim(strval($vaktpost_authcfg["type"] ?? ""));
              $vaktpost_auth_name = trim(strval($vaktpost_authcfg["name"] ?? ""));
              if ($vaktpost_auth_type === "" || $vaktpost_auth_type === "Local Auth") {
                $_SESSION["authsource"] = "Local Database";
              } else {
                $_SESSION["authsource"] = strtoupper($vaktpost_auth_type)
                  . ($vaktpost_auth_name === "" ? "" : "/" . $vaktpost_auth_name);
              }
            }
          }
          write_config("Vaktpost: deleted a rule");
          if ($vaktpost_audit_session_started) {
            if (session_status() !== PHP_SESSION_ACTIVE) {
              session_start(["use_cookies" => 0, "use_only_cookies" => 0, "use_strict_mode" => 0]);
            }
            if (session_status() === PHP_SESSION_ACTIVE) {
              $_SESSION = [];
              session_destroy();
            }
          }
          mark_subsystem_dirty("filter");
          $toreturn["status"] = "ok";
          $toreturn["apply_pending"] = true;
        } else {
          $toreturn["status"] = "not_found";
        }
        """)
    }

    /// Creates or updates one filter-rule separator using pfSense's native
    /// `filter/separator/<interface>/sepN` shape. Position is the number of
    /// interface rules preceding the separator, encoded as `["frN"]`.
    static func saveFilterSeparator(separator: JSONDict) -> PHPSnippet {
        let encoded = payload(separator)
        return PHPSnippet("save_filter_separator", """
        ini_set('display_errors', 0);
        require_once '/etc/inc/util.inc';
        require_once '/etc/inc/filter.inc';
        global $config;
        $toreturn = [];
        $vaktpost_payload = "\(encoded)";
        \(decodePayload)
        $vaktpost_interface = trim(strval($vaktpost_input["interface"] ?? ""));
        $vaktpost_key = trim(strval($vaktpost_input["key"] ?? ""));
        $vaktpost_text = trim(strval($vaktpost_input["text"] ?? ""));
        $vaktpost_color = trim(strval($vaktpost_input["color"] ?? "info"));
        $vaktpost_position = intval($vaktpost_input["position"] ?? -1);
        $vaktpost_create = ($vaktpost_input["create"] ?? false) === true;

        $vaktpost_filter = is_array($config["filter"] ?? null) ? $config["filter"] : [];
        $vaktpost_rules = is_array($vaktpost_filter["rule"] ?? null)
          ? $vaktpost_filter["rule"] : [];
        $vaktpost_interface_rule_count = 0;
        foreach ($vaktpost_rules as $vaktpost_rule) {
          if (!is_array($vaktpost_rule)) { continue; }
          $vaktpost_rule_interface = $vaktpost_rule["interface"] ?? "";
          $vaktpost_rule_interface = is_array($vaktpost_rule_interface)
            ? implode(",", $vaktpost_rule_interface) : strval($vaktpost_rule_interface);
          if ($vaktpost_rule_interface === $vaktpost_interface) {
            $vaktpost_interface_rule_count = $vaktpost_interface_rule_count + 1;
          }
        }

        if (!array_key_exists($vaktpost_interface, get_configured_interface_with_descr())
            || $vaktpost_text === ""
            || !in_array($vaktpost_color, ["info", "success", "warning", "danger"], true)
            || $vaktpost_position < 0
            || $vaktpost_position > $vaktpost_interface_rule_count) {
          $toreturn["status"] = "validation_failed";
          $toreturn["error"] = "The separator interface, text, color, or position is invalid";
        } else {
          $vaktpost_all_separators = is_array($vaktpost_filter["separator"] ?? null)
            ? $vaktpost_filter["separator"] : [];
          $vaktpost_separators = is_array($vaktpost_all_separators[$vaktpost_interface] ?? null)
            ? $vaktpost_all_separators[$vaktpost_interface] : [];

          if ($vaktpost_create) {
            $vaktpost_number = 0;
            $vaktpost_key = "sep" . $vaktpost_number;
            while (array_key_exists($vaktpost_key, $vaktpost_separators)) {
              $vaktpost_number = $vaktpost_number + 1;
              $vaktpost_key = "sep" . $vaktpost_number;
            }
            $vaktpost_separators[$vaktpost_key] = [];
          }

          if ($vaktpost_key === "" || !array_key_exists($vaktpost_key, $vaktpost_separators)) {
            $toreturn["status"] = "not_found";
            $toreturn["error"] = "The separator is no longer present";
          } else {
            $vaktpost_separators[$vaktpost_key]["text"] = $vaktpost_text;
            $vaktpost_separators[$vaktpost_key]["color"] = $vaktpost_color;
            $vaktpost_separators[$vaktpost_key]["row"] = ["fr" . $vaktpost_position];
            $vaktpost_all_separators[$vaktpost_interface] = $vaktpost_separators;
            $vaktpost_filter["separator"] = $vaktpost_all_separators;
            $config["filter"] = $vaktpost_filter;

            $vaktpost_audit_session_started = false;
            if (session_status() !== PHP_SESSION_ACTIVE) {
              $vaktpost_audit_session_started = session_start([
                "use_cookies" => 0, "use_only_cookies" => 0, "use_strict_mode" => 0
              ]);
            }
            $vaktpost_authenticated_user = trim(strval($_SERVER["PHP_AUTH_USER"] ?? ""));
            if ($vaktpost_authenticated_user !== "") {
              $_SESSION["Username"] = $vaktpost_authenticated_user;
              $vaktpost_authcfg = auth_get_authserver(config_get_path("system/webgui/authmode"));
              if (is_array($vaktpost_authcfg)) {
                $vaktpost_auth_type = trim(strval($vaktpost_authcfg["type"] ?? ""));
                $vaktpost_auth_name = trim(strval($vaktpost_authcfg["name"] ?? ""));
                if ($vaktpost_auth_type === "" || $vaktpost_auth_type === "Local Auth") {
                  $_SESSION["authsource"] = "Local Database";
                } else {
                  $_SESSION["authsource"] = strtoupper($vaktpost_auth_type)
                    . ($vaktpost_auth_name === "" ? "" : "/" . $vaktpost_auth_name);
                }
              }
            }
            write_config($vaktpost_create
              ? "Vaktpost: added a rule separator on " . $vaktpost_interface
              : "Vaktpost: edited a rule separator on " . $vaktpost_interface);
            if ($vaktpost_audit_session_started) {
              if (session_status() !== PHP_SESSION_ACTIVE) {
                session_start(["use_cookies" => 0, "use_only_cookies" => 0, "use_strict_mode" => 0]);
              }
              if (session_status() === PHP_SESSION_ACTIVE) {
                $_SESSION = [];
                session_destroy();
              }
            }
            mark_subsystem_dirty("filter");
            $toreturn = [
              "status" => "ok", "apply_pending" => true,
              "key" => $vaktpost_key, "interface" => $vaktpost_interface,
              "text" => $vaktpost_text, "color" => $vaktpost_color,
              "position" => $vaktpost_position, "created" => $vaktpost_create
            ];
          }
        }
        """)
    }

    /// Deletes one filter-rule separator without touching the rules around it.
    static func deleteFilterSeparator(interface: String, key: String) -> PHPSnippet {
        let encoded = payload(JSONDict([
            "interface": .string(interface), "key": .string(key)
        ]))
        return PHPSnippet("delete_filter_separator", """
        ini_set('display_errors', 0);
        require_once '/etc/inc/util.inc';
        require_once '/etc/inc/filter.inc';
        global $config;
        $toreturn = [];
        $vaktpost_payload = "\(encoded)";
        \(decodePayload)
        $vaktpost_interface = trim(strval($vaktpost_input["interface"] ?? ""));
        $vaktpost_key = trim(strval($vaktpost_input["key"] ?? ""));
        $vaktpost_filter = is_array($config["filter"] ?? null) ? $config["filter"] : [];
        $vaktpost_all_separators = is_array($vaktpost_filter["separator"] ?? null)
          ? $vaktpost_filter["separator"] : [];
        $vaktpost_separators = is_array($vaktpost_all_separators[$vaktpost_interface] ?? null)
          ? $vaktpost_all_separators[$vaktpost_interface] : [];

        if ($vaktpost_interface === "" || $vaktpost_key === ""
            || !array_key_exists($vaktpost_key, $vaktpost_separators)) {
          $toreturn["status"] = "not_found";
          $toreturn["error"] = "The separator is no longer present";
        } else {
          unset($vaktpost_separators[$vaktpost_key]);
          $vaktpost_all_separators[$vaktpost_interface] = $vaktpost_separators;
          $vaktpost_filter["separator"] = $vaktpost_all_separators;
          $config["filter"] = $vaktpost_filter;

          $vaktpost_audit_session_started = false;
          if (session_status() !== PHP_SESSION_ACTIVE) {
            $vaktpost_audit_session_started = session_start([
              "use_cookies" => 0, "use_only_cookies" => 0, "use_strict_mode" => 0
            ]);
          }
          $vaktpost_authenticated_user = trim(strval($_SERVER["PHP_AUTH_USER"] ?? ""));
          if ($vaktpost_authenticated_user !== "") {
            $_SESSION["Username"] = $vaktpost_authenticated_user;
            $vaktpost_authcfg = auth_get_authserver(config_get_path("system/webgui/authmode"));
            if (is_array($vaktpost_authcfg)) {
              $vaktpost_auth_type = trim(strval($vaktpost_authcfg["type"] ?? ""));
              $vaktpost_auth_name = trim(strval($vaktpost_authcfg["name"] ?? ""));
              if ($vaktpost_auth_type === "" || $vaktpost_auth_type === "Local Auth") {
                $_SESSION["authsource"] = "Local Database";
              } else {
                $_SESSION["authsource"] = strtoupper($vaktpost_auth_type)
                  . ($vaktpost_auth_name === "" ? "" : "/" . $vaktpost_auth_name);
              }
            }
          }
          write_config("Vaktpost: deleted a rule separator on " . $vaktpost_interface);
          if ($vaktpost_audit_session_started) {
            if (session_status() !== PHP_SESSION_ACTIVE) {
              session_start(["use_cookies" => 0, "use_only_cookies" => 0, "use_strict_mode" => 0]);
            }
            if (session_status() === PHP_SESSION_ACTIVE) {
              $_SESSION = [];
              session_destroy();
            }
          }
          mark_subsystem_dirty("filter");
          $toreturn = ["status" => "ok", "apply_pending" => true,
            "key" => $vaktpost_key, "interface" => $vaktpost_interface];
        }
        """)
    }

    /// Creates or updates one separator in pfSense's flat NAT table.
    static func saveNatSeparator(separator: JSONDict) -> PHPSnippet {
        let encoded = payload(separator)
        return PHPSnippet("save_nat_separator", """
        ini_set('display_errors', 0);
        require_once '/etc/inc/util.inc';
        require_once '/etc/inc/filter.inc';
        global $config;
        $toreturn = [];
        $vaktpost_payload = "\(encoded)";
        \(decodePayload)
        $vaktpost_key = trim(strval($vaktpost_input["key"] ?? ""));
        $vaktpost_text = trim(strval($vaktpost_input["text"] ?? ""));
        $vaktpost_color = trim(strval($vaktpost_input["color"] ?? "info"));
        $vaktpost_position = intval($vaktpost_input["position"] ?? -1);
        $vaktpost_create = ($vaktpost_input["create"] ?? false) === true;

        $vaktpost_nat = is_array($config["nat"] ?? null) ? $config["nat"] : [];
        $vaktpost_rules = is_array($vaktpost_nat["rule"] ?? null)
          ? array_values($vaktpost_nat["rule"]) : [];
        $vaktpost_separators = is_array($vaktpost_nat["separator"] ?? null)
          ? $vaktpost_nat["separator"] : [];

        if ($vaktpost_text === ""
            || !in_array($vaktpost_color, ["info", "success", "warning", "danger"], true)
            || $vaktpost_position < 0 || $vaktpost_position > count($vaktpost_rules)) {
          $toreturn["status"] = "validation_failed";
          $toreturn["error"] = "The NAT separator text, color, or position is invalid";
        } else {
          if ($vaktpost_create) {
            $vaktpost_number = 0;
            $vaktpost_key = "sep" . $vaktpost_number;
            while (array_key_exists($vaktpost_key, $vaktpost_separators)) {
              $vaktpost_number = $vaktpost_number + 1;
              $vaktpost_key = "sep" . $vaktpost_number;
            }
            $vaktpost_separators[$vaktpost_key] = [];
          }

          if ($vaktpost_key === "" || !array_key_exists($vaktpost_key, $vaktpost_separators)) {
            $toreturn["status"] = "not_found";
            $toreturn["error"] = "The NAT separator is no longer present";
          } else {
            $vaktpost_separators[$vaktpost_key]["text"] = $vaktpost_text;
            $vaktpost_separators[$vaktpost_key]["color"] = $vaktpost_color;
            $vaktpost_separators[$vaktpost_key]["row"] = ["fr" . $vaktpost_position];
            $vaktpost_nat["separator"] = $vaktpost_separators;
            $config["nat"] = $vaktpost_nat;

            $vaktpost_audit_session_started = false;
            if (session_status() !== PHP_SESSION_ACTIVE) {
              $vaktpost_audit_session_started = session_start([
                "use_cookies" => 0, "use_only_cookies" => 0, "use_strict_mode" => 0
              ]);
            }
            $vaktpost_authenticated_user = trim(strval($_SERVER["PHP_AUTH_USER"] ?? ""));
            if ($vaktpost_authenticated_user !== "") {
              $_SESSION["Username"] = $vaktpost_authenticated_user;
              $vaktpost_authcfg = auth_get_authserver(config_get_path("system/webgui/authmode"));
              if (is_array($vaktpost_authcfg)) {
                $vaktpost_auth_type = trim(strval($vaktpost_authcfg["type"] ?? ""));
                $vaktpost_auth_name = trim(strval($vaktpost_authcfg["name"] ?? ""));
                if ($vaktpost_auth_type === "" || $vaktpost_auth_type === "Local Auth") {
                  $_SESSION["authsource"] = "Local Database";
                } else {
                  $_SESSION["authsource"] = strtoupper($vaktpost_auth_type)
                    . ($vaktpost_auth_name === "" ? "" : "/" . $vaktpost_auth_name);
                }
              }
            }
            write_config($vaktpost_create
              ? "Vaktpost: added a NAT separator"
              : "Vaktpost: edited a NAT separator");
            if ($vaktpost_audit_session_started) {
              if (session_status() !== PHP_SESSION_ACTIVE) {
                session_start(["use_cookies" => 0, "use_only_cookies" => 0, "use_strict_mode" => 0]);
              }
              if (session_status() === PHP_SESSION_ACTIVE) {
                $_SESSION = [];
                session_destroy();
              }
            }
            mark_subsystem_dirty("natconf");
            $toreturn = [
              "status" => "ok", "apply_pending" => true,
              "key" => $vaktpost_key, "text" => $vaktpost_text,
              "color" => $vaktpost_color, "position" => $vaktpost_position,
              "created" => $vaktpost_create
            ];
          }
        }
        """)
    }

    /// Deletes one flat NAT separator without changing surrounding forwards.
    static func deleteNatSeparator(key: String) -> PHPSnippet {
        let encoded = payload(JSONDict(["key": .string(key)]))
        return PHPSnippet("delete_nat_separator", """
        ini_set('display_errors', 0);
        require_once '/etc/inc/util.inc';
        require_once '/etc/inc/filter.inc';
        global $config;
        $toreturn = [];
        $vaktpost_payload = "\(encoded)";
        \(decodePayload)
        $vaktpost_key = trim(strval($vaktpost_input["key"] ?? ""));
        $vaktpost_nat = is_array($config["nat"] ?? null) ? $config["nat"] : [];
        $vaktpost_separators = is_array($vaktpost_nat["separator"] ?? null)
          ? $vaktpost_nat["separator"] : [];

        if ($vaktpost_key === "" || !array_key_exists($vaktpost_key, $vaktpost_separators)) {
          $toreturn["status"] = "not_found";
          $toreturn["error"] = "The NAT separator is no longer present";
        } else {
          unset($vaktpost_separators[$vaktpost_key]);
          $vaktpost_nat["separator"] = $vaktpost_separators;
          $config["nat"] = $vaktpost_nat;

          $vaktpost_audit_session_started = false;
          if (session_status() !== PHP_SESSION_ACTIVE) {
            $vaktpost_audit_session_started = session_start([
              "use_cookies" => 0, "use_only_cookies" => 0, "use_strict_mode" => 0
            ]);
          }
          $vaktpost_authenticated_user = trim(strval($_SERVER["PHP_AUTH_USER"] ?? ""));
          if ($vaktpost_authenticated_user !== "") {
            $_SESSION["Username"] = $vaktpost_authenticated_user;
            $vaktpost_authcfg = auth_get_authserver(config_get_path("system/webgui/authmode"));
            if (is_array($vaktpost_authcfg)) {
              $vaktpost_auth_type = trim(strval($vaktpost_authcfg["type"] ?? ""));
              $vaktpost_auth_name = trim(strval($vaktpost_authcfg["name"] ?? ""));
              if ($vaktpost_auth_type === "" || $vaktpost_auth_type === "Local Auth") {
                $_SESSION["authsource"] = "Local Database";
              } else {
                $_SESSION["authsource"] = strtoupper($vaktpost_auth_type)
                  . ($vaktpost_auth_name === "" ? "" : "/" . $vaktpost_auth_name);
              }
            }
          }
          write_config("Vaktpost: deleted a NAT separator");
          if ($vaktpost_audit_session_started) {
            if (session_status() !== PHP_SESSION_ACTIVE) {
              session_start(["use_cookies" => 0, "use_only_cookies" => 0, "use_strict_mode" => 0]);
            }
            if (session_status() === PHP_SESSION_ACTIVE) {
              $_SESSION = [];
              session_destroy();
            }
          }
          mark_subsystem_dirty("natconf");
          $toreturn = ["status" => "ok", "apply_pending" => true, "key" => $vaktpost_key];
        }
        """)
    }

    /// Creates or updates a host, network, or port alias without loading the
    /// resulting ruleset. pfSense's alias page follows the same two-phase
    /// model: save config, mark `aliases` dirty, then apply separately.
    /// Its body is a reviewed static PHP literal, not complex Swift control flow.
    static func saveAlias(alias: JSONDict) -> PHPSnippet { // swiftlint:disable:this function_body_length
        let encoded = payload(alias)
        return PHPSnippet("save_alias", """
        ini_set('display_errors', 0);
        require_once '/etc/inc/util.inc';
        require_once '/etc/inc/filter.inc';
        require_once '/etc/inc/pfsense-utils.inc';
        global $config;
        $toreturn = [];
        $vaktpost_payload = "\(encoded)";
        \(decodePayload)
        $vaktpost_create = ($vaktpost_input["create"] ?? false) === true;
        $vaktpost_original = trim(strval($vaktpost_input["original_name"] ?? ""));
        $vaktpost_name = trim(strval($vaktpost_input["name"] ?? ""));
        $vaktpost_type = strtolower(trim(strval($vaktpost_input["type"] ?? "")));
        $vaktpost_descr = trim(strval($vaktpost_input["descr"] ?? ""));
        $vaktpost_members = $vaktpost_input["members"] ?? [];
        $vaktpost_details = $vaktpost_input["details"] ?? [];
        $vaktpost_alias_root = $config["aliases"] ?? [];
        $vaktpost_aliases = (is_array($vaktpost_alias_root)
          && is_iterable($vaktpost_alias_root["alias"] ?? null))
          ? $vaktpost_alias_root["alias"] : [];
        $vaktpost_error = "";
        if ($vaktpost_name === "" || preg_match('/^[A-Za-z_][A-Za-z0-9_]*$/D', $vaktpost_name) !== 1) {
          $vaktpost_error = "Alias names must start with a letter or underscore and contain only letters, numbers, and underscores";
        } elseif (!in_array($vaktpost_type, ["host", "network", "port"], true)) {
          $vaktpost_error = "Only host, network, and port aliases can be edited in Vaktpost";
        } elseif (!is_array($vaktpost_members) || count($vaktpost_members) < 1 || count($vaktpost_members) > 5000) {
          $vaktpost_error = "At least one alias member is required";
        } elseif (!is_array($vaktpost_details)) {
          $vaktpost_error = "Alias member descriptions are malformed";
        }

        $vaktpost_found = -1;
        if ($vaktpost_error === "") {
          foreach ($vaktpost_aliases as $vaktpost_index => $vaktpost_existing) {
            if (!is_array($vaktpost_existing)) { continue; }
            $vaktpost_existing_name = trim(strval($vaktpost_existing["name"] ?? ""));
            if (strtolower($vaktpost_existing_name) === strtolower($vaktpost_name)) {
              if ($vaktpost_create || $vaktpost_existing_name !== $vaktpost_original) {
                $vaktpost_error = "An alias with this name already exists";
                break;
              }
              $vaktpost_found = intval($vaktpost_index);
            }
            if (!$vaktpost_create && $vaktpost_existing_name === $vaktpost_original) {
              $vaktpost_found = intval($vaktpost_index);
            }
          }
          if (!$vaktpost_create && ($vaktpost_original === "" || $vaktpost_name !== $vaktpost_original)) {
            $vaktpost_error = "Existing alias names cannot be changed because firewall rules may reference them";
          } elseif (!$vaktpost_create && $vaktpost_found < 0) {
            $vaktpost_error = "The alias is no longer present";
          } elseif (!$vaktpost_create
              && strtolower(trim(strval($vaktpost_aliases[$vaktpost_found]["type"] ?? ""))) !== $vaktpost_type) {
            $vaktpost_error = "Existing alias types cannot be changed because firewall rules may reference them";
          }
        }

        $vaktpost_clean_members = [];
        $vaktpost_clean_details = [];
        if ($vaktpost_error === "") {
          foreach ($vaktpost_members as $vaktpost_index => $vaktpost_member_value) {
            $vaktpost_member = trim(strval($vaktpost_member_value));
            if ($vaktpost_member === "") {
              $vaktpost_error = "Alias members cannot be blank";
              break;
            }
            if ($vaktpost_member === $vaktpost_name) {
              $vaktpost_error = "An alias cannot include itself";
              break;
            }
            $vaktpost_valid = $vaktpost_type === "port"
              ? is_port_or_range_or_alias($vaktpost_member)
              : (is_ipaddroralias($vaktpost_member) || is_subnet($vaktpost_member)
                || is_iprange($vaktpost_member) || is_fqdn($vaktpost_member));
            if (!$vaktpost_valid) {
              $vaktpost_error = "One or more alias members are invalid for this alias type";
              break;
            }
            $vaktpost_clean_members[] = $vaktpost_member;
            $vaktpost_clean_details[] = trim(strval($vaktpost_details[$vaktpost_index] ?? ""));
          }
        }

        if ($vaktpost_error !== "") {
          $toreturn = ["status" => "validation_failed", "error" => $vaktpost_error];
        } else {
          $vaktpost_entry = $vaktpost_create ? [] : $vaktpost_aliases[$vaktpost_found];
          $vaktpost_entry["name"] = $vaktpost_name;
          $vaktpost_entry["type"] = $vaktpost_type;
          $vaktpost_entry["address"] = implode(" ", $vaktpost_clean_members);
          $vaktpost_entry["detail"] = implode("||", $vaktpost_clean_details);
          if ($vaktpost_descr === "") {
            unset($vaktpost_entry["descr"]);
          } else {
            $vaktpost_entry["descr"] = $vaktpost_descr;
          }
          if ($vaktpost_create) {
            $vaktpost_aliases[] = $vaktpost_entry;
          } else {
            $vaktpost_aliases[$vaktpost_found] = $vaktpost_entry;
          }
          $config["aliases"]["alias"] = array_values($vaktpost_aliases);
          $vaktpost_audit_session_started = false;
          if (session_status() !== PHP_SESSION_ACTIVE) {
            $vaktpost_audit_session_started = session_start([
              "use_cookies" => 0, "use_only_cookies" => 0, "use_strict_mode" => 0
            ]);
          }
          $vaktpost_authenticated_user = trim(strval($_SERVER["PHP_AUTH_USER"] ?? ""));
          if ($vaktpost_authenticated_user !== "") {
            $_SESSION["Username"] = $vaktpost_authenticated_user;
            $vaktpost_authcfg = auth_get_authserver(config_get_path("system/webgui/authmode"));
            if (is_array($vaktpost_authcfg)) {
              $vaktpost_auth_type = trim(strval($vaktpost_authcfg["type"] ?? ""));
              $vaktpost_auth_name = trim(strval($vaktpost_authcfg["name"] ?? ""));
              if ($vaktpost_auth_type === "" || $vaktpost_auth_type === "Local Auth") {
                $_SESSION["authsource"] = "Local Database";
              } else {
                $_SESSION["authsource"] = strtoupper($vaktpost_auth_type)
                  . ($vaktpost_auth_name === "" ? "" : "/" . $vaktpost_auth_name);
              }
            }
          }
          write_config($vaktpost_create
            ? "Vaktpost: added firewall alias " . $vaktpost_name
            : "Vaktpost: edited firewall alias " . $vaktpost_name);
          if ($vaktpost_audit_session_started) {
            if (session_status() !== PHP_SESSION_ACTIVE) {
              session_start(["use_cookies" => 0, "use_only_cookies" => 0, "use_strict_mode" => 0]);
            }
            if (session_status() === PHP_SESSION_ACTIVE) {
              $_SESSION = [];
              session_destroy();
            }
          }
          mark_subsystem_dirty("aliases");
          $toreturn = [
            "status" => "ok", "apply_pending" => true,
            "created" => $vaktpost_create, "name" => $vaktpost_name
          ];
        }
        """)
    }

    /// Deletes an alias only when pfSense reports no rule references and no
    /// other alias contains it. The config is staged; Apply Changes performs
    /// the actual ruleset reload later.
    static func deleteAlias(name: String) -> PHPSnippet {
        let encoded = payload(JSONDict(["name": .string(name)]))
        return PHPSnippet("delete_alias", """
        ini_set('display_errors', 0);
        require_once '/etc/inc/util.inc';
        require_once '/etc/inc/filter.inc';
        require_once '/etc/inc/pfsense-utils.inc';
        global $config;
        $toreturn = [];
        $vaktpost_payload = "\(encoded)";
        \(decodePayload)
        $vaktpost_name = trim(strval($vaktpost_input["name"] ?? ""));
        $vaktpost_alias_root = $config["aliases"] ?? [];
        $vaktpost_aliases = (is_array($vaktpost_alias_root)
          && is_iterable($vaktpost_alias_root["alias"] ?? null))
          ? $vaktpost_alias_root["alias"] : [];
        $vaktpost_found = -1;
        $vaktpost_nested_use = false;
        foreach ($vaktpost_aliases as $vaktpost_index => $vaktpost_existing) {
          if (!is_array($vaktpost_existing)) { continue; }
          $vaktpost_existing_name = trim(strval($vaktpost_existing["name"] ?? ""));
          if ($vaktpost_existing_name === $vaktpost_name) {
            $vaktpost_found = intval($vaktpost_index);
            continue;
          }
          $vaktpost_existing_members = explode(" ", trim(strval($vaktpost_existing["address"] ?? "")));
          foreach ($vaktpost_existing_members as $vaktpost_existing_member) {
            if (trim(strval($vaktpost_existing_member)) === $vaktpost_name) {
              $vaktpost_nested_use = true;
              break;
            }
          }
        }
        // pfSense's helper covers the principal address/target fields. The
        // exact-string scan is intentionally conservative and additionally
        // catches filter/NAT port references on versions whose helper omits
        // them. A false positive refuses deletion; it never removes policy.
        $vaktpost_policy_text = json_encode([
          $config["filter"] ?? [], $config["nat"] ?? []
        ]);
        $vaktpost_policy_use = strpos($vaktpost_policy_text, '"' . $vaktpost_name . '"') !== false;
        if ($vaktpost_name === "" || $vaktpost_found < 0) {
          $toreturn = ["status" => "not_found", "error" => "The alias is no longer present"];
        } elseif (is_alias_inuse($vaktpost_name) || $vaktpost_policy_use || $vaktpost_nested_use) {
          $toreturn = [
            "status" => "in_use",
            "error" => "This alias is used by a firewall rule, NAT rule, or another alias"
          ];
        } else {
          unset($vaktpost_aliases[$vaktpost_found]);
          $config["aliases"]["alias"] = array_values($vaktpost_aliases);
          $vaktpost_audit_session_started = false;
          if (session_status() !== PHP_SESSION_ACTIVE) {
            $vaktpost_audit_session_started = session_start([
              "use_cookies" => 0, "use_only_cookies" => 0, "use_strict_mode" => 0
            ]);
          }
          $vaktpost_authenticated_user = trim(strval($_SERVER["PHP_AUTH_USER"] ?? ""));
          if ($vaktpost_authenticated_user !== "") {
            $_SESSION["Username"] = $vaktpost_authenticated_user;
            $vaktpost_authcfg = auth_get_authserver(config_get_path("system/webgui/authmode"));
            if (is_array($vaktpost_authcfg)) {
              $vaktpost_auth_type = trim(strval($vaktpost_authcfg["type"] ?? ""));
              $vaktpost_auth_name = trim(strval($vaktpost_authcfg["name"] ?? ""));
              if ($vaktpost_auth_type === "" || $vaktpost_auth_type === "Local Auth") {
                $_SESSION["authsource"] = "Local Database";
              } else {
                $_SESSION["authsource"] = strtoupper($vaktpost_auth_type)
                  . ($vaktpost_auth_name === "" ? "" : "/" . $vaktpost_auth_name);
              }
            }
          }
          write_config("Vaktpost: deleted firewall alias " . $vaktpost_name);
          if ($vaktpost_audit_session_started) {
            if (session_status() !== PHP_SESSION_ACTIVE) {
              session_start(["use_cookies" => 0, "use_only_cookies" => 0, "use_strict_mode" => 0]);
            }
            if (session_status() === PHP_SESSION_ACTIVE) {
              $_SESSION = [];
              session_destroy();
            }
          }
          mark_subsystem_dirty("aliases");
          $toreturn = ["status" => "ok", "apply_pending" => true, "name" => $vaktpost_name];
        }
        """)
    }

    /// Reorders one interface's filter rules, and recomputes its separators'
    /// positions to match — the operation behind dragging a rule or a
    /// separator to a new spot.
    ///
    /// Deliberately **not** a port of pfSense's own reorder machinery
    /// (`set_filter_rules_order`, and the category/group/subcategory "rules
    /// map" behind it). A full search of `filter.inc`, `firewall_rules.php`,
    /// `firewall_nat.php` and `pfsense-utils.inc` found pfSense's own
    /// separator-renumbering function, `shift_separators()`, with **zero
    /// call sites** in any of them — so whether, or how, pfSense's own drag
    /// path keeps separators correct could not be established from source.
    /// Replicating an internal this app cannot see the call graph for would
    /// be exactly the kind of guess this project has learned not to make.
    ///
    /// What is here instead is independently well-defined: given the final
    /// order a drag produced, replace this interface's rules with that order
    /// and recompute every separator's position fresh — "how many rule-items
    /// precede me now" — using the identical definition the read path
    /// already uses to report a position back to the app. Reading and
    /// writing share one definition, so they cannot drift apart from each
    /// other even if pfSense's own algorithm works some other way
    /// internally; pfSense's own list rendering reads the result correctly
    /// either way, since `display_separator()` only cares about the final
    /// `"fr" . N` string, not how it was produced.
    ///
    /// `items` must be an exact permutation of what already exists for this
    /// interface — the same set of rule trackers, the same set of separator
    /// keys, neither more nor fewer. This operation only reorders; it cannot
    /// add, remove, or move something onto a different interface. Verified
    /// directly against real PHP execution and a synthetic multi-interface
    /// fixture, including that every other interface's rules and every
    /// unrelated field on a moved rule survive untouched, and that a
    /// mismatched submission is rejected with no write at all.
    /// Its body is a reviewed static PHP literal, not complex Swift control flow.
    static func reorderFilterRules(interface: String, items: [JSONValue]) -> PHPSnippet { // swiftlint:disable:this function_body_length
        let encoded = payload(JSONDict([
            "interface": .string(interface),
            "items": .array(items)
        ]))
        return PHPSnippet("reorder_filter_rules", """
        ini_set('display_errors', 0);
        // Restored. Removing these to test whether they were implicated in
        // a persistent, reproducible "this rule does not exist" failure
        // changed nothing about it — identical error, identical wording,
        // against the real firewall. That experiment is what ruled the
        // requires out; there is no remaining reason to diverge from
        // `saveRule` and `deleteRule`, which keep them.
        require_once '/etc/inc/util.inc';
        require_once '/etc/inc/filter.inc';
        // Confirmed the actual, load-bearing cause by direct A/B test against
        // the real firewall, not by reasoning about scope from source alone:
        // this exact validation logic, run with a hardcoded, definitely-correct
        // interface and item list — bypassing payload decoding entirely —
        // still failed live, identically to every prior attempt, while an
        // otherwise near-identical probe that explicitly declared this
        // succeeded at the same moment against the same $config. Every other
        // working snippet in this file declares it; this one and the four
        // rule/NAT save or delete writes silently did not. A later audit found
        // that Quick Block shared the same omission as well.
        global $config;
        $toreturn = [];
        $vaktpost_payload = "\(encoded)";
        \(decodePayload)

        $vaktpost_interface = strval($vaktpost_input["interface"] ?? "");
        $vaktpost_items = $vaktpost_input["items"] ?? [];

        if ($vaktpost_interface === "" || !is_array($vaktpost_items) || empty($vaktpost_items)) {
          $toreturn["status"] = "invalid";
          $toreturn["error"] = "An interface and a non-empty order are required.";
        } else {
          $vaktpost_section = $config["filter"];
          $vaktpost_rules = (is_array($vaktpost_section) && is_iterable($vaktpost_section["rule"])) ? $vaktpost_section["rule"] : [];

          // The reorderable subset: this interface's own rules, never a
          // floating rule. A genuinely floating rule's interface normalises
          // to a comma-joined list of two or more names, which a single
          // interface name can never exactly equal — still true after the
          // normalisation just below, so no separate exclusion is needed for
          // it. What that normalisation is actually for is different: a rule
          // scoped to exactly one interface can still have its `interface`
          // field stored as a one-element array rather than a bare string —
          // confirmed on a live firewall, not assumed — and joining a single
          // element produces that same element back with no comma at all,
          // so it reads identically to a bare string once normalised and was
          // silently excluded from every match before this did.
          $vaktpost_by_tracker = [];
          $vaktpost_original_trackers = [];
          foreach ($vaktpost_rules as $vaktpost_r) {
            if (!is_array($vaktpost_r)) { continue; }
            // pfSense stores a rule's interface as a plain string for most
            // rules, but as an array for some — confirmed against a live
            // firewall, not assumed: two genuinely single-interface rules
            // read back with `interface` as a one-element array. Read
            // correctly here, `FirewallRule.interfaceName` on the Swift side
            // already joins an array the same way, which is why the display
            // and this comparison now agree instead of one silently seeing
            // "opt5" and the other silently seeing the literal string "Array"
            // that PHP produces when a plain strval() meets an array.
            $vaktpost_r_iface = $vaktpost_r["interface"] ?? "";
            $vaktpost_r_iface = is_array($vaktpost_r_iface) ? implode(",", $vaktpost_r_iface) : strval($vaktpost_r_iface);
            if ($vaktpost_r_iface !== $vaktpost_interface) { continue; }
            $vaktpost_t = strval($vaktpost_r["tracker"] ?? "");
            if ($vaktpost_t === "") { continue; }
            $vaktpost_by_tracker[$vaktpost_t] = $vaktpost_r;
            $vaktpost_original_trackers[] = $vaktpost_t;
          }

          $vaktpost_sep_section = $config["filter"];
          $vaktpost_all_seps = is_array($vaktpost_sep_section) ? ($vaktpost_sep_section["separator"] ?? []) : [];
          $vaktpost_existing_seps = (is_array($vaktpost_all_seps) && is_array($vaktpost_all_seps[$vaktpost_interface] ?? null))
            ? $vaktpost_all_seps[$vaktpost_interface] : [];

          // The submitted order must be a permutation of exactly what
          // already exists — never a way to add, drop, or move in a rule or
          // separator this operation was not asked to touch.
          $vaktpost_submitted_rule_trackers = [];
          $vaktpost_submitted_sep_keys = [];
          $vaktpost_shape_valid = true;
          foreach ($vaktpost_items as $vaktpost_item) {
            if (!is_array($vaktpost_item)) { $vaktpost_shape_valid = false; break; }
            $vaktpost_kind = strval($vaktpost_item["kind"] ?? "");
            $vaktpost_id = strval($vaktpost_item["id"] ?? "");
            if ($vaktpost_id === "") { $vaktpost_shape_valid = false; break; }
            if ($vaktpost_kind === "rule") {
              $vaktpost_submitted_rule_trackers[] = $vaktpost_id;
            } elseif ($vaktpost_kind === "separator") {
              $vaktpost_submitted_sep_keys[] = $vaktpost_id;
            } else {
              $vaktpost_shape_valid = false;
              break;
            }
          }

          $vaktpost_rules_match = $vaktpost_shape_valid
            && count($vaktpost_submitted_rule_trackers) === count($vaktpost_original_trackers)
            && count(array_diff($vaktpost_submitted_rule_trackers, $vaktpost_original_trackers)) === 0
            && count(array_diff($vaktpost_original_trackers, $vaktpost_submitted_rule_trackers)) === 0;

          $vaktpost_existing_sep_keys = array_keys($vaktpost_existing_seps);
          $vaktpost_seps_match = count($vaktpost_submitted_sep_keys) === count($vaktpost_existing_sep_keys)
            && count(array_diff($vaktpost_submitted_sep_keys, $vaktpost_existing_sep_keys)) === 0
            && count(array_diff($vaktpost_existing_sep_keys, $vaktpost_submitted_sep_keys)) === 0;

          if (!$vaktpost_shape_valid || !$vaktpost_rules_match || !$vaktpost_seps_match) {
            // The generic message this used to return told nobody anything —
            // not which rule, not which side had it, not even whether rules
            // or separators were the problem. On a genuine mismatch this is
            // the only chance to see what actually disagreed before trying
            // again blind, so the specific difference is computed and
            // reported rather than only the fact that one exists.
            //
            // A hardcoded, realistic reproduction of this exact validation
            // logic against a synthetic copy of this exact ruleset passed —
            // no mismatch, run outside the payload path entirely. That rules
            // the validation logic out and points at how this specific value
            // gets from Swift into this variable, which is what these two
            // lines exist to finally see directly rather than infer.
            // The raw base64 was here before this and was worse than
            // useless: reading it back required transcribing dense,
            // multi-line, wrapped text out of a screenshot by hand, and a
            // single misread character there produces a plausible-looking
            // but wrong reconstruction with no way to tell it apart from a
            // real finding. Decoded already, in the one place that cannot
            // introduce that error: the parsed items array, exactly as this
            // snippet itself understood the submission, kind and id for
            // each entry in submitted order.
            $vaktpost_items_summary = [];
            foreach ($vaktpost_items as $vaktpost_summary_item) {
              $vaktpost_items_summary[] = is_array($vaktpost_summary_item)
                ? (strval($vaktpost_summary_item["kind"] ?? "?") . ":" . strval($vaktpost_summary_item["id"] ?? "?"))
                : "(not an object)";
            }
            $vaktpost_detail = [
              "submitted items in order: " . implode(", ", $vaktpost_items_summary),
              "decoded interface as hex: " . bin2hex($vaktpost_interface),
            ];
            if (!$vaktpost_shape_valid) {
              $vaktpost_detail[] = "the submitted order contains an item with no kind or id";
            }
            if ($vaktpost_shape_valid && !$vaktpost_rules_match) {
              $vaktpost_missing_rules = array_diff($vaktpost_original_trackers, $vaktpost_submitted_rule_trackers);
              $vaktpost_extra_rules = array_diff($vaktpost_submitted_rule_trackers, $vaktpost_original_trackers);
              if (!empty($vaktpost_missing_rules)) {
                $vaktpost_detail[] = "missing from the order: " . implode(", ", $vaktpost_missing_rules);
              }
              if (!empty($vaktpost_extra_rules)) {
                // "Not currently on this interface" answered which trackers
                // disagreed and stopped there — it did not say where the
                // firewall actually thinks they are, which is exactly the
                // next question a person asks after reading it. Looked up
                // once here, across the whole ruleset, rather than left for
                // a second guess: an interface-naming mismatch (a rule whose
                // real `interface` value differs from the one this screen is
                // scoped to, despite both resolving to the same display
                // label) and a rule genuinely removed since it was fetched
                // produce the same bare tracker number, and read very
                // differently once this says which it is.
                $vaktpost_located = [];
                foreach ($vaktpost_extra_rules as $vaktpost_extra_tracker) {
                  $vaktpost_found_elsewhere = null;
                  foreach ($vaktpost_rules as $vaktpost_any_rule) {
                    if (is_array($vaktpost_any_rule)
                        && strval($vaktpost_any_rule["tracker"] ?? "") === $vaktpost_extra_tracker) {
                      $vaktpost_any_iface = $vaktpost_any_rule["interface"] ?? "(no interface field)";
                      $vaktpost_found_elsewhere = is_array($vaktpost_any_iface)
                        ? implode(",", $vaktpost_any_iface) : strval($vaktpost_any_iface);
                      break;
                    }
                  }
                  $vaktpost_located[] = $vaktpost_extra_tracker . " (" .
                    ($vaktpost_found_elsewhere !== null
                      // Single-quoted PHP strings, not double-quoted with an
                      // escaped `"` inside — this project's own gate refuses
                      // any backslash in a snippet body outright, and a
                      // literal quote character needs none at all this way.
                      ? 'actually on "' . $vaktpost_found_elsewhere . '"'
                      : "no longer exists anywhere in the ruleset") . ")";
                }
                $vaktpost_detail[] = 'not currently on "' . $vaktpost_interface . '": ' . implode(", ", $vaktpost_located);
              }
            }
            if ($vaktpost_shape_valid && !$vaktpost_seps_match) {
              $vaktpost_missing_seps = array_diff($vaktpost_existing_sep_keys, $vaktpost_submitted_sep_keys);
              $vaktpost_extra_seps = array_diff($vaktpost_submitted_sep_keys, $vaktpost_existing_sep_keys);
              if (!empty($vaktpost_missing_seps)) {
                $vaktpost_detail[] = "separators missing from the order: " . implode(", ", $vaktpost_missing_seps);
              }
              if (!empty($vaktpost_extra_seps)) {
                $vaktpost_detail[] = "separators not currently on this interface: " . implode(", ", $vaktpost_extra_seps);
              }
            }
            // Two rounds of this reported specific missing or extra trackers
            // and keys, and the same two trackers kept coming back "no
            // longer exists anywhere" regardless. That answers whether a
            // mismatch exists, but not the more useful question: what does
            // the firewall actually have on this interface right now,
            // independent of anything the app believes? Reported plainly
            // here — every tracker and description currently on this
            // interface, every separator key and its text — so the two
            // sides of the disagreement are both visible in the same
            // message rather than one being inferred from the other.
            $vaktpost_current_summary = [];
            foreach ($vaktpost_original_trackers as $vaktpost_cur_tracker) {
              $vaktpost_cur_rule = $vaktpost_by_tracker[$vaktpost_cur_tracker];
              $vaktpost_current_summary[] = $vaktpost_cur_tracker . ' ("' .
                strval($vaktpost_cur_rule["descr"] ?? "") . '")';
            }
            foreach ($vaktpost_existing_sep_keys as $vaktpost_cur_sep_key) {
              $vaktpost_cur_sep = $vaktpost_existing_seps[$vaktpost_cur_sep_key];
              $vaktpost_current_summary[] = $vaktpost_cur_sep_key . ' ("' .
                strval($vaktpost_cur_sep["text"] ?? "") . '", separator)';
            }
            $vaktpost_detail[] = 'currently on "' . $vaktpost_interface . '": '
              . (empty($vaktpost_current_summary) ? "(nothing)" : implode(", ", $vaktpost_current_summary));
            // pfSense caches its parsed configuration at /tmp/config.cache
            // and reads from that cache rather than reparsing config.xml on
            // every request, refreshing it only when write_config() properly
            // invalidates it. Removing this snippet's require_once lines
            // changed nothing about the failure, which rules out those two
            // files specifically -- but not a stale cache read further back,
            // in whatever loads $config before this snippet's own code ever
            // runs. Checked directly here, read-only, rather than guessed at
            // again: whether the file exists, when it was last written, and
            // whether the missing trackers appear in it as plain text --
            // cheap enough to always include once a mismatch has already
            // happened, and worth far more than another blind hypothesis.
            $vaktpost_cache_path = "/tmp/config.cache";
            if (file_exists($vaktpost_cache_path)) {
              $vaktpost_cache_age = time() - filemtime($vaktpost_cache_path);
              $vaktpost_cache_text = file_get_contents($vaktpost_cache_path);
              $vaktpost_cache_hits = [];
              foreach ($vaktpost_extra_rules as $vaktpost_check_tracker) {
                if ($vaktpost_cache_text !== false && strpos($vaktpost_cache_text, $vaktpost_check_tracker) !== false) {
                  $vaktpost_cache_hits[] = $vaktpost_check_tracker;
                }
              }
              $vaktpost_detail[] = "config.cache is " . $vaktpost_cache_age . "s old"
                . (empty($vaktpost_cache_hits)
                  ? "; the missing trackers do not appear in it as text either"
                  : "; these missing trackers DO appear in it as text: " . implode(", ", $vaktpost_cache_hits));
            } else {
              $vaktpost_detail[] = "config.cache does not exist";
            }
            $toreturn["status"] = "mismatch";
            // Colon, not a parenthesis, ahead of the detail clause: the
            // publish gate's function-call scanner reads PHP string contents
            // the same as PHP syntax and cannot tell "exactly (" here from an
            // actual call to a function named exactly. Rephrasing is the fix,
            // not loosening what the gate checks.
            $toreturn["error"] = "The submitted order does not match this interface's current rules and separators exactly: "
              . implode("; ", $vaktpost_detail) . ".";
          } else {
            $vaktpost_new_subset = [];
            $vaktpost_new_seps = $vaktpost_existing_seps;
            $vaktpost_preceding = 0;
            foreach ($vaktpost_items as $vaktpost_item) {
              $vaktpost_kind = strval($vaktpost_item["kind"] ?? "");
              $vaktpost_id = strval($vaktpost_item["id"] ?? "");
              if ($vaktpost_kind === "rule") {
                $vaktpost_new_subset[] = $vaktpost_by_tracker[$vaktpost_id];
                $vaktpost_preceding = $vaktpost_preceding + 1;
              } else {
                $vaktpost_new_seps[$vaktpost_id]["row"] = ["fr" . $vaktpost_preceding];
              }
            }

            // Splice back into the global array. Every rule belonging to
            // another interface, or a floating rule, stays in its exact
            // original slot; every slot that belonged to this interface is
            // replaced, in order, with the new arrangement.
            $vaktpost_cursor = 0;
            $vaktpost_reassembled = [];
            foreach ($vaktpost_rules as $vaktpost_r) {
              $vaktpost_reassemble_iface = $vaktpost_r["interface"] ?? "";
              $vaktpost_reassemble_iface = is_array($vaktpost_reassemble_iface)
                ? implode(",", $vaktpost_reassemble_iface) : strval($vaktpost_reassemble_iface);
              if (is_array($vaktpost_r) && $vaktpost_reassemble_iface === $vaktpost_interface) {
                $vaktpost_reassembled[] = $vaktpost_new_subset[$vaktpost_cursor];
                $vaktpost_cursor = $vaktpost_cursor + 1;
              } else {
                $vaktpost_reassembled[] = $vaktpost_r;
              }
            }

            $config["filter"]["rule"] = array_values($vaktpost_reassembled);
            if (!is_array($config["filter"]["separator"] ?? null)) { $config["filter"]["separator"] = []; }
            $config["filter"]["separator"][$vaktpost_interface] = $vaktpost_new_seps;

            // Built from the payload-decoded variable, not from a Swift
            // interpolation of the caller's `interface` argument — the whole
            // point of the payload is that no runtime string reaches PHP
            // source directly.
            $vaktpost_audit_session_started = false;
            if (session_status() !== PHP_SESSION_ACTIVE) {
              $vaktpost_audit_session_started = session_start([
                "use_cookies" => 0, "use_only_cookies" => 0, "use_strict_mode" => 0
              ]);
            }
            $vaktpost_authenticated_user = trim(strval($_SERVER["PHP_AUTH_USER"] ?? ""));
            if ($vaktpost_authenticated_user !== "") {
              $_SESSION["Username"] = $vaktpost_authenticated_user;
              $vaktpost_authcfg = auth_get_authserver(config_get_path("system/webgui/authmode"));
              if (is_array($vaktpost_authcfg)) {
                $vaktpost_auth_type = trim(strval($vaktpost_authcfg["type"] ?? ""));
                $vaktpost_auth_name = trim(strval($vaktpost_authcfg["name"] ?? ""));
                if ($vaktpost_auth_type === "" || $vaktpost_auth_type === "Local Auth") {
                  $_SESSION["authsource"] = "Local Database";
                } else {
                  $_SESSION["authsource"] = strtoupper($vaktpost_auth_type)
                    . ($vaktpost_auth_name === "" ? "" : "/" . $vaktpost_auth_name);
                }
              }
            }
            write_config("Vaktpost: reordered rules on " . $vaktpost_interface);
            if ($vaktpost_audit_session_started) {
              if (session_status() !== PHP_SESSION_ACTIVE) {
                session_start(["use_cookies" => 0, "use_only_cookies" => 0, "use_strict_mode" => 0]);
              }
              if (session_status() === PHP_SESSION_ACTIVE) {
                $_SESSION = [];
                session_destroy();
              }
            }
            mark_subsystem_dirty("filter");
            $toreturn["status"] = "ok";
            $toreturn["apply_pending"] = true;
            $toreturn["order"] = $vaktpost_submitted_rule_trackers;
          }
        }
        """)
    }

    // The body is a reviewed static PHP literal, not complex Swift control flow.
    // swiftlint:disable:next function_body_length
    static func reorderNatRules(items: [JSONValue]) -> PHPSnippet {
        let encoded = payload(JSONDict(["items": .array(items)]))
        return PHPSnippet("reorder_nat_rules", """
        ini_set('display_errors', 0);
        require_once '/etc/inc/util.inc';
        require_once '/etc/inc/filter.inc';
        global $config;
        $toreturn = [];
        $vaktpost_payload = "\(encoded)";
        \(decodePayload)

        $vaktpost_items = $vaktpost_input["items"] ?? [];
        $vaktpost_nat = is_array($config["nat"] ?? null) ? $config["nat"] : [];
        $vaktpost_rules = is_array($vaktpost_nat["rule"] ?? null)
          ? array_values($vaktpost_nat["rule"]) : [];
        $vaktpost_separators = is_array($vaktpost_nat["separator"] ?? null)
          ? $vaktpost_nat["separator"] : [];

        if (!is_array($vaktpost_items) || empty($vaktpost_items)) {
          $toreturn["status"] = "invalid";
          $toreturn["error"] = "A non-empty NAT order is required.";
        } elseif (count($vaktpost_items) !== count($vaktpost_rules) + count($vaktpost_separators)) {
          $toreturn["status"] = "mismatch";
          $toreturn["error"] = "The NAT rules or separators changed since this order was prepared.";
        } else {
          $vaktpost_seen_rules = [];
          $vaktpost_seen_separators = [];
          $vaktpost_reordered = [];
          $vaktpost_reordered_separators = [];
          $vaktpost_preceding_rules = 0;
          $vaktpost_valid = true;
          $vaktpost_error = "";

          foreach ($vaktpost_items as $vaktpost_item) {
            if (!is_array($vaktpost_item)) {
              $vaktpost_valid = false;
              $vaktpost_error = "The submitted NAT order contains an invalid item.";
              break;
            }
            $vaktpost_kind = strval($vaktpost_item["kind"] ?? "rule");
            if ($vaktpost_kind === "separator") {
              $vaktpost_separator_key = strval($vaktpost_item["id"] ?? "");
              if ($vaktpost_separator_key === ""
                  || !array_key_exists($vaktpost_separator_key, $vaktpost_separators)
                  || array_key_exists($vaktpost_separator_key, $vaktpost_seen_separators)) {
                $vaktpost_valid = false;
                $vaktpost_error = "The submitted NAT order contains an invalid separator.";
                break;
              }
              $vaktpost_seen_separators[$vaktpost_separator_key] = true;
              $vaktpost_separator = $vaktpost_separators[$vaktpost_separator_key];
              if (!is_array($vaktpost_separator)) {
                $vaktpost_valid = false;
                $vaktpost_error = "A NAT separator is not an object.";
                break;
              }
              $vaktpost_separator["row"] = [
                "fr" . $vaktpost_preceding_rules
              ];
              $vaktpost_reordered_separators[$vaktpost_separator_key] = $vaktpost_separator;
              continue;
            }
            if ($vaktpost_kind !== "rule"
                || !array_key_exists("original_index", $vaktpost_item)) {
              $vaktpost_valid = false;
              $vaktpost_error = "The submitted NAT order contains an invalid item kind.";
              break;
            }
            $vaktpost_index = intval($vaktpost_item["original_index"]);
            if ($vaktpost_index < 0 || $vaktpost_index >= count($vaktpost_rules)
                || array_key_exists(strval($vaktpost_index), $vaktpost_seen_rules)) {
              $vaktpost_valid = false;
              $vaktpost_error = "The submitted NAT order contains an invalid or duplicate position.";
              break;
            }

            $vaktpost_rule = $vaktpost_rules[$vaktpost_index];
            if (!is_array($vaktpost_rule)) {
              $vaktpost_valid = false;
              $vaktpost_error = "A NAT rule is not an object.";
              break;
            }

            $vaktpost_iface = $vaktpost_rule["interface"] ?? "";
            $vaktpost_iface = is_array($vaktpost_iface)
              ? implode(",", $vaktpost_iface) : strval($vaktpost_iface);
            $vaktpost_destination = $vaktpost_rule["destination"] ?? [];
            $vaktpost_destination_kind = "any";
            $vaktpost_destination_address = "any";
            if (is_array($vaktpost_destination)) {
              if (array_key_exists("network", $vaktpost_destination)) {
                $vaktpost_destination_kind = "network";
                $vaktpost_destination_address = strval($vaktpost_destination["network"]);
              } elseif (array_key_exists("address", $vaktpost_destination)) {
                $vaktpost_destination_address = strval($vaktpost_destination["address"]);
                $vaktpost_destination_kind = in_array($vaktpost_destination_address, ["any", "ANY"], true)
                  ? "any" : "address";
              }
            } elseif (strval($vaktpost_destination) !== "") {
              $vaktpost_destination_address = strval($vaktpost_destination);
              $vaktpost_destination_kind = in_array($vaktpost_destination_address, ["any", "ANY"], true)
                ? "any" : "address";
            }
            // pfSense stores a NAT destination port inside the destination
            // object (`destination/port`). Older Vaktpost builds wrote the
            // filter-rule-style flat `destination_port` key, so retain that
            // only as a migration fallback when identifying a row.
            $vaktpost_destination_port = is_array($vaktpost_destination)
              ? strval($vaktpost_destination["port"] ?? ($vaktpost_rule["destination_port"] ?? ""))
              : strval($vaktpost_rule["destination_port"] ?? "");

            $vaktpost_matches = strval($vaktpost_item["tracker"] ?? "")
                === strval($vaktpost_rule["tracker"] ?? "")
              && strval($vaktpost_item["interface"] ?? "") === $vaktpost_iface
              && strval($vaktpost_item["destination_kind"] ?? "") === $vaktpost_destination_kind
              && strval($vaktpost_item["destination_address"] ?? "") === $vaktpost_destination_address
              && strval($vaktpost_item["destination_port"] ?? "")
                === $vaktpost_destination_port
              && strval($vaktpost_item["target"] ?? "")
                === strval($vaktpost_rule["target"] ?? "")
              && strval($vaktpost_item["local_port"] ?? "")
                === strval($vaktpost_rule["local-port"] ?? ($vaktpost_rule["local_port"] ?? ""));
            if (!$vaktpost_matches) {
              $vaktpost_valid = false;
              $vaktpost_error = "A NAT rule changed since this order was prepared.";
              break;
            }

            $vaktpost_seen_rules[strval($vaktpost_index)] = true;
            $vaktpost_reordered[] = $vaktpost_rule;
            $vaktpost_preceding_rules = $vaktpost_preceding_rules + 1;
          }

          if (!$vaktpost_valid
              || count($vaktpost_seen_rules) !== count($vaktpost_rules)
              || count($vaktpost_seen_separators) !== count($vaktpost_separators)) {
            $toreturn["status"] = "mismatch";
            $toreturn["error"] = $vaktpost_error === ""
              ? "The submitted NAT order is incomplete." : $vaktpost_error;
          } else {
            $config["nat"]["rule"] = array_values($vaktpost_reordered);
            $config["nat"]["separator"] = $vaktpost_reordered_separators;
            $vaktpost_audit_session_started = false;
            if (session_status() !== PHP_SESSION_ACTIVE) {
              $vaktpost_audit_session_started = session_start([
                "use_cookies" => 0, "use_only_cookies" => 0, "use_strict_mode" => 0
              ]);
            }
            $vaktpost_authenticated_user = trim(strval($_SERVER["PHP_AUTH_USER"] ?? ""));
            if ($vaktpost_authenticated_user !== "") {
              $_SESSION["Username"] = $vaktpost_authenticated_user;
              $vaktpost_authcfg = auth_get_authserver(config_get_path("system/webgui/authmode"));
              if (is_array($vaktpost_authcfg)) {
                $vaktpost_auth_type = trim(strval($vaktpost_authcfg["type"] ?? ""));
                $vaktpost_auth_name = trim(strval($vaktpost_authcfg["name"] ?? ""));
                if ($vaktpost_auth_type === "" || $vaktpost_auth_type === "Local Auth") {
                  $_SESSION["authsource"] = "Local Database";
                } else {
                  $_SESSION["authsource"] = strtoupper($vaktpost_auth_type)
                    . ($vaktpost_auth_name === "" ? "" : "/" . $vaktpost_auth_name);
                }
              }
            }
            write_config("Vaktpost: reordered NAT port forwards and separators");
            if ($vaktpost_audit_session_started) {
              if (session_status() !== PHP_SESSION_ACTIVE) {
                session_start(["use_cookies" => 0, "use_only_cookies" => 0, "use_strict_mode" => 0]);
              }
              if (session_status() === PHP_SESSION_ACTIVE) {
                $_SESSION = [];
                session_destroy();
              }
            }
            mark_subsystem_dirty("natconf");
            $toreturn["status"] = "ok";
            $toreturn["apply_pending"] = true;
          }
        }
        """)
    }

    static func deleteNatRule(tracker: String) -> PHPSnippet {
        let encoded = payload(JSONDict(["tracker": .string(tracker)]))
        return PHPSnippet("delete_nat_rule", """
        ini_set('display_errors', 0);
        require_once '/etc/inc/util.inc';
        require_once '/etc/inc/filter.inc';
        global $config;
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
          $vaktpost_audit_session_started = false;
          if (session_status() !== PHP_SESSION_ACTIVE) {
            $vaktpost_audit_session_started = session_start([
              "use_cookies" => 0, "use_only_cookies" => 0, "use_strict_mode" => 0
            ]);
          }
          $vaktpost_authenticated_user = trim(strval($_SERVER["PHP_AUTH_USER"] ?? ""));
          if ($vaktpost_authenticated_user !== "") {
            $_SESSION["Username"] = $vaktpost_authenticated_user;
            $vaktpost_authcfg = auth_get_authserver(config_get_path("system/webgui/authmode"));
            if (is_array($vaktpost_authcfg)) {
              $vaktpost_auth_type = trim(strval($vaktpost_authcfg["type"] ?? ""));
              $vaktpost_auth_name = trim(strval($vaktpost_authcfg["name"] ?? ""));
              if ($vaktpost_auth_type === "" || $vaktpost_auth_type === "Local Auth") {
                $_SESSION["authsource"] = "Local Database";
              } else {
                $_SESSION["authsource"] = strtoupper($vaktpost_auth_type)
                  . ($vaktpost_auth_name === "" ? "" : "/" . $vaktpost_auth_name);
              }
            }
          }
          write_config("Vaktpost: deleted a nat rule");
          if ($vaktpost_audit_session_started) {
            if (session_status() !== PHP_SESSION_ACTIVE) {
              session_start(["use_cookies" => 0, "use_only_cookies" => 0, "use_strict_mode" => 0]);
            }
            if (session_status() === PHP_SESSION_ACTIVE) {
              $_SESSION = [];
              session_destroy();
            }
          }
          mark_subsystem_dirty("natconf");
          $toreturn["status"] = "ok";
          $toreturn["apply_pending"] = true;
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
    /// Its body is a reviewed static PHP literal, not complex Swift control flow.
    static func saveRule(rule: JSONDict) -> PHPSnippet { // swiftlint:disable:this function_body_length
        let encoded = payload(rule)
        return PHPSnippet("save_rule", """
        ini_set('display_errors', 0);
        require_once '/etc/inc/util.inc';
        require_once '/etc/inc/filter.inc';
        global $config;
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
              if (!is_array($vaktpost_existing)
                  || strval($vaktpost_existing["tracker"] ?? "") !== $vaktpost_before) { continue; }
              // Same normalisation as the reorder snippet, and for the same
              // confirmed reason: pfSense stores some rules' `interface` as a
              // one-element array rather than a bare string, and a plain
              // strval() on an array silently produces the literal string
              // "Array" — which then never matches a real interface name, so
              // a perfectly valid anchor on such a rule was rejected as if it
              // belonged to a different interface entirely.
              $vaktpost_anchor_iface = $vaktpost_existing["interface"] ?? "";
              $vaktpost_anchor_iface = is_array($vaktpost_anchor_iface)
                ? implode(",", $vaktpost_anchor_iface) : strval($vaktpost_anchor_iface);
              if ($vaktpost_anchor_iface === $vaktpost_interface) {
                $vaktpost_anchor_found = true;
                break;
              }
            }
            $vaktpost_position_valid = $vaktpost_anchor_found;
          }
        }
        if ($found && $vaktpost_placement === "keep") {
          // "Keep" is an interface-local promise. Once the interface changes
          // there is no current position there to preserve. Normalised the
          // same way as the anchor check just above, for the identical
          // reason: the rule being edited may itself be one whose interface
          // is stored as a one-element array.
          $vaktpost_keep_iface = $rule["interface"] ?? "";
          $vaktpost_keep_iface = is_array($vaktpost_keep_iface)
            ? implode(",", $vaktpost_keep_iface) : strval($vaktpost_keep_iface);
          if ($vaktpost_keep_iface !== $vaktpost_interface) {
            $vaktpost_position_valid = false;
          }
        }

        // Rebuild each side from one explicit native shape. `any`, a pfSense
        // system selector and a literal/alias are not interchangeable keys in
        // config.xml. Validate the exact shape with pfSense itself before the
        // copy of `$config` is changed.
        $vaktpost_payload_valid = true;
        $vaktpost_validation_error = "";
        $vaktpost_sides = [];
        foreach (["source", "destination"] as $vaktpost_side_name) {
          $vaktpost_side = $vaktpost_input[$vaktpost_side_name] ?? [];
          if (!is_array($vaktpost_side)) {
            $vaktpost_payload_valid = false;
            $vaktpost_validation_error = "The " . $vaktpost_side_name . " address has no valid type";
            break;
          }
          $vaktpost_type_count = (($vaktpost_side["any"] ?? false) === true ? 1 : 0)
            + (array_key_exists("network", $vaktpost_side) ? 1 : 0)
            + (array_key_exists("address", $vaktpost_side) ? 1 : 0);
          if ($vaktpost_type_count !== 1) {
            $vaktpost_payload_valid = false;
            $vaktpost_validation_error = "The " . $vaktpost_side_name . " address must have one type";
            break;
          }
          if (($vaktpost_side["any"] ?? false) === true) {
            $vaktpost_sides[$vaktpost_side_name] = ["any" => true];
          } elseif (array_key_exists("network", $vaktpost_side)) {
            $vaktpost_value = trim(strval($vaktpost_side["network"] ?? ""));
            $vaktpost_special = get_specialnet($vaktpost_value, [
              SPECIALNET_SELF, SPECIALNET_CLIENTS, SPECIALNET_IFADDR,
              SPECIALNET_IFNET, SPECIALNET_GROUP
            ]);
            if ($vaktpost_value === "" || !$vaktpost_special) {
              $vaktpost_payload_valid = false;
              $vaktpost_validation_error = "The " . $vaktpost_side_name . " system selector is unavailable";
              break;
            }
            $vaktpost_sides[$vaktpost_side_name] = ["network" => $vaktpost_value];
          } elseif (array_key_exists("address", $vaktpost_side)) {
            $vaktpost_value = trim(strval($vaktpost_side["address"] ?? ""));
            $vaktpost_address_valid = $vaktpost_value !== "" && is_ipaddroralias($vaktpost_value);
            if (!$vaktpost_address_valid && strpos($vaktpost_value, "/") !== false) {
              $vaktpost_cidr = explode("/", $vaktpost_value, 2);
              $vaktpost_bits = strval($vaktpost_cidr[1] ?? "");
              $vaktpost_address_valid = count($vaktpost_cidr) === 2 && is_numeric($vaktpost_bits)
                && ((is_ipaddrv4($vaktpost_cidr[0]) && intval($vaktpost_bits) >= 0 && intval($vaktpost_bits) <= 32)
                  || (is_ipaddrv6($vaktpost_cidr[0]) && intval($vaktpost_bits) >= 0 && intval($vaktpost_bits) <= 128));
            }
            if (!$vaktpost_address_valid) {
              $vaktpost_payload_valid = false;
              $vaktpost_validation_error = "The " . $vaktpost_side_name . " address or alias is invalid";
              break;
            }
            $vaktpost_sides[$vaktpost_side_name] = ["address" => $vaktpost_value];
          } else {
            $vaktpost_payload_valid = false;
            $vaktpost_validation_error = "The " . $vaktpost_side_name . " address has no valid type";
            break;
          }
        }
        foreach (["source_port", "destination_port"] as $vaktpost_port_name) {
          $vaktpost_port_value = trim(strval($vaktpost_input[$vaktpost_port_name] ?? ""));
          $vaktpost_port_valid = $vaktpost_port_value === "" || is_port_or_alias($vaktpost_port_value);
          if (!$vaktpost_port_valid && strpos($vaktpost_port_value, "-") !== false) {
            $vaktpost_range = explode("-", $vaktpost_port_value, 2);
            $vaktpost_port_valid = count($vaktpost_range) === 2
              && is_numeric($vaktpost_range[0]) && is_numeric($vaktpost_range[1])
              && is_port_or_alias($vaktpost_range[0]) && is_port_or_alias($vaktpost_range[1])
              && intval($vaktpost_range[0]) <= intval($vaktpost_range[1]);
          }
          if (!$vaktpost_port_valid) {
            $vaktpost_payload_valid = false;
            $vaktpost_validation_error = "The " . $vaktpost_port_name . " value is invalid";
            break;
          }
        }
        $vaktpost_family = strval($vaktpost_input["ipprotocol"] ?? "");
        foreach ($vaktpost_sides as $vaktpost_side) {
          if (!array_key_exists("address", $vaktpost_side)) { continue; }
          $vaktpost_direct = explode("/", strval($vaktpost_side["address"]), 2)[0];
          if ((is_ipaddrv4($vaktpost_direct) && $vaktpost_family !== "inet")
              || (is_ipaddrv6($vaktpost_direct) && $vaktpost_family !== "inet6")) {
            $vaktpost_payload_valid = false;
            $vaktpost_validation_error = "A literal address does not match the selected IP version";
            break;
          }
        }
        $vaktpost_protocol = strval($vaktpost_input["protocol"] ?? "");
        if ((trim(strval($vaktpost_input["source_port"] ?? "")) !== ""
              || trim(strval($vaktpost_input["destination_port"] ?? "")) !== "")
            && !in_array($vaktpost_protocol, ["tcp", "udp", "tcp/udp"], true)) {
          $vaktpost_payload_valid = false;
          $vaktpost_validation_error = "Ports require TCP or UDP";
        }
        if (!array_key_exists($vaktpost_interface, get_configured_interface_with_descr())
            || !in_array(strval($vaktpost_input["type"] ?? ""), ["pass", "block", "reject"], true)
            || !in_array($vaktpost_protocol, ["any", "tcp", "udp", "tcp/udp", "icmp", "esp", "gre"], true)
            || !in_array($vaktpost_family, ["inet", "inet6", "inet46"], true)) {
          $vaktpost_payload_valid = false;
          $vaktpost_validation_error = "The rule type, protocol, IP version or interface is invalid";
        }

        if (!$vaktpost_create && !$found) {
          // Never turn a stale edit into an append. The rule may have been
          // removed after the app's preflight read and before this write.
          $toreturn["status"] = "not_found";
          $toreturn["error"] = "The rule tracker no longer exists";
        } elseif (!$vaktpost_position_valid) {
          $toreturn["status"] = "position_not_found";
          $toreturn["error"] = "The selected rule position is no longer available";
        } elseif (!$vaktpost_payload_valid) {
          $toreturn["status"] = "validation_failed";
          $toreturn["error"] = $vaktpost_validation_error;
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

        $rule["source"] = $vaktpost_sides["source"];
        $rule["destination"] = $vaktpost_sides["destination"];

        // Absent means absent. A port key left behind with an empty value is a
        // rule pfSense reads differently from one without the key at all.
        $vaktpost_sport = trim(strval($vaktpost_input["source_port"] ?? ""));
        if ($vaktpost_sport !== "") {
          $rule["source_port"] = $vaktpost_sport;
        } else {
          unset($rule["source_port"]);
        }
        $vaktpost_dport = trim(strval($vaktpost_input["destination_port"] ?? ""));
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
        $vaktpost_audit_session_started = false;
        if (session_status() !== PHP_SESSION_ACTIVE) {
          $vaktpost_audit_session_started = session_start([
            "use_cookies" => 0, "use_only_cookies" => 0, "use_strict_mode" => 0
          ]);
        }
        $vaktpost_authenticated_user = trim(strval($_SERVER["PHP_AUTH_USER"] ?? ""));
        if ($vaktpost_authenticated_user !== "") {
          $_SESSION["Username"] = $vaktpost_authenticated_user;
          $vaktpost_authcfg = auth_get_authserver(config_get_path("system/webgui/authmode"));
          if (is_array($vaktpost_authcfg)) {
            $vaktpost_auth_type = trim(strval($vaktpost_authcfg["type"] ?? ""));
            $vaktpost_auth_name = trim(strval($vaktpost_authcfg["name"] ?? ""));
            if ($vaktpost_auth_type === "" || $vaktpost_auth_type === "Local Auth") {
              $_SESSION["authsource"] = "Local Database";
            } else {
              $_SESSION["authsource"] = strtoupper($vaktpost_auth_type)
                . ($vaktpost_auth_name === "" ? "" : "/" . $vaktpost_auth_name);
            }
          }
        }
        write_config("Vaktpost: saved a rule");
        if ($vaktpost_audit_session_started) {
          if (session_status() !== PHP_SESSION_ACTIVE) {
            session_start(["use_cookies" => 0, "use_only_cookies" => 0, "use_strict_mode" => 0]);
          }
          if (session_status() === PHP_SESSION_ACTIVE) {
            $_SESSION = [];
            session_destroy();
          }
        }
        mark_subsystem_dirty("filter");
        $toreturn["status"] = "ok";
        $toreturn["apply_pending"] = true;
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
    /// Matching a NAT rule is not as simple as matching a filter rule.
    /// pfSense assigns every filter rule a tracker and keeps it stable, but it
    /// never assigns one to a NAT rule at all -- `firewall_nat_edit.php`
    /// identifies a port forward purely by its position in the array. A
    /// forward saved through the web GUI, or through a build of this app
    /// before it started writing trackers onto NAT rules, has no tracker to
    /// match on, and a version of this snippet that required one -- which is
    /// what this said until it was checked against real pfSense data --
    /// rejected every edit and every delete of every such forward,
    /// unconditionally, on every firewall.
    ///
    /// So matching tries the tracker first, where one exists, and falls back
    /// to the forward's own identity -- interface, destination, port and
    /// target, exactly as fetched before this payload's edits were applied --
    /// only when it does not. The fallback is deliberately narrow: it never
    /// runs for a create, and it only considers rows that themselves have no
    /// tracker, so it can never mistake one already-adopted forward for
    /// another. Whatever row it finds gets a real tracker assigned as part of
    /// this save, so the fallback is a one-time cost per forward -- the next
    /// edit finds it by tracker directly.
    ///
    /// What the fallback cannot do is find a row whose *own* identifying
    /// fields were changed in the same edit that is trying to match it -- if
    /// this is the first edit of a legacy forward and it also changes the
    /// destination port, there is nothing to match against, and it correctly
    /// falls through to becoming an append rather than guessing. That is the
    /// safe direction to fail in: a duplicate is visible and removable, a
    /// wrongly-matched row is neither. Changing an identifying field on a
    /// forward that already has a tracker is unaffected -- tracker matching
    /// does not care what else in the row changed.
    /// Its body is a reviewed static PHP literal, not complex Swift control flow.
    static func saveNatRule(rule: JSONDict) -> PHPSnippet { // swiftlint:disable:this function_body_length
        let encoded = payload(rule)
        return PHPSnippet("save_nat_rule", """
        ini_set('display_errors', 0);
        require_once '/etc/inc/util.inc';
        require_once '/etc/inc/filter.inc';
        global $config;
        $toreturn = [];
        $vaktpost_payload = "\(encoded)";
        \(decodePayload)

        $section = $config["nat"];
        $rules = (is_array($section) && is_iterable($section["rule"])) ? $section["rule"] : [];

        $tracker = strval($vaktpost_input["tracker"] ?? "");
        $vaktpost_if = strval($vaktpost_input["interface"] ?? "");
        $vaktpost_target = strval($vaktpost_input["target"] ?? "");
        // The port is part of what identifies a forward.
        //
        // Without it, two forwards to the same host on the same interface —
        // 80 and 443 to 10.0.0.5, which is an ordinary pair — have identical
        // interface, destination and target, so editing one replaced the
        // other. `PortForward.id` in the app has always included the port;
        // this had dropped it.
        $vaktpost_dstport = strval($vaktpost_input["destination_port"] ?? "");

        // pfSense assigns filter rules a tracker; it never assigns NAT rules
        // one. `firewall_nat_edit.php` identifies a port forward purely by its
        // position in the array. So a forward saved by the web GUI, or by a
        // build of this app before it started writing trackers onto NAT
        // rules, has no tracker at all -- and until this fallback existed,
        // editing or disabling such a forward always failed at the client-side
        // guard before any request was even sent, because the app had nothing
        // to send.
        //
        // These four are the forward's identity as it was *fetched*, before
        // any of the edits in this payload were applied. Matching on the NEW
        // values would fail exactly when someone edits one of the fields that
        // identifies the row -- moving it to a different port, say -- which is
        // an entirely ordinary thing to want to do.
        $vaktpost_orig_if = strval($vaktpost_input["original_interface"] ?? "");
        $vaktpost_orig_dst = $vaktpost_input["original_destination"] ?? [];
        $vaktpost_orig_dstaddr = "";
        if (is_array($vaktpost_orig_dst)) {
          if (($vaktpost_orig_dst["any"] ?? false) === true) {
            $vaktpost_orig_dstaddr = "any";
          } elseif (array_key_exists("network", $vaktpost_orig_dst)) {
            $vaktpost_orig_dstaddr = strval($vaktpost_orig_dst["network"]);
          } elseif (array_key_exists("address", $vaktpost_orig_dst)) {
            $vaktpost_orig_dstaddr = strval($vaktpost_orig_dst["address"]);
          }
        }
        $vaktpost_orig_dstport = strval($vaktpost_input["original_destination_port"] ?? "");
        $vaktpost_orig_target = strval($vaktpost_input["original_target"] ?? "");

        $vaktpost_create = ($vaktpost_input["create"] ?? false) ? true : false;
        $found = false;
        $vaktpost_index = null;
        $rule = [];

        // Creating means never matching. In particular, a duplicate must not
        // match the tracker of the forward it was copied from.
        foreach (($vaktpost_create ? [] : $rules) as $idx => $r) {
          if (!is_array($r)) { continue; }
          if ($tracker !== "" && strval($r["tracker"] ?? "") === $tracker) {
            $rule = $r;
            $vaktpost_index = $idx;
            $found = true;
            break;
          }
        }

        // Tried only when the row has no tracker of its own to look up by --
        // a forward this app has already saved once always has one by the
        // time this runs (see the tracker assignment below), so this path is
        // only ever reached for a rule nobody has edited through this app
        // yet, and it never runs at all for a create.
        if (!$found && !$vaktpost_create && $tracker === "" && $vaktpost_orig_if !== "") {
          foreach ($rules as $idx => $r) {
            if (!is_array($r) || !empty($r["tracker"])) { continue; }
            $vaktpost_rdst = $r["destination"] ?? [];
            $vaktpost_rdstaddr = "";
            if (is_array($vaktpost_rdst)) {
              if (($vaktpost_rdst["any"] ?? false) === true) {
                $vaktpost_rdstaddr = "any";
              } elseif (array_key_exists("network", $vaktpost_rdst)) {
                $vaktpost_rdstaddr = strval($vaktpost_rdst["network"]);
              } elseif (array_key_exists("address", $vaktpost_rdst)) {
                $vaktpost_rdstaddr = strval($vaktpost_rdst["address"]);
              }
            }
            // Native pfSense NAT rules keep the public port in
            // `destination/port`. Accept the old flat spelling only so an
            // affected Vaktpost rule can be opened once and migrated.
            $vaktpost_rdstport = is_array($vaktpost_rdst)
              ? strval($vaktpost_rdst["port"] ?? ($r["destination_port"] ?? ""))
              : strval($r["destination_port"] ?? "");
            if (strval($r["interface"] ?? "") === $vaktpost_orig_if
                && $vaktpost_rdstaddr === $vaktpost_orig_dstaddr
                && $vaktpost_rdstport === $vaktpost_orig_dstport
                && strval($r["target"] ?? "") === $vaktpost_orig_target) {
              $rule = $r;
              $vaktpost_index = $idx;
              $found = true;
              break;
            }
          }
        }

        $vaktpost_payload_valid = true;
        $vaktpost_validation_error = "";
        $vaktpost_sides = [];
        foreach (["source", "destination"] as $vaktpost_side_name) {
          $vaktpost_side = $vaktpost_input[$vaktpost_side_name] ?? [];
          if (!is_array($vaktpost_side)) {
            $vaktpost_payload_valid = false;
            $vaktpost_validation_error = "The " . $vaktpost_side_name . " address has no valid type";
            break;
          }
          $vaktpost_type_count = (($vaktpost_side["any"] ?? false) === true ? 1 : 0)
            + (array_key_exists("network", $vaktpost_side) ? 1 : 0)
            + (array_key_exists("address", $vaktpost_side) ? 1 : 0);
          if ($vaktpost_type_count !== 1) {
            $vaktpost_payload_valid = false;
            $vaktpost_validation_error = "The " . $vaktpost_side_name . " address must have one type";
            break;
          }
          if (($vaktpost_side["any"] ?? false) === true) {
            $vaktpost_sides[$vaktpost_side_name] = ["any" => true];
          } elseif (array_key_exists("network", $vaktpost_side)) {
            $vaktpost_value = trim(strval($vaktpost_side["network"] ?? ""));
            $vaktpost_special = get_specialnet($vaktpost_value, [
              SPECIALNET_SELF, SPECIALNET_CLIENTS, SPECIALNET_IFADDR,
              SPECIALNET_IFNET, SPECIALNET_GROUP
            ]);
            if ($vaktpost_value === "" || !$vaktpost_special) {
              $vaktpost_payload_valid = false;
              $vaktpost_validation_error = "The " . $vaktpost_side_name . " system selector is unavailable";
              break;
            }
            $vaktpost_sides[$vaktpost_side_name] = ["network" => $vaktpost_value];
          } elseif (array_key_exists("address", $vaktpost_side)) {
            $vaktpost_value = trim(strval($vaktpost_side["address"] ?? ""));
            $vaktpost_address_valid = $vaktpost_value !== "" && is_ipaddroralias($vaktpost_value);
            if (!$vaktpost_address_valid && strpos($vaktpost_value, "/") !== false) {
              $vaktpost_cidr = explode("/", $vaktpost_value, 2);
              $vaktpost_bits = strval($vaktpost_cidr[1] ?? "");
              $vaktpost_address_valid = count($vaktpost_cidr) === 2 && is_numeric($vaktpost_bits)
                && ((is_ipaddrv4($vaktpost_cidr[0]) && intval($vaktpost_bits) >= 0 && intval($vaktpost_bits) <= 32)
                  || (is_ipaddrv6($vaktpost_cidr[0]) && intval($vaktpost_bits) >= 0 && intval($vaktpost_bits) <= 128));
            }
            if (!$vaktpost_address_valid) {
              $vaktpost_payload_valid = false;
              $vaktpost_validation_error = "The " . $vaktpost_side_name . " address or alias is invalid";
              break;
            }
            $vaktpost_sides[$vaktpost_side_name] = ["address" => $vaktpost_value];
          } else {
            $vaktpost_payload_valid = false;
            $vaktpost_validation_error = "The " . $vaktpost_side_name . " address has no valid type";
            break;
          }
        }
        foreach (["destination_port", "local_port"] as $vaktpost_port_name) {
          $vaktpost_port_value = trim(strval($vaktpost_input[$vaktpost_port_name] ?? ""));
          $vaktpost_port_valid = $vaktpost_port_value === "" || is_port_or_alias($vaktpost_port_value);
          if (!$vaktpost_port_valid && strpos($vaktpost_port_value, "-") !== false) {
            $vaktpost_range = explode("-", $vaktpost_port_value, 2);
            $vaktpost_port_valid = count($vaktpost_range) === 2
              && is_numeric($vaktpost_range[0]) && is_numeric($vaktpost_range[1])
              && is_port_or_alias($vaktpost_range[0]) && is_port_or_alias($vaktpost_range[1])
              && intval($vaktpost_range[0]) <= intval($vaktpost_range[1]);
          }
          if (!$vaktpost_port_valid) {
            $vaktpost_payload_valid = false;
            $vaktpost_validation_error = "The " . $vaktpost_port_name . " value is invalid";
            break;
          }
        }
        $vaktpost_family = strval($vaktpost_input["ipprotocol"] ?? "");
        foreach ($vaktpost_sides as $vaktpost_side) {
          if (!array_key_exists("address", $vaktpost_side)) { continue; }
          $vaktpost_direct = explode("/", strval($vaktpost_side["address"]), 2)[0];
          if ((is_ipaddrv4($vaktpost_direct) && $vaktpost_family !== "inet")
              || (is_ipaddrv6($vaktpost_direct) && $vaktpost_family !== "inet6")) {
            $vaktpost_payload_valid = false;
            $vaktpost_validation_error = "A literal address does not match the selected IP version";
            break;
          }
        }
        $vaktpost_protocol = strval($vaktpost_input["protocol"] ?? "");
        $vaktpost_target_direct = explode("/", $vaktpost_target, 2)[0];
        if ((is_ipaddrv4($vaktpost_target_direct) && $vaktpost_family !== "inet")
            || (is_ipaddrv6($vaktpost_target_direct) && $vaktpost_family !== "inet6")) {
          $vaktpost_payload_valid = false;
          $vaktpost_validation_error = "The target does not match the selected IP version";
        }
        if ((trim(strval($vaktpost_input["destination_port"] ?? "")) !== ""
              || trim(strval($vaktpost_input["local_port"] ?? "")) !== "")
            && !in_array($vaktpost_protocol, ["tcp", "udp", "tcp/udp"], true)) {
          $vaktpost_payload_valid = false;
          $vaktpost_validation_error = "Ports require TCP or UDP";
        }
        if (!array_key_exists($vaktpost_if, get_configured_interface_with_descr())
            || !in_array($vaktpost_protocol, ["any", "tcp", "udp", "tcp/udp", "icmp", "esp", "gre"], true)
            || !in_array($vaktpost_family, ["inet", "inet6", "inet46"], true)
            || $vaktpost_target === "" || !is_ipaddroralias($vaktpost_target)) {
          $vaktpost_payload_valid = false;
          $vaktpost_validation_error = "The target, protocol, IP version or interface is invalid";
        }

        if (!$vaktpost_create && !$found) {
          $toreturn["status"] = "not_found";
          $toreturn["error"] = "The port-forward tracker no longer exists";
        } elseif (!$vaktpost_payload_valid) {
          $toreturn["status"] = "validation_failed";
          $toreturn["error"] = $vaktpost_validation_error;
        } else {
        $rule["interface"] = $vaktpost_if;
        $rule["protocol"] = strval($vaktpost_input["protocol"] ?? "any");
        $rule["ipprotocol"] = strval($vaktpost_input["ipprotocol"] ?? "inet");
        $rule["target"] = $vaktpost_target;
        $rule["descr"] = strval($vaktpost_input["descr"] ?? "");
        $rule["disabled"] = ($vaktpost_input["disabled"] ?? false) ? true : false;

        // Assigned whenever the row still has none: a fresh append never had
        // one, and a legacy row matched by its old identity above did not
        // either -- that was the whole reason the fallback matching ran.
        // Either way, this write leaves it with a real tracker, so the next
        // edit finds it directly and the fallback is not needed again.
        //
        // An ordinary edit of a row that already has one takes neither
        // branch: $rule already carries the tracker copied from $r, and
        // empty() on a non-empty string is false.
        if (empty($rule["tracker"] ?? "")) {
          $vaktpost_new_tracker = $tracker !== "" ? $tracker : strval(time());
          $vaktpost_collision = true;
          while ($vaktpost_collision) {
            $vaktpost_collision = false;
            foreach ($rules as $vaktpost_check_idx => $vaktpost_existing) {
              if ($vaktpost_check_idx === $vaktpost_index) { continue; }
              if (is_array($vaktpost_existing)
                  && strval($vaktpost_existing["tracker"] ?? "") === $vaktpost_new_tracker) {
                $vaktpost_new_tracker = strval(intval($vaktpost_new_tracker) + 1);
                $vaktpost_collision = true;
                break;
              }
            }
          }
          $tracker = $vaktpost_new_tracker;
          $rule["tracker"] = $tracker;
        }

        $rule["source"] = $vaktpost_sides["source"];
        $rule["destination"] = $vaktpost_sides["destination"];

        $vaktpost_dport = trim(strval($vaktpost_input["destination_port"] ?? ""));
        if ($vaktpost_dport !== "") {
          // Port forwards use pfSense's native nested destination port,
          // unlike filter rules which use a flat destination_port field.
          $rule["destination"]["port"] = $vaktpost_dport;
        } else {
          unset($rule["destination"]["port"]);
        }
        // Remove the non-native spelling written by earlier Vaktpost builds.
        unset($rule["destination_port"]);
        $vaktpost_lport = trim(strval($vaktpost_input["local_port"] ?? ""));
        if ($vaktpost_lport !== "") {
          // `local-port` is pfSense's native Redirect target port key.
          $rule["local-port"] = $vaktpost_lport;
        } else {
          unset($rule["local-port"]);
        }
        // Affected Vaktpost builds wrote this non-native spelling. Remove it
        // whenever the rule is saved so the native field above is canonical.
        unset($rule["local_port"]);

        if ($found) {
          $rules[$vaktpost_index] = $rule;
        } else {
          $rules[] = $rule;
        }
        $config["nat"]["rule"] = array_values($rules);
        $vaktpost_audit_session_started = false;
        if (session_status() !== PHP_SESSION_ACTIVE) {
          $vaktpost_audit_session_started = session_start([
            "use_cookies" => 0, "use_only_cookies" => 0, "use_strict_mode" => 0
          ]);
        }
        $vaktpost_authenticated_user = trim(strval($_SERVER["PHP_AUTH_USER"] ?? ""));
        if ($vaktpost_authenticated_user !== "") {
          $_SESSION["Username"] = $vaktpost_authenticated_user;
          $vaktpost_authcfg = auth_get_authserver(config_get_path("system/webgui/authmode"));
          if (is_array($vaktpost_authcfg)) {
            $vaktpost_auth_type = trim(strval($vaktpost_authcfg["type"] ?? ""));
            $vaktpost_auth_name = trim(strval($vaktpost_authcfg["name"] ?? ""));
            if ($vaktpost_auth_type === "" || $vaktpost_auth_type === "Local Auth") {
              $_SESSION["authsource"] = "Local Database";
            } else {
              $_SESSION["authsource"] = strtoupper($vaktpost_auth_type)
                . ($vaktpost_auth_name === "" ? "" : "/" . $vaktpost_auth_name);
            }
          }
        }
        write_config("Vaktpost: saved a nat rule");
        if ($vaktpost_audit_session_started) {
          if (session_status() !== PHP_SESSION_ACTIVE) {
            session_start(["use_cookies" => 0, "use_only_cookies" => 0, "use_strict_mode" => 0]);
          }
          if (session_status() === PHP_SESSION_ACTIVE) {
            $_SESSION = [];
            session_destroy();
          }
        }
        mark_subsystem_dirty("natconf");
        $toreturn["status"] = "ok";
        $toreturn["apply_pending"] = true;
        $toreturn["created"] = $vaktpost_create;
        $toreturn["tracker"] = $tracker;
        }
        """)
    }

    /// Throughput measured over HTTPS rather than shelling out to a CLI
    /// speedtest tool. This app's own write-boundary rules forbid every
    /// shell-execution path (`exec`, `system`, `shell_exec`, `proc_open`,
    /// and the rest) in every snippet but pfSense's own fixed updater —
    /// deliberately, since a shell reach would make the function allowlist
    /// meaningless. curl_exec() is not on that list: it makes an ordinary
    /// outbound HTTPS request, the same category of thing DNS lookups and
    /// ping already do here, so this measures real throughput without
    /// needing a package installed or an exception carved into that rule.
    ///
    /// speed.cloudflare.com is Cloudflare's own speed-test infrastructure —
    /// the same one behind their public DNS resolver's own speed-test page —
    /// a known payload size with no signup or key needed, reachable from
    /// any firewall with a working WAN.
    static let speedtest = PHPSnippet("speedtest", """
    ini_set('display_errors', 0);
    $toreturn = [];

    if (!function_exists('curl_init')) {
        $toreturn["available"] = false;
        $toreturn["reason"] = "PHP's curl extension is not available on this firewall.";
    } else {
        // Download first: a WAN that cannot reach the test server at all
        // should be reported here rather than after also waiting out the
        // upload leg's own timeout.
        $downloadBytes = 10000000;
        $downloadStart = microtime(true);
        $ch = curl_init("https://speed.cloudflare.com/__down?bytes=$downloadBytes");
        curl_setopt($ch, CURLOPT_RETURNTRANSFER, false);
        curl_setopt($ch, CURLOPT_WRITEFUNCTION, function ($handle, $data) { return strlen($data); });
        curl_setopt($ch, CURLOPT_TIMEOUT, 30);
        curl_setopt($ch, CURLOPT_CONNECTTIMEOUT, 10);
        curl_setopt($ch, CURLOPT_SSL_VERIFYPEER, true);
        $ok = curl_exec($ch);
        $connectTime = curl_getinfo($ch, CURLINFO_CONNECT_TIME);
        $downloadSize = curl_getinfo($ch, CURLINFO_SIZE_DOWNLOAD);
        $httpCode = curl_getinfo($ch, CURLINFO_HTTP_CODE);
        $curlError = curl_error($ch);
        curl_close($ch);
        $downloadElapsed = microtime(true) - $downloadStart;

        if ($ok === false || $httpCode !== 200 || $downloadSize <= 0 || $downloadElapsed <= 0) {
            $toreturn["available"] = false;
            $toreturn["reason"] = $curlError !== "" ? $curlError : "The download test failed with HTTP status $httpCode.";
        } else {
            $toreturn["available"] = true;
            $toreturn["server"] = "speed.cloudflare.com";
            $toreturn["ping_ms"] = round($connectTime * 1000, 1);
            $toreturn["download_mbps"] = round(($downloadSize * 8) / $downloadElapsed / 1000000, 2);

            // A failed upload leg still leaves download and ping worth
            // reporting, so its own failure does not blank out the rest.
            $uploadBytes = 5000000;
            $uploadData = random_bytes($uploadBytes);
            $uploadStart = microtime(true);
            $ch2 = curl_init("https://speed.cloudflare.com/__up");
            curl_setopt($ch2, CURLOPT_POST, true);
            curl_setopt($ch2, CURLOPT_POSTFIELDS, $uploadData);
            curl_setopt($ch2, CURLOPT_RETURNTRANSFER, true);
            curl_setopt($ch2, CURLOPT_TIMEOUT, 30);
            curl_setopt($ch2, CURLOPT_CONNECTTIMEOUT, 10);
            curl_setopt($ch2, CURLOPT_SSL_VERIFYPEER, true);
            $ok2 = curl_exec($ch2);
            $uploadHttpCode = curl_getinfo($ch2, CURLINFO_HTTP_CODE);
            curl_close($ch2);
            $uploadElapsed = microtime(true) - $uploadStart;

            if ($ok2 !== false && $uploadHttpCode === 200 && $uploadElapsed > 0) {
                $toreturn["upload_mbps"] = round(($uploadBytes * 8) / $uploadElapsed / 1000000, 2);
            }
        }
    }
    """)

    /// The configuration file exactly as pfSense has it on disk right now —
    /// a plain read, base64-encoded for safe transport, never a write. No
    /// entry in `writeOperations` needed: `file_get_contents()` here is the
    /// read this app's own write-boundary rules already permit without
    /// restriction (only write-mode `fopen` and `file_put_contents` are
    /// forbidden), and nothing below ever assigns back to `$config` or
    /// calls `write_config()`.
    static let backupConfig = PHPSnippet("backup_config", """
    ini_set('display_errors', 0);
    require_once '/etc/inc/globals.inc';
    global $g;
    $toreturn = [];
    $cfgdir = $g['conf_path'] ?? '/cf/conf';
    $cfgfile = $cfgdir . '/config.xml';
    if (!file_exists($cfgfile) || !is_readable($cfgfile)) {
        $toreturn["available"] = false;
        $toreturn["reason"] = "The configuration file could not be read.";
    } else {
        $xml = file_get_contents($cfgfile);
        $toreturn["available"] = $xml !== false;
        $toreturn["xml_base64"] = $xml !== false ? base64_encode($xml) : null;
        $toreturn["size_bytes"] = $xml !== false ? strlen($xml) : 0;
        $toreturn["hostname"] = php_uname('n');
    }
    """)

    /// Every snippet, for the publish check to audit and for tests to cover.
    static var all: [PHPSnippet] {
        [telemetry, firmware, packages, packageUpdates, updateProcessStatus,
         notices, interfaces, interfaceCounters, gateways, arpTable, dhcpLeases,
         staticMappings, hostOverrides, services, openvpnServers, openvpnClients, ipsecSAs,
         wireguard, pfTables, haproxy, acme, pfBlocker, dnsblStats, firewallRules, firewallAliases, portForwards,
         ruleSeparators, carp,
         certificates, dyndns, ping, rrdProbe, rrdTrace,
         batchCore, batchClients, batchVpn, batchSystem,
         reloadFirewall, speedtest, backupConfig]
        + LogSource.allCases.map { log($0, limit: 100) }
        + RRDWindow.allCases.map { rrdTraffic($0) }
        + HostFilter.allCases.map { hostTraffic(slot: 0, filter: $0, sort: .inbound) }
    }
}
// swiftlint:enable file_length type_body_length
