<?php

declare(strict_types=1);

if (isset($_SERVER['SCRIPT_FILENAME']) && realpath((string) $_SERVER['SCRIPT_FILENAME']) === __FILE__) {
    http_response_code(404);
    exit;
}

final class XmlApiSimulator
{
    /** @var list<string> */
    public const SCENARIOS = ['review', 'updates', 'degraded', 'fault'];

    /**
     * Match a Vaktpost PHP snippet by reviewed signature and return synthetic data.
     * The supplied PHP is treated only as text and is never evaluated.
     *
     * @param array{firmware?: bool, package?: bool} $completedUpdates
     * @return array{payload?: mixed, fault?: array{code: int, message: string}, completed_update?: 'firmware'|'package'}
     */
    public function respond(string $script, string $scenario, array $completedUpdates = []): array
    {
        if (!in_array($scenario, self::SCENARIOS, true)) {
            return ['fault' => ['code' => -32602, 'message' => 'Unknown simulator scenario']];
        }

        $isPing = str_contains($script, 'trim(file_get_contents("/etc/version"))');
        if ($scenario === 'fault' && !$isPing) {
            return ['fault' => ['code' => 0, 'message' => 'Synthetic failure requested by the fault scenario']];
        }

        $updatesAvailable = $scenario === 'updates';
        $degraded = $scenario === 'degraded';

        if (str_contains($script, '$vaktpost_batch["telemetry"]')) {
            return ['payload' => $this->coreBatch($updatesAvailable, $degraded, $completedUpdates)];
        }
        if (str_contains($script, '$vaktpost_batch["arp_table"]')) {
            return ['payload' => $this->clientsBatch()];
        }
        if (str_contains($script, '$vaktpost_batch["openvpn_servers"]')) {
            return ['payload' => $this->vpnBatch($degraded)];
        }
        if (str_contains($script, '$vaktpost_batch["notices"]')) {
            return ['payload' => $this->systemBatch($updatesAvailable, $completedUpdates)];
        }

        // Detail screens must be matched before the generic installed-package
        // signature below. pfBlockerNG, HAProxy and ACME all read
        // $config["installedpackages"], but each expects its own response
        // shape rather than the ordinary package list.
        if (str_contains($script, 'pfblockerngdnsblsettings')) {
            return ['payload' => $this->pfBlocker()];
        }
        if (str_contains($script, '$byDomain') && str_contains($script, 'dnsbl.log')) {
            return ['payload' => $this->dnsblStats()];
        }
        if (str_contains($script, 'ha_backends') && str_contains($script, 'ha_pools')) {
            return ['payload' => $this->haproxy()];
        }
        if (str_contains($script, 'accountkeys') && str_contains($script, 'a_domainlist')) {
            return ['payload' => $this->acme()];
        }
        if (str_contains($script, 'pfSense_get_pf_table') && str_contains($script, 'pfr_get_table_addrs')) {
            return ['payload' => $this->pfTables()];
        }
        if (str_contains($script, '$available = function_exists("rrd_fetch")')
            && str_contains($script, '*-traffic.rrd')) {
            return ['payload' => $this->rrdTraffic($script)];
        }

        $log = $this->logRequest($script);
        if ($log !== null) {
            return ['payload' => $log];
        }

        if (str_contains($script, 'printBandwidth(')) {
            return ['payload' => $this->hostTraffic($script)];
        }

        // ── Writes ──
        //
        // Every write snippet carries $vaktpost_payload (base64 JSON) and
        // ends with a write_config() call bearing its own descriptive
        // message — checked here, before the read-only $config["filter"|
        // "nat"|"aliases"] matches below, since every write also touches
        // those same paths. Session-backed, so a create/edit/delete/reorder
        // persists for the rest of this session and shows up on the next
        // read the way it would on a real firewall.
        if (str_contains($script, '"Vaktpost: saved a rule"')) {
            return ['payload' => $this->writeSaveRule($script)];
        }
        if (str_contains($script, '"Vaktpost: deleted a rule")')) {
            return ['payload' => $this->writeDeleteRule($script)];
        }
        if (str_contains($script, '"Vaktpost: saved a nat rule"')) {
            return ['payload' => $this->writeSaveNatRule($script)];
        }
        if (str_contains($script, '"Vaktpost: deleted a nat rule"')) {
            return ['payload' => $this->writeDeleteNatRule($script)];
        }
        if (str_contains($script, 'added a rule separator on ') || str_contains($script, 'edited a rule separator on ')) {
            return ['payload' => $this->writeSaveFilterSeparator($script)];
        }
        if (str_contains($script, 'deleted a rule separator on ')) {
            return ['payload' => $this->writeDeleteFilterSeparator($script)];
        }
        if (str_contains($script, 'added a NAT separator') || str_contains($script, 'edited a NAT separator')) {
            return ['payload' => $this->writeSaveNatSeparator($script)];
        }
        if (str_contains($script, 'Vaktpost: deleted a NAT separator')) {
            return ['payload' => $this->writeDeleteNatSeparator($script)];
        }
        if (str_contains($script, 'added firewall alias ') || str_contains($script, 'edited firewall alias ')) {
            return ['payload' => $this->writeSaveAlias($script)];
        }
        if (str_contains($script, 'Vaktpost: deleted firewall alias ')) {
            return ['payload' => $this->writeDeleteAlias($script)];
        }
        if (str_contains($script, 'Vaktpost: reordered rules on ')) {
            return ['payload' => $this->writeReorderFilterRules($script)];
        }
        if (str_contains($script, 'Vaktpost: reordered NAT port forwards')) {
            return ['payload' => $this->writeReorderNatRules($script)];
        }

        if (str_contains($script, '$vaktpost_kind') && str_contains($script, 'mwexec_bg')) {
            if (!$updatesAvailable) {
                return ['payload' => ['status' => 'no_update', 'started' => false, 'error' => 'The requested update is no longer available']];
            }
            $kind = $this->decodeUpdateKind($script);
            return [
                'payload' => [
                    'status' => 'ok',
                    'started' => true,
                    'phase' => 'completed',
                    'mode' => $kind,
                    'package' => $kind === 'package' ? 'pfSense-pkg-pfBlockerNG-devel' : '',
                    'target' => $kind === 'package' ? '3.2.0_9' : '2.7.3',
                ],
                'completed_update' => $kind,
            ];
        }

        if (str_contains($script, '"running" => isvalidpid')) {
            return ['payload' => ['running' => false]];
        }
        if (str_contains($script, 'get_pkg_info("all", false, true)')) {
            return ['payload' => ['available' => true, 'data' => $this->packages($updatesAvailable, (bool) ($completedUpdates['package'] ?? false))]];
        }
        if (str_contains($script, 'get_system_pkg_version')) {
            return ['payload' => $this->firmware($updatesAvailable, (bool) ($completedUpdates['firmware'] ?? false))];
        }
        if (str_contains($script, '"cpu_ticks_total"')) {
            return ['payload' => $this->telemetry()];
        }
        if (str_contains($script, 'get_configured_interface_with_descr')) {
            return ['payload' => ['data' => $this->interfaces($degraded)]];
        }
        if (str_contains($script, 'return_gateways_status')) {
            return ['payload' => $this->gateways($degraded)];
        }
        if (str_contains($script, 'get_services')) {
            return ['payload' => ['data' => $this->services($degraded)]];
        }
        if (str_contains($script, 'is_subsystem_dirty') && str_contains($script, 'separator')) {
            $state = $this->state();
            return ['payload' => [
                'filter' => $state['filter_separators'],
                'nat' => $state['nat_separators'],
                'apply_pending' => !empty($_SESSION['vaktpost_dirty']),
            ]];
        }
        if (str_contains($script, '$config["filter"]')) {
            return ['payload' => ['data' => $this->state()['rules']]];
        }
        if (str_contains($script, '$config["aliases"]')) {
            return ['payload' => ['data' => $this->state()['aliases']]];
        }
        if (str_contains($script, '$config["nat"]') && !str_contains($script, 'separator')) {
            return ['payload' => ['data' => $this->state()['nat_rules']]];
        }
        if (str_contains($script, 'get_notices')) {
            return ['payload' => $this->notices()];
        }
        if (str_contains($script, 'get_carp_status')) {
            return ['payload' => ['enable' => false, 'interfaces' => []]];
        }
        if (str_contains($script, 'openssl_x509_parse')) {
            return ['payload' => $this->certificates()];
        }
        if (str_contains($script, 'dyndns_*.cache')) {
            return ['payload' => $this->dynamicDns()];
        }
        if (str_contains($script, 'get_openvpn_server_status')) {
            return ['payload' => $this->vpnBatch($degraded)['sections']['openvpn_servers']];
        }
        if (str_contains($script, 'get_openvpn_client_status')) {
            return ['payload' => $this->vpnBatch($degraded)['sections']['openvpn_clients']];
        }
        if (str_contains($script, 'ipsec_list_sa')) {
            return ['payload' => $this->vpnBatch($degraded)['sections']['ipsec_sas']];
        }
        if (str_contains($script, 'wg_get_status')) {
            return ['payload' => $this->vpnBatch($degraded)['sections']['wireguard']];
        }
        if (str_contains($script, 'filter_configure_sync')) {
            // The real snippet's success path also clears pfSense's own
            // "aliases" dirty flag once the reload completes — this is the
            // one place the pending state this lab tracks actually clears,
            // matching that: an Apply here is what stops every other read
            // from reporting apply_pending until the next write sets it again.
            unset($_SESSION['vaktpost_dirty']);
            return ['payload' => ['status' => 'ok']];
        }
        if (str_contains($script, 'restart_service')) {
            return ['payload' => ['status' => 'ok']];
        }
        if (str_contains($script, 'pfctl_clear_states')) {
            return ['payload' => ['status' => 'ok', 'scope' => 'all']];
        }
        if ($isPing) {
            return ['payload' => ['version' => '2.7.3-RELEASE']];
        }
        if (str_contains($script, '$config["installedpackages"]')) {
            return ['payload' => ['data' => $this->packages($updatesAvailable, (bool) ($completedUpdates['package'] ?? false))]];
        }

        if (str_contains($script, 'system_get_arp_table')) {
            return ['payload' => $this->clientsBatch()['sections']['arp_table']];
        }
        if (str_contains($script, 'system_get_dhcpleases')) {
            return ['payload' => $this->clientsBatch()['sections']['dhcp_leases']];
        }
        if (str_contains($script, '$config["dhcpd"]') && str_contains($script, 'staticmap')) {
            return ['payload' => $this->clientsBatch()['sections']['static_mappings']];
        }
        if (str_contains($script, 'config_get_path("unbound/hosts"')) {
            return ['payload' => $this->clientsBatch()['sections']['host_overrides']];
        }

        return ['fault' => ['code' => -32602, 'message' => 'The lab refused an unknown snippet; submitted PHP is never executed']];
    }

    // ── Session-backed writable state ──
    //
    // Rules, port forwards, aliases and separators start as mutable copies
    // of the same fixtures every read-only request already returns, and
    // every write below mutates this copy — never the static baseline — so
    // create/edit/delete/reorder persists for the rest of this session and
    // the next read reflects it, the way a real firewall would.

    /** @return array{rules: list<array<string, mixed>>, nat_rules: list<array<string, mixed>>, aliases: list<array<string, mixed>>, filter_separators: list<array<string, mixed>>, nat_separators: list<array<string, mixed>>} */
    /**
     * A session's state is discarded and reseeded after this many seconds,
     * regardless of PHP's own session garbage collection. GC is
     * probabilistic and tuned for freeing memory on a busy host — on a
     * lab endpoint that might see one visitor an hour, it can leave a
     * ruleset someone emptied out sitting there for whoever tries the app
     * next. This bounds that independently of how any given host has GC
     * configured.
     */
    private const STATE_MAX_AGE_SECONDS = 1200;

    /** @return array{seeded_at: int, rules: list<array<string, mixed>>, nat_rules: list<array<string, mixed>>, aliases: list<array<string, mixed>>, filter_separators: list<array<string, mixed>>, nat_separators: list<array<string, mixed>>} */
    private function state(): array
    {
        $existing = $_SESSION['vaktpost_state'] ?? null;
        $stale = is_array($existing)
            && is_int($existing['seeded_at'] ?? null)
            && (time() - $existing['seeded_at']) > self::STATE_MAX_AGE_SECONDS;

        if (!is_array($existing) || $stale) {
            $_SESSION['vaktpost_state'] = [
                'seeded_at' => time(),
                'rules' => $this->firewallRules(),
                'nat_rules' => $this->portForwards(),
                'aliases' => $this->aliases(),
                'filter_separators' => [
                    ['interface' => 'lan', 'key' => 'sep0', 'text' => 'Application access', 'color' => 'info', 'position' => '0'],
                ],
                'nat_separators' => [],
            ];
            // A reseed clears whatever was pending too — there is nothing
            // meaningful left to apply once the ruleset behind it is gone.
            unset($_SESSION['vaktpost_dirty']);
        }
        return $_SESSION['vaktpost_state'];
    }

    private function saveState(array $state): void
    {
        $_SESSION['vaktpost_state'] = $state;
        $_SESSION['vaktpost_dirty'] = true;
    }

    /**
     * Decodes the base64 JSON payload every write snippet carries as
     * $vaktpost_payload, the same way the real snippet's own decodePayload
     * line does.
     *
     * @return array<string, mixed>
     */
    private function extractPayload(string $script): array
    {
        if (preg_match('/\$vaktpost_payload\s*=\s*"([A-Za-z0-9+\/=]*)"/', $script, $matches) !== 1) {
            return [];
        }
        $decoded = base64_decode($matches[1], true);
        if ($decoded === false) {
            return [];
        }
        $data = json_decode($decoded, true);
        return is_array($data) ? $data : [];
    }

    /** @param list<array<string, mixed>> $list */
    private function findIndex(array $list, string $field, string $value): ?int
    {
        if ($value === '') {
            return null;
        }
        foreach ($list as $i => $item) {
            if (($item[$field] ?? '') === $value) {
                return $i;
            }
        }
        return null;
    }

    /** @param list<array<string, mixed>> $existing */
    private function newTracker(array $existing): string
    {
        $tracker = (string) time();
        $trackers = array_column($existing, 'tracker');
        while (in_array($tracker, $trackers, true)) {
            $tracker = (string) ((int) $tracker + 1);
        }
        return $tracker;
    }

    /** @param list<array<string, mixed>> $existing */
    private function newSeparatorKey(array $existing): string
    {
        $n = 0;
        $keys = array_column($existing, 'key');
        while (in_array('sep' . $n, $keys, true)) {
            $n++;
        }
        return 'sep' . $n;
    }

    /**
     * Inserts a rule or port forward at the placement pfSense's own save
     * flow supports: first, last, or immediately before a named anchor. An
     * anchor that no longer exists falls back to last, same as a plain
     * append would.
     *
     * @param list<array<string, mixed>> $list
     * @param array<string, mixed> $item
     * @return list<array<string, mixed>>
     */
    private function placeInList(array $list, array $item, string $placement, string $beforeId, string $idField = 'tracker'): array
    {
        if ($placement === 'first') {
            array_unshift($list, $item);
            return $list;
        }
        if ($placement === 'before' && $beforeId !== '') {
            foreach ($list as $i => $existing) {
                if (($existing[$idField] ?? '') === $beforeId) {
                    array_splice($list, $i, 0, [$item]);
                    return $list;
                }
            }
        }
        $list[] = $item;
        return $list;
    }

    /** @return array<string, mixed> */
    private function writeSaveRule(string $script): array
    {
        $input = $this->extractPayload($script);
        $state = $this->state();
        $isCreate = ($input['create'] ?? false) === true;
        $tracker = (string) ($input['tracker'] ?? '');
        $placement = (string) ($input['placement'] ?? ($isCreate ? 'last' : 'keep'));
        $before = (string) ($input['before_tracker'] ?? '');
        $fields = $input;
        unset($fields['create'], $fields['placement'], $fields['before_tracker']);

        if ($isCreate) {
            $tracker = $this->newTracker($state['rules']);
            $fields['tracker'] = $tracker;
            $state['rules'] = $this->placeInList($state['rules'], $fields, $placement, $before);
        } else {
            $index = $this->findIndex($state['rules'], 'tracker', $tracker);
            if ($index === null) {
                return ['status' => 'not_found', 'error' => 'The rule no longer exists.'];
            }
            $fields['tracker'] = $tracker;
            $state['rules'][$index] = array_merge($state['rules'][$index], $fields);
            if ($placement !== 'keep') {
                $rule = $state['rules'][$index];
                array_splice($state['rules'], $index, 1);
                $state['rules'] = $this->placeInList($state['rules'], $rule, $placement, $before);
            }
        }
        $this->saveState($state);

        $result = ['status' => 'ok', 'apply_pending' => true, 'created' => $isCreate, 'tracker' => $tracker, 'placement' => $placement];
        if ($placement === 'before') {
            $result['before_tracker'] = $before;
        }
        return $result;
    }

    /** @return array<string, mixed> */
    private function writeDeleteRule(string $script): array
    {
        $input = $this->extractPayload($script);
        $state = $this->state();
        $tracker = (string) ($input['tracker'] ?? '');
        $index = $this->findIndex($state['rules'], 'tracker', $tracker);
        if ($index === null) {
            return ['status' => 'not_found'];
        }
        array_splice($state['rules'], $index, 1);
        $this->saveState($state);
        return ['status' => 'ok', 'apply_pending' => true];
    }

    /** @return array<string, mixed> */
    private function writeSaveNatRule(string $script): array
    {
        $input = $this->extractPayload($script);
        $state = $this->state();
        $isCreate = ($input['create'] ?? false) === true;
        $tracker = (string) ($input['tracker'] ?? '');
        $fields = $input;
        unset($fields['create']);

        if ($isCreate) {
            $tracker = $this->newTracker($state['nat_rules']);
            $fields['tracker'] = $tracker;
            $state['nat_rules'][] = $fields;
        } else {
            $index = $tracker !== '' ? $this->findIndex($state['nat_rules'], 'tracker', $tracker) : null;
            if ($index === null) {
                // Legacy-identity fallback for a forward saved before this
                // app started assigning NAT trackers: match by the original
                // interface and target instead.
                $origInterface = (string) ($input['original_interface'] ?? '');
                $origTarget = (string) ($input['original_target'] ?? '');
                foreach ($state['nat_rules'] as $i => $r) {
                    if (($r['tracker'] ?? '') === ''
                        && ($r['interface'] ?? '') === $origInterface
                        && ($r['target'] ?? '') === $origTarget) {
                        $index = $i;
                        break;
                    }
                }
            }
            if ($index === null) {
                return ['status' => 'not_found', 'error' => 'The port forward no longer exists.'];
            }
            $tracker = $tracker !== '' ? $tracker : $this->newTracker($state['nat_rules']);
            $fields['tracker'] = $tracker;
            $state['nat_rules'][$index] = array_merge($state['nat_rules'][$index], $fields);
        }
        $this->saveState($state);
        return ['status' => 'ok', 'apply_pending' => true, 'created' => $isCreate, 'tracker' => $tracker];
    }

    /** @return array<string, mixed> */
    private function writeDeleteNatRule(string $script): array
    {
        $input = $this->extractPayload($script);
        $state = $this->state();
        $tracker = (string) ($input['tracker'] ?? '');
        $index = $this->findIndex($state['nat_rules'], 'tracker', $tracker);
        if ($index === null) {
            return ['status' => 'not_found'];
        }
        array_splice($state['nat_rules'], $index, 1);
        $this->saveState($state);
        return ['status' => 'ok', 'apply_pending' => true];
    }

    /** @return array<string, mixed> */
    private function writeSaveFilterSeparator(string $script): array
    {
        $input = $this->extractPayload($script);
        $state = $this->state();
        $isCreate = ($input['create'] ?? false) === true;
        $key = (string) ($input['key'] ?? '');
        $interface = (string) ($input['interface'] ?? '');
        $text = (string) ($input['text'] ?? '');
        $color = (string) ($input['color'] ?? 'info');
        $position = (string) ($input['position'] ?? '0');

        if ($isCreate) {
            $key = $this->newSeparatorKey($state['filter_separators']);
            $state['filter_separators'][] = [
                'interface' => $interface, 'key' => $key, 'text' => $text, 'color' => $color, 'position' => $position,
            ];
        } else {
            $index = $this->findIndex($state['filter_separators'], 'key', $key);
            if ($index === null) {
                return ['status' => 'not_found', 'error' => 'The separator is no longer present'];
            }
            $state['filter_separators'][$index] = [
                'interface' => $interface, 'key' => $key, 'text' => $text, 'color' => $color, 'position' => $position,
            ];
        }
        $this->saveState($state);
        return [
            'status' => 'ok', 'apply_pending' => true, 'key' => $key, 'interface' => $interface,
            'text' => $text, 'color' => $color, 'position' => $position, 'created' => $isCreate,
        ];
    }

    /** @return array<string, mixed> */
    private function writeDeleteFilterSeparator(string $script): array
    {
        $input = $this->extractPayload($script);
        $state = $this->state();
        $key = (string) ($input['key'] ?? '');
        $interface = (string) ($input['interface'] ?? '');
        $index = $this->findIndex($state['filter_separators'], 'key', $key);
        if ($index === null) {
            return ['status' => 'not_found', 'error' => 'The separator is no longer present'];
        }
        array_splice($state['filter_separators'], $index, 1);
        $this->saveState($state);
        return ['status' => 'ok', 'apply_pending' => true, 'key' => $key, 'interface' => $interface];
    }

    /** @return array<string, mixed> */
    private function writeSaveNatSeparator(string $script): array
    {
        $input = $this->extractPayload($script);
        $state = $this->state();
        $isCreate = ($input['create'] ?? false) === true;
        $key = (string) ($input['key'] ?? '');
        $text = (string) ($input['text'] ?? '');
        $color = (string) ($input['color'] ?? 'info');
        $position = (string) ($input['position'] ?? '0');

        if ($isCreate) {
            $key = $this->newSeparatorKey($state['nat_separators']);
            $state['nat_separators'][] = ['key' => $key, 'text' => $text, 'color' => $color, 'position' => $position];
        } else {
            $index = $this->findIndex($state['nat_separators'], 'key', $key);
            if ($index === null) {
                return ['status' => 'not_found', 'error' => 'The NAT separator is no longer present'];
            }
            $state['nat_separators'][$index] = ['key' => $key, 'text' => $text, 'color' => $color, 'position' => $position];
        }
        $this->saveState($state);
        return ['status' => 'ok', 'apply_pending' => true, 'key' => $key, 'text' => $text, 'color' => $color, 'position' => $position, 'created' => $isCreate];
    }

    /** @return array<string, mixed> */
    private function writeDeleteNatSeparator(string $script): array
    {
        $input = $this->extractPayload($script);
        $state = $this->state();
        $key = (string) ($input['key'] ?? '');
        $index = $this->findIndex($state['nat_separators'], 'key', $key);
        if ($index === null) {
            return ['status' => 'not_found', 'error' => 'The NAT separator is no longer present'];
        }
        array_splice($state['nat_separators'], $index, 1);
        $this->saveState($state);
        return ['status' => 'ok', 'apply_pending' => true, 'key' => $key];
    }

    /** @return array<string, mixed> */
    private function writeSaveAlias(string $script): array
    {
        $input = $this->extractPayload($script);
        $state = $this->state();
        $isCreate = ($input['create'] ?? false) === true;
        $name = (string) ($input['name'] ?? '');
        $fields = $input;
        unset($fields['create'], $fields['original_name']);

        if ($isCreate) {
            $state['aliases'][] = $fields;
        } else {
            $index = $this->findIndex($state['aliases'], 'name', $name);
            if ($index === null) {
                return ['status' => 'not_found', 'error' => 'The alias is no longer present'];
            }
            $state['aliases'][$index] = array_merge($state['aliases'][$index], $fields);
        }
        $this->saveState($state);
        return ['status' => 'ok', 'apply_pending' => true, 'created' => $isCreate, 'name' => $name];
    }

    /** @return array<string, mixed> */
    private function writeDeleteAlias(string $script): array
    {
        $input = $this->extractPayload($script);
        $state = $this->state();
        $name = (string) ($input['name'] ?? '');
        $index = $this->findIndex($state['aliases'], 'name', $name);
        if ($index === null) {
            return ['status' => 'not_found', 'error' => 'The alias is no longer present'];
        }
        array_splice($state['aliases'], $index, 1);
        $this->saveState($state);
        return ['status' => 'ok', 'apply_pending' => true, 'name' => $name];
    }

    /** @return array<string, mixed> */
    private function writeReorderFilterRules(string $script): array
    {
        $input = $this->extractPayload($script);
        $state = $this->state();
        $interface = (string) ($input['interface'] ?? '');
        $items = is_array($input['items'] ?? null) ? $input['items'] : [];
        if ($interface === '' || empty($items)) {
            return ['status' => 'invalid', 'error' => 'A non-empty order is required.'];
        }

        $onInterface = [];
        $elsewhere = [];
        foreach ($state['rules'] as $rule) {
            if (($rule['interface'] ?? '') === $interface) {
                $onInterface[] = $rule;
            } else {
                $elsewhere[] = $rule;
            }
        }
        $sepsOnInterface = [];
        $sepsElsewhere = [];
        foreach ($state['filter_separators'] as $sep) {
            if (($sep['interface'] ?? '') === $interface) {
                $sepsOnInterface[] = $sep;
            } else {
                $sepsElsewhere[] = $sep;
            }
        }

        $reorderedRules = [];
        $reorderedSeps = [];
        $precedingRules = 0;
        foreach ($items as $item) {
            $kind = (string) ($item['kind'] ?? '');
            $id = (string) ($item['id'] ?? '');
            if ($kind === 'rule') {
                foreach ($onInterface as $rule) {
                    if (($rule['tracker'] ?? '') === $id) {
                        $reorderedRules[] = $rule;
                        $precedingRules++;
                        break;
                    }
                }
            } elseif ($kind === 'separator') {
                foreach ($sepsOnInterface as $sep) {
                    if (($sep['key'] ?? '') === $id) {
                        $sep['position'] = (string) $precedingRules;
                        $reorderedSeps[] = $sep;
                        break;
                    }
                }
            }
        }
        if (count($reorderedRules) !== count($onInterface)) {
            return ['status' => 'mismatch', 'error' => 'The rules on this interface changed since this order was prepared.'];
        }

        $state['rules'] = array_merge($elsewhere, $reorderedRules);
        $state['filter_separators'] = array_merge($sepsElsewhere, $reorderedSeps);
        $this->saveState($state);
        return ['status' => 'ok', 'apply_pending' => true];
    }

    /** @return array<string, mixed> */
    private function writeReorderNatRules(string $script): array
    {
        $input = $this->extractPayload($script);
        $state = $this->state();
        $items = is_array($input['items'] ?? null) ? $input['items'] : [];
        if (empty($items)) {
            return ['status' => 'invalid', 'error' => 'A non-empty NAT order is required.'];
        }
        if (count($items) !== count($state['nat_rules']) + count($state['nat_separators'])) {
            return ['status' => 'mismatch', 'error' => 'The NAT rules or separators changed since this order was prepared.'];
        }

        $reorderedRules = [];
        $reorderedSeps = [];
        $precedingRules = 0;
        foreach ($items as $item) {
            $kind = (string) ($item['kind'] ?? '');
            if ($kind === 'rule') {
                $tracker = (string) ($item['tracker'] ?? '');
                foreach ($state['nat_rules'] as $rule) {
                    if (($rule['tracker'] ?? '') === $tracker) {
                        $reorderedRules[] = $rule;
                        $precedingRules++;
                        break;
                    }
                }
            } elseif ($kind === 'separator') {
                $id = (string) ($item['id'] ?? '');
                foreach ($state['nat_separators'] as $sep) {
                    if (($sep['key'] ?? '') === $id) {
                        $sep['position'] = (string) $precedingRules;
                        $reorderedSeps[] = $sep;
                        break;
                    }
                }
            }
        }
        if (count($reorderedRules) !== count($state['nat_rules'])) {
            return ['status' => 'mismatch', 'error' => 'The NAT rules or separators changed since this order was prepared.'];
        }
        $state['nat_rules'] = $reorderedRules;
        $state['nat_separators'] = $reorderedSeps;
        $this->saveState($state);
        return ['status' => 'ok', 'apply_pending' => true];
    }

    /** @return array<string, mixed> */
    private function coreBatch(bool $updates, bool $degraded, array $completed): array
    {
        return ['sections' => [
            'telemetry' => $this->telemetry(),
            'firmware' => $this->firmware($updates, (bool) ($completed['firmware'] ?? false)),
            'interfaces' => ['data' => $this->interfaces($degraded)],
            'gateways' => $this->gateways($degraded),
            'services' => ['data' => $this->services($degraded)],
        ]];
    }

    /** @return array<string, mixed> */
    private function clientsBatch(): array
    {
        return ['sections' => [
            'arp_table' => ['data' => [
                ['ip' => '192.0.2.20', 'mac' => '02:00:00:10:00:20', 'hostname' => 'web-01', 'interface' => 'vtnet1'],
                ['ip' => '192.0.2.53', 'mac' => '02:00:00:10:00:53', 'hostname' => 'dns-01', 'interface' => 'vtnet1'],
            ]],
            'dhcp_leases' => ['data' => [
                ['ip' => '192.0.2.110', 'mac' => '02:00:00:10:01:10', 'hostname' => 'test-iphone', 'starts' => '2026/09/15 09:00:00', 'ends' => '2026/09/15 21:00:00', 'state' => 'active', 'if' => 'lan'],
                ['ip' => '192.0.2.111', 'mac' => '02:00:00:10:01:11', 'hostname' => 'test-mac', 'starts' => '2026/09/15 08:30:00', 'ends' => '2026/09/15 20:30:00', 'state' => 'active', 'if' => 'lan'],
            ]],
            'static_mappings' => ['data' => [['ipaddr' => '192.0.2.53', 'mac' => '02:00:00:10:00:53', 'hostname' => 'dns-01', 'descr' => 'Synthetic resolver', 'interface' => 'lan']]],
            'host_overrides' => ['data' => [['host' => 'router', 'domain' => 'example.invalid', 'ip' => '192.0.2.1', 'descr' => 'Synthetic gateway']]],
            'firewall_aliases' => ['data' => $this->aliases()],
        ]];
    }

    /** @return array<string, mixed> */
    private function vpnBatch(bool $degraded): array
    {
        return ['sections' => [
            'openvpn_servers' => ['data' => [[
                'name' => 'Remote access UDP4:1194', 'vpnid' => '1', 'mode' => 'server_user', 'port' => '1194',
                'conns' => $degraded ? [] : [['common_name' => 'friend-test', 'remote_host' => '203.0.113.42:51820', 'virtual_addr' => '192.0.2.210', 'bytes_recv' => 2410992, 'bytes_sent' => 8778104, 'connect_time' => '2026-09-15 10:32:14']],
                'routes' => [],
            ]]],
            'openvpn_clients' => ['data' => [['name' => 'Lab uplink', 'vpnid' => '2', 'status' => $degraded ? 'down' : 'up', 'remote_host' => '198.51.100.90', 'virtual_addr' => '192.0.2.130']]],
            'ipsec_sas' => ['data' => [['con_id' => 'branch-office', 'uniqueid' => '42', 'state' => $degraded ? 'connecting' : 'established', 'local_host' => '198.51.100.24', 'remote_host' => '203.0.113.80', 'version' => 'IKEv2', 'child_sas' => $degraded ? [] : [[]]]]],
            'wireguard' => [
                'tunnels' => [['name' => 'tun_wg0', 'descr' => 'Mobile peers', 'enabled' => true, 'peer_count' => 1, 'status' => $degraded ? 'down' : 'up', 'listen_port' => '51820']],
                'peers' => [['tun' => 'tun_wg0', 'public_key' => 'SYNTHETIC-PUBLIC-KEY', 'descr' => 'Test phone', 'endpoint' => '203.0.113.44:51820', 'latest_handshake' => $degraded ? '0' : (string) (time() - 70), 'transfer_rx' => 1024112, 'transfer_tx' => 3880442, 'allowed_ips' => ['192.0.2.212/32'], 'enabled' => true]],
            ],
        ]];
    }

    /** @return array<string, mixed> */
    private function systemBatch(bool $updates, array $completed): array
    {
        return ['sections' => [
            'notices' => $this->notices(),
            'certificates' => $this->certificates(),
            'dyndns' => $this->dynamicDns(),
            'packages' => ['data' => $this->packages($updates, (bool) ($completed['package'] ?? false))],
            'carp' => ['enable' => false, 'interfaces' => []],
        ]];
    }

    /** @return array<string, mixed> */
    private function telemetry(): array
    {
        // Ticks are cumulative counters, the same shape as interface byte
        // counters — driftingCounter() applies here for the same reason:
        // a static pair of tick values, like the fixed baseline this
        // replaced, produces a zero delta between any two polls. The app's
        // own CPU-usage derivation treats a zero interval as indistinguishable
        // from the same sample read twice and discards it rather than
        // reporting 0% — so a static total_ticks/idle_ticks pair does not
        // make the app show 0% usage, it makes the CPU meter never appear
        // at all, which is what was happening here.
        //
        // idle's own wobble is capped well below what would let it exceed
        // total in the same interval: total_ticks always advances at a
        // fixed 400/sec (no wobble — a clock does not speed up and slow
        // down), and idle wobbles between 256 and 384 of those 400,
        // implying roughly 4%–36% instantaneous CPU usage. Total ticks
        // being a hard ceiling idle can never cross is what the app's own
        // "idle_delta <= total_delta" sanity check depends on; a wobble
        // large enough to cross it even briefly would make that one poll
        // look like a counter reset and discard it.
        $elapsed = microtime(true) - strtotime('2026-09-01 00:00:00 UTC');
        $cpuTicksTotal = (int) $this->driftingCounter(8_400_000, 400, $elapsed, 45, 0, 0.0);
        $cpuTicksIdle = (int) $this->driftingCounter(7_240_000, 320, $elapsed, 45, 0, 0.2);

        return [
            'hostname' => 'vaktpost-lab', 'domain' => 'example.invalid', 'platform' => 'Virtual pfSense test appliance', 'serial' => 'SYNTHETIC-ONLY',
            'cpu_count' => 4, 'cpu_ticks_total' => $cpuTicksTotal, 'cpu_ticks_idle' => $cpuTicksIdle, 'mem_usage' => 31, 'swap_usage' => 0, 'uptime_sec' => 1248920,
            // A genuinely separate sensor from the per-core ones below —
            // an ACPI thermal zone, not a duplicate of dev.cpu.0.temperature
            // under a second name. The app shows both rows together when
            // both are present, which only makes sense when they are
            // actually two different sensors; reusing one core's own OID
            // here made the two rows repeat the same reading under
            // different labels.
            'temp_c' => 46.5, 'temp_source' => 'hw.acpi.thermal.tz0.temperature',
            'core_temps' => [['core' => 0, 'temp' => 47, 'source' => 'dev.cpu.0.temperature'], ['core' => 1, 'temp' => 48, 'source' => 'dev.cpu.1.temperature'], ['core' => 2, 'temp' => 49, 'source' => 'dev.cpu.2.temperature'], ['core' => 3, 'temp' => 50, 'source' => 'dev.cpu.3.temperature']],
            'cpu_load_avg' => [0.22, 0.18, 0.16], 'mbuf_used' => 18204, 'mbuf_total' => 262144, 'mbuf_usage' => 6.9, 'currentstates' => 482, 'maximumstates' => 400000,
            'filesystems' => [['mount' => '/', 'size' => '7.8G', 'used' => '1.9G', 'available' => '5.3G', 'percent_used' => 26], ['mount' => '/var', 'size' => '3.8G', 'used' => '620M', 'available' => '2.9G', 'percent_used' => 17]],
        ];
    }

    /** @return array<string, mixed> */
    private function firmware(bool $available, bool $completed): array
    {
        $outdated = $available && !$completed;
        return ['version' => $outdated ? '2.7.2-RELEASE' : '2.7.3-RELEASE', 'installed_version' => $outdated ? '2.7.2' : '2.7.3', 'latest_version' => '2.7.3', 'update_available' => $outdated];
    }

    /** @return list<array<string, mixed>> */
    private function packages(bool $available, bool $completed): array
    {
        $outdated = $available && !$completed;
        return [
            ['name' => 'pfBlockerNG-devel', 'shortname' => 'pfBlockerNG-devel', 'update_name' => 'pfSense-pkg-pfBlockerNG-devel', 'descr' => 'IP and DNS block-list management', 'installed_version' => $outdated ? '3.2.0_8' : '3.2.0_9', 'latest_version' => '3.2.0_9', 'update_available' => $outdated],
            ['name' => 'openvpn-client-export', 'shortname' => 'openvpn-client-export', 'update_name' => 'pfSense-pkg-openvpn-client-export', 'descr' => 'OpenVPN client configuration exporter', 'installed_version' => '1.9.13', 'latest_version' => '1.9.13', 'update_available' => false],
            ['name' => 'acme', 'shortname' => 'acme', 'update_name' => 'pfSense-pkg-acme', 'descr' => 'ACME certificate automation', 'installed_version' => '0.8.1', 'latest_version' => '0.8.1', 'update_available' => false],
        ];
    }

    /** @return array{data: list<string>, path: string, size: int} */
    private function logRequest(string $script): ?array
    {
        if (preg_match('/\\$path\\s*=\\s*"\\/var\\/log\\/(filter|system|auth|dhcpd|openvpn)\\.log"/', $script, $matches) !== 1) {
            return null;
        }

        $source = $matches[1];
        $rows = $this->logs()[$source];
        return [
            'data' => $rows,
            'path' => '/var/log/' . $source . '.log',
            'size' => strlen(implode(PHP_EOL, $rows)),
        ];
    }

    /** @return array<string, list<string>> */
    private function logs(): array
    {
        return [
            'filter' => [
                'Sep 15 13:58:02 filterlog[4711]: 5,,,1700000001,vtnet1,match,pass,in,4,0x0,,64,0,0,DF,6,tcp,60,192.0.2.110,192.0.2.20,53318,443,0,S,',
                'Sep 15 14:01:44 filterlog[4711]: 5,,,1700000002,vtnet0,match,block,in,4,0x0,,51,44210,0,none,6,tcp,60,203.0.113.66,198.51.100.24,51422,22,0,S,',
                'Sep 15 14:03:09 filterlog[4711]: 5,,,1700000003,ovpns1,match,pass,in,4,0x0,,64,0,0,none,17,udp,74,192.0.2.210,192.0.2.53,59001,53,54',
            ],
            'system' => [
                'Sep 15 13:45:00 vaktpost-lab php-fpm[2114]: /rc.start_packages: Restarting/Starting all packages.',
                'Sep 15 14:00:01 vaktpost-lab check_reload_status[411]: Reloading filter',
                'Sep 15 14:03:12 vaktpost-lab syslogd: synthetic lab snapshot complete',
            ],
            'auth' => [
                'Sep 15 13:52:17 vaktpost-lab sshd[8201]: Accepted publickey for lab-admin from 192.0.2.111 port 52108 ssh2',
                'Sep 15 14:02:53 vaktpost-lab php-fpm[8344]: Successful login for user review from 192.0.2.110',
            ],
            'dhcpd' => [
                'Sep 15 13:50:06 vaktpost-lab dhcpd[991]: DHCPACK on 192.0.2.110 to 02:00:00:10:01:10 (test-iphone) via vtnet1',
                'Sep 15 14:00:42 vaktpost-lab dhcpd[991]: DHCPACK on 192.0.2.111 to 02:00:00:10:01:11 (test-mac) via vtnet1',
            ],
            'openvpn' => [
                'Sep 15 13:40:31 vaktpost-lab openvpn[2390]: peer info: IV_PLAT=iOS',
                'Sep 15 13:40:32 vaktpost-lab openvpn[2390]: friend-test/203.0.113.42:51820 MULTI_sva: pool returned IPv4=192.0.2.210',
            ],
        ];
    }

    /** @return array{available: bool, data: list<array<string, mixed>>} */
    private function pfTables(): array
    {
        return ['available' => true, 'data' => [
            ['name' => 'sshguard', 'entries' => ['203.0.113.66', '203.0.113.81']],
            ['name' => 'demo_web_servers', 'entries' => ['192.0.2.20', '192.0.2.21']],
        ]];
    }

    /** @return array<string, mixed> */
    private function pfBlocker(): array
    {
        return [
            'installed' => true,
            'enabled' => true,
            'dnsbl' => true,
            'dnsbl_mode' => 'dnsbl_python',
            'mode' => 'on',
            'accessor' => 'synthetic',
            'paths' => ['pkg' => true, 'logs' => true, 'db' => true, 'deny' => true, 'dnsbl' => true],
            'logs' => [
                ['name' => 'pfblockerng.log', 'bytes' => 18342, 'updated' => 1789462990],
                ['name' => 'dnsbl.log', 'bytes' => 9271, 'updated' => 1789462960],
            ],
            'feeds' => [
                ['name' => 'pfB_PRI1_v4', 'descr' => 'Synthetic reputation feed', 'type' => 'urltable', 'entries' => 1248, 'source' => 'file'],
                ['name' => 'pfB_DEMO_v4', 'descr' => 'Lab deny list', 'type' => 'host', 'entries' => 2, 'source' => 'config'],
            ],
        ];
    }

    /** @return array<string, mixed> */
    private function dnsblStats(): array
    {
        return [
            'available' => true, 'bytes' => 9271, 'scanned' => 9271,
            'truncated' => false, 'events' => 18, 'unparsed' => 0,
            'first' => 'Sep 15 09:11:03', 'last' => 'Sep 15 14:02:18',
            'domains' => [['name' => 'telemetry.example.invalid', 'count' => 8], ['name' => 'ads.example.invalid', 'count' => 6]],
            'clients' => [['name' => '192.0.2.110', 'count' => 10], ['name' => '192.0.2.111', 'count' => 8]],
            'groups' => [['name' => 'Demo_Blocklists', 'count' => 18]],
            'feeds' => [['name' => 'Synthetic_List', 'count' => 18]],
            'hours' => [['label' => 'Sep 15 13', 'count' => 7], ['label' => 'Sep 15 14', 'count' => 4]],
        ];
    }

    /** @return array<string, mixed> */
    private function haproxy(): array
    {
        return [
            'installed' => true,
            'frontends' => [[
                'name' => 'public_https', 'descr' => 'Synthetic HTTPS frontend', 'status' => 'active',
                'type' => 'http', 'binds' => ['198.51.100.24:443 ssl'], 'acl_count' => 1, 'backend' => 'demo_apps',
            ]],
            'backends' => [[
                'name' => 'demo_apps', 'descr' => 'Synthetic application pool', 'balance' => 'roundrobin',
                'check_type' => 'HTTP', 'check_uri' => '/health', 'check_interval' => '5000',
                'servers' => [
                    ['name' => 'web-01', 'address' => '192.0.2.20', 'port' => '443', 'enabled' => true, 'ssl' => true, 'weight' => '100'],
                    ['name' => 'web-02', 'address' => '192.0.2.21', 'port' => '443', 'enabled' => true, 'ssl' => true, 'weight' => '100'],
                ],
            ]],
            'stats_accessors' => [],
        ];
    }

    /** @return array<string, mixed> */
    private function acme(): array
    {
        return [
            'installed' => true,
            'certificates' => [[
                'name' => 'lab-cert', 'descr' => 'Vaktpost Lab Certificate', 'account' => 'letsencrypt-production',
                'keylength' => 'ec-256', 'renew_after' => '60', 'enabled' => true,
                'domains' => ['lab.example.invalid', 'vpn.example.invalid'],
            ]],
            'accounts' => [[
                'name' => 'letsencrypt-production', 'descr' => 'Synthetic ACME account',
                'server' => 'https://acme-v02.api.letsencrypt.org/directory',
            ]],
        ];
    }

    /** @return array{available: bool, data: list<array<string, mixed>>} */
    /**
     * Traffic history for the four series pfSense's own Status → Monitoring
     * page draws, anchored to the current time rather than a fixed date.
     *
     * A fixed `$start` here was the earlier version of this method, and it
     * had the same bug as the fixed-epoch interface counters did before
     * `driftingCounter()`: every response claimed the same "last update",
     * so the app's own staleness check kept reporting a growing gap no
     * matter when it was actually asked — a few minutes old today, hours
     * old by next week. Anchoring `$lastUpdate` to now and computing
     * `age_seconds` from it the same way the real snippet does
     * (`time() - $last`) means it reads as current every time, the way an
     * RRD file that is actually being written to would.
     *
     * The requested window is read out of the script the same way slot and
     * filter are for host traffic — pulled from the literal `rrd_fetch`
     * call rather than passed as a separate payload, since this snippet
     * predates that convention. A fixed point count regardless of window
     * is a simplification of RRD's own per-resolution consolidation
     * tiers, but keeps every window's chart similarly readable rather
     * than an 8-hour view with three points or a year view with tens of
     * thousands.
     */
    private function rrdTraffic(string $script): array
    {
        preg_match('/"-s",\s*"-(\d+)"/', $script, $windowMatch);
        $windowSeconds = isset($windowMatch[1]) ? (int) $windowMatch[1] : 28_800;

        $pointCount = 48;
        $resolution = max(60, intdiv($windowSeconds, $pointCount));
        $lastUpdate = time();
        // A fixed, recent reference point for the wobble driving each
        // series' values — see driftingCounter()'s own note on why a fixed
        // Unix epoch is wrong here: it would put every value in a range
        // this chart cannot sensibly display. The trend itself does not
        // need to grow the way a cumulative byte counter does, since these
        // are rates, not counters, so there is no monotonicity constraint
        // to preserve — only a plausible day so the eye reads it as
        // "recent" rather than "years of history".
        $elapsed = time() - strtotime('2026-09-01 00:00:00 UTC');

        $series = [];
        foreach ([
            ['wan', 'inpass', 340_000.0, 47.0, 0.0],
            ['wan', 'outpass', 95_000.0, 61.0, 1.1],
            ['lan', 'inpass', 150_000.0, 53.0, 2.4],
            ['lan', 'outpass', 480_000.0, 39.0, 0.6],
        ] as [$file, $name, $avgRate, $period, $phase]) {
            $points = [];
            for ($index = 0; $index < $pointCount; $index++) {
                $at = $lastUpdate - ($pointCount - 1 - $index) * $resolution;
                $pointElapsed = $elapsed - ($pointCount - 1 - $index) * $resolution;
                $angularFrequency = 2 * M_PI / $period;
                $value = $avgRate * (1 + 0.5 * sin($angularFrequency * $pointElapsed + $phase));
                $points[] = ['at' => $at, 'value' => max(0, $value)];
            }
            $series[] = [
                'file' => $file, 'series' => $name, 'last_update' => $lastUpdate,
                'age_seconds' => time() - $lastUpdate, 'resolution' => $resolution,
                'values_seen' => $pointCount, 'values_kept' => $pointCount, 'points' => $points,
            ];
        }
        return ['available' => true, 'data' => $series];
    }

    /**
     * A byte counter that increases every second but at a rate that itself
     * drifts up and down over time, rather than a constant rate — so two
     * "live" polls a few seconds apart show a moving throughput instead of
     * a flat line, the way a real interface does.
     *
     * The wobble sits on top of a straight-line trend (avgRate) rather than
     * replacing it, and its amplitude is capped so its own rate of change
     * never exceeds avgRate. That keeps the counter strictly increasing —
     * important because the app treats any decrease as a counter reset
     * (an interface reboot) and throws the sample away rather than
     * charting a spike.
     */
    private function driftingCounter(float $baseline, float $avgRate, float $elapsed, float $period, float $phase, float $wobble = 0.6): float
    {
        if ($avgRate <= 0) {
            return $baseline;
        }
        $angularFrequency = 2 * M_PI / $period;
        $amplitude = $wobble * $avgRate / $angularFrequency;
        return $baseline + $avgRate * $elapsed + $amplitude * sin($angularFrequency * $elapsed + $phase);
    }

    /** @return list<array<string, mixed>> */
    private function interfaces(bool $degraded): array
    {
        // A fixed, recent reference point rather than the Unix epoch or a
        // wrapping value like "seconds since midnight": the former would
        // put every counter in the petabytes by now, and the latter would
        // make the counter drop at every wrap boundary, which the app reads
        // as an interface reboot and discards the sample for. A fixed date
        // in the past means elapsed time only ever grows, so the counter
        // only ever grows with it.
        $elapsed = microtime(true) - strtotime('2026-09-01 00:00:00 UTC');

        // A down interface should not be gaining traffic; freezing its
        // rate at zero here keeps opt1's degraded state consistent with
        // its counters rather than showing a "down" interface still busy.
        $opt1Rate = $degraded ? 0.0 : 60_000.0;

        return [
            ['name' => 'wan', 'descr' => 'WAN', 'hwif' => 'vtnet0', 'status' => 'up', 'enable' => true, 'ipaddr' => '198.51.100.24', 'subnet' => '255.255.255.0', 'macaddr' => '02:00:00:00:00:10', 'media' => '10Gbase-T <full-duplex>', 'gateway' => 'WAN_DHCP', 'counters_present' => true,
                'inbytes' => (int) $this->driftingCounter(938443211, 340_000, $elapsed, 47, 0.0),
                'outbytes' => (int) $this->driftingCounter(286900442, 95_000, $elapsed, 61, 1.1),
                'inpkts' => (int) $this->driftingCounter(1201900, 420, $elapsed, 47, 0.0),
                'outpkts' => (int) $this->driftingCounter(886210, 130, $elapsed, 61, 1.1),
                'inerrs' => 0, 'outerrs' => 0, 'collisions' => 0],
            ['name' => 'lan', 'descr' => 'LAN', 'hwif' => 'vtnet1', 'status' => 'up', 'enable' => true, 'ipaddr' => '192.0.2.1', 'subnet' => '255.255.255.0', 'macaddr' => '02:00:00:00:00:11', 'media' => '10Gbase-T <full-duplex>', 'counters_present' => true,
                'inbytes' => (int) $this->driftingCounter(643110223, 150_000, $elapsed, 53, 2.4),
                'outbytes' => (int) $this->driftingCounter(1224771109, 480_000, $elapsed, 39, 0.6),
                'inpkts' => (int) $this->driftingCounter(945110, 190, $elapsed, 53, 2.4),
                'outpkts' => (int) $this->driftingCounter(1442992, 560, $elapsed, 39, 0.6),
                'inerrs' => 0, 'outerrs' => 0, 'collisions' => 0],
            ['name' => 'opt1', 'descr' => 'OPENVPN1', 'hwif' => 'ovpns1', 'status' => $degraded ? 'down' : 'up', 'enable' => true, 'ipaddr' => '192.0.2.129', 'subnet' => '255.255.255.0', 'counters_present' => true,
                'inbytes' => (int) $this->driftingCounter(88120554, $opt1Rate, $elapsed, 29, 3.5),
                'outbytes' => (int) $this->driftingCounter(42771209, $opt1Rate * 0.4, $elapsed, 29, 3.5),
                'inpkts' => (int) $this->driftingCounter(152110, $opt1Rate / 700, $elapsed, 29, 3.5),
                'outpkts' => (int) $this->driftingCounter(98002, ($opt1Rate * 0.4) / 700, $elapsed, 29, 3.5),
                'inerrs' => 0, 'outerrs' => 0, 'collisions' => 0],
        ];
    }

    /**
     * Per-host bandwidth for one interface, synthesized from a small fixed
     * catalog of hosts per interface rather than a real packet capture.
     * `slot`, and the filter/sort `printBandwidth` was called with, are read
     * out of the snippet text the same way every other value here is —
     * they're embedded directly in the script rather than passed as part of
     * the payload, since this snippet predates the payload convention.
     *
     * @return array<string, mixed>
     */
    private function hostTraffic(string $script): array
    {
        preg_match('/\$vaktpost_slot = (\d+);/', $script, $slotMatch);
        preg_match('/printBandwidth\(\$vaktpost_key, "(\w*)", "(\w*)"/', $script, $paramsMatch);
        $slot = isset($slotMatch[1]) ? (int) $slotMatch[1] : 0;
        $filter = $paramsMatch[1] ?? 'local';
        $sort = $paramsMatch[2] ?? 'in';

        $interfaces = [
            ['key' => 'wan', 'descr' => 'WAN', 'device' => 'vtnet0'],
            ['key' => 'lan', 'descr' => 'LAN', 'device' => 'vtnet1'],
            ['key' => 'opt1', 'descr' => 'OPENVPN1', 'device' => 'ovpns1'],
        ];
        if (!isset($interfaces[$slot])) {
            return [
                'available' => false, 'interface' => '', 'descr' => '', 'device' => '',
                'slot' => $slot, 'reason' => 'This firewall has no interface in that position.',
                'raw' => '', 'data' => [],
            ];
        }
        $iface = $interfaces[$slot];

        // A small, fixed set of hosts per interface: "local" ones matching
        // the same addresses the Clients tab already shows via ARP/DHCP,
        // "remote" ones representing traffic to or from the internet. WAN
        // genuinely has no hosts of its own behind it, so its local set is
        // empty — matching how a real WAN interface has no local subnet.
        $catalog = [
            'wan' => ['local' => [], 'remote' => ['203.0.113.66', '198.51.100.5', '203.0.113.81']],
            'lan' => ['local' => ['192.0.2.20', '192.0.2.53', '192.0.2.110', '192.0.2.111'], 'remote' => ['203.0.113.10', '198.51.100.20']],
            'opt1' => ['local' => ['192.0.2.210'], 'remote' => ['203.0.113.42']],
        ];
        $pool = $catalog[$iface['key']] ?? ['local' => [], 'remote' => []];
        if ($filter === 'local') {
            $hosts = $pool['local'];
        } elseif ($filter === 'remote') {
            $hosts = $pool['remote'];
        } else {
            $hosts = array_merge($pool['local'], $pool['remote']);
        }

        if (empty($hosts)) {
            return [
                'available' => true, 'interface' => $iface['key'], 'descr' => $iface['descr'],
                'device' => $iface['device'], 'slot' => $slot, 'reason' => '', 'raw' => '', 'data' => [],
            ];
        }

        // A time-varying instantaneous rate per host, distinct per host and
        // per direction so the numbers move between polls rather than
        // sitting flat. This is a fresh capture each call, not a counter,
        // so unlike interface byte counts there is no monotonicity
        // constraint to respect here.
        $now = microtime(true);
        $rows = [];
        foreach ($hosts as $ip) {
            $seed = crc32($ip);
            $phaseIn = ($seed % 100) / 100 * 2 * M_PI;
            $phaseOut = (($seed >> 8) % 100) / 100 * 2 * M_PI;
            $baseIn = 200_000 + ($seed % 900_000);
            $baseOut = 80_000 + (($seed >> 4) % 400_000);
            $bitsIn = max(0, $baseIn * (1 + 0.5 * sin($now / 7 + $phaseIn)));
            $bitsOut = max(0, $baseOut * (1 + 0.5 * sin($now / 11 + $phaseOut)));
            $rows[] = [
                'ip' => $ip,
                'in_text' => $this->formatRate($bitsIn),
                'out_text' => $this->formatRate($bitsOut),
                'sort_in' => $bitsIn,
                'sort_out' => $bitsOut,
            ];
        }

        $sortKey = $sort === 'out' ? 'sort_out' : 'sort_in';
        usort($rows, function (array $a, array $b) use ($sortKey): int {
            return $b[$sortKey] <=> $a[$sortKey];
        });
        $rows = array_slice($rows, 0, 10);
        foreach ($rows as $i => $row) {
            unset($rows[$i]['sort_in'], $rows[$i]['sort_out']);
        }

        $rawParts = [];
        foreach ($rows as $row) {
            $rawParts[] = $row['ip'] . ';' . $row['in_text'] . ';' . $row['out_text'];
        }
        $raw = implode('|', $rawParts) . '|';

        return [
            'available' => true,
            'interface' => $iface['key'],
            'descr' => $iface['descr'],
            'device' => $iface['device'],
            'slot' => $slot,
            'reason' => '',
            'raw' => $raw,
            'data' => array_values($rows),
        ];
    }

    /**
     * Formats a bits-per-second value the way `rate` prints one: a bare
     * integer under 1000, otherwise a two-decimal value with a K or M
     * suffix.
     */
    private function formatRate(float $bitsPerSecond): string
    {
        if ($bitsPerSecond >= 1_000_000) {
            return number_format($bitsPerSecond / 1_000_000, 2) . 'M';
        }
        if ($bitsPerSecond >= 1_000) {
            return number_format($bitsPerSecond / 1_000, 2) . 'K';
        }
        return (string) (int) round($bitsPerSecond);
    }

    /** @return array{data: array<string, array<string, mixed>>} */
    private function gateways(bool $degraded): array
    {
        return ['data' => ['WAN_DHCP' => ['name' => 'WAN_DHCP', 'monitor_ip' => '203.0.113.1', 'source_ip' => '198.51.100.24', 'status' => $degraded ? 'down' : 'online', 'substatus' => $degraded ? 'highloss' : 'none', 'delay' => $degraded ? 116.4 : 11.8, 'stddev' => 1.7, 'loss' => $degraded ? 32 : 0]]];
    }

    /** @return list<array<string, mixed>> */
    private function services(bool $degraded): array
    {
        return [['name' => 'unbound', 'description' => 'DNS Resolver', 'status' => 'running'], ['name' => 'dhcpd', 'description' => 'DHCP Server', 'status' => 'running'], ['name' => 'openvpn', 'description' => 'OpenVPN server', 'status' => $degraded ? 'stopped' : 'running'], ['name' => 'ntpd', 'description' => 'NTP clock sync', 'status' => 'running']];
    }

    /** @return list<array<string, mixed>> */
    private function firewallRules(): array
    {
        return [
            ['tracker' => '1700000001', 'type' => 'pass', 'interface' => 'lan', 'ipprotocol' => 'inet', 'protocol' => 'tcp', 'source' => ['network' => 'lan'], 'destination' => ['address' => 'demo_web_servers', 'port' => '443'], 'descr' => 'Allow HTTPS to demo services'],
            ['tracker' => '1700000002', 'type' => 'block', 'interface' => 'wan', 'ipprotocol' => 'inet', 'protocol' => 'any', 'source' => ['any' => true], 'destination' => ['network' => 'wanip'], 'descr' => 'Default deny (synthetic)', 'log' => ''],
            ['tracker' => '1700000003', 'type' => 'pass', 'interface' => 'opt1', 'ipprotocol' => 'inet', 'protocol' => 'udp', 'source' => ['network' => 'opt1'], 'destination' => ['address' => 'demo_dns', 'port' => '53'], 'descr' => 'VPN DNS access'],
        ];
    }

    /** @return list<array<string, mixed>> */
    private function aliases(): array
    {
        return [['name' => 'demo_web_servers', 'type' => 'host', 'address' => '192.0.2.20 192.0.2.21', 'detail' => 'Web 1||Web 2', 'descr' => 'Synthetic application hosts'], ['name' => 'demo_dns', 'type' => 'host', 'address' => '192.0.2.53', 'detail' => 'Resolver', 'descr' => 'Synthetic DNS resolver'], ['name' => 'demo_web_ports', 'type' => 'port', 'address' => '80 443', 'detail' => 'HTTP||HTTPS', 'descr' => 'Web ports']];
    }

    /** @return list<array<string, mixed>> */
    private function portForwards(): array
    {
        return [['tracker' => '1800000001', 'interface' => 'wan', 'protocol' => 'tcp', 'ipprotocol' => 'inet', 'source' => ['any' => true], 'destination' => ['network' => 'wanip', 'port' => '443'], 'target' => '192.0.2.20', 'local-port' => '443', 'descr' => 'Demo HTTPS forward']];
    }

    /** @return array{data: list<array<string, mixed>>} */
    private function notices(): array
    {
        return ['data' => [['id' => 'demo-notice', 'notice' => 'This is a synthetic Vaktpost review environment. No real firewall is connected.', 'priority' => 3, 'created_at' => '1789462800']]];
    }

    /** @return array{data: list<array<string, mixed>>} */
    private function certificates(): array
    {
        return ['data' => [['refid' => 'demo-cert', 'descr' => 'Vaktpost Lab Certificate', 'is_ca' => false, 'is_acme' => true, 'valid_from' => 1789462800, 'valid_until' => 1820998800]]];
    }

    /** @return array{data: list<array<string, mixed>>} */
    private function dynamicDns(): array
    {
        return ['data' => [['host' => 'lab', 'domain' => 'example.invalid', 'fqdn' => 'lab.example.invalid', 'ip' => '198.51.100.24', 'updated' => 1789462800, 'provider' => 'demo']]];
    }

    private function decodeUpdateKind(string $script): string
    {
        if (preg_match('/\$vaktpost_payload\s*=\s*"([A-Za-z0-9+\/=]+)"/', $script, $matches) !== 1) {
            return 'package';
        }
        $decoded = base64_decode($matches[1], true);
        if ($decoded === false) {
            return 'package';
        }
        $payload = json_decode($decoded, true);
        return is_array($payload) && ($payload['kind'] ?? null) === 'firmware' ? 'firmware' : 'package';
    }
}
