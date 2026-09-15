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
        if (str_contains($script, '$config["filter"]')) {
            return ['payload' => ['data' => $this->firewallRules()]];
        }
        if (str_contains($script, '$config["aliases"]')) {
            return ['payload' => ['data' => $this->aliases()]];
        }
        if (str_contains($script, '$config["nat"]') && !str_contains($script, 'separator')) {
            return ['payload' => ['data' => $this->portForwards()]];
        }
        if (str_contains($script, 'is_subsystem_dirty') && str_contains($script, 'separator')) {
            return ['payload' => ['filter' => [['interface' => 'lan', 'key' => 'sep0', 'text' => 'Application access', 'color' => 'info', 'position' => '0']], 'nat' => [], 'apply_pending' => false]];
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

        // Optional detail screens return harmless empty shapes only for reviewed,
        // distinctive pfSense/Vaktpost signatures.
        $emptyDataSignatures = ['pfctl_table', 'pfBlockerNG', 'DNSBL', 'haproxy', 'acme', 'clog', 'rrd', 'get_dhcp_leases', 'get_static_maps', 'get_host_overrides'];
        foreach ($emptyDataSignatures as $signature) {
            if (stripos($script, $signature) !== false) {
                return ['payload' => ['data' => []]];
            }
        }

        return ['fault' => ['code' => -32602, 'message' => 'The lab refused an unknown snippet; submitted PHP is never executed']];
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
        return [
            'hostname' => 'vaktpost-lab', 'domain' => 'example.invalid', 'platform' => 'Virtual pfSense test appliance', 'serial' => 'SYNTHETIC-ONLY',
            'cpu_count' => 4, 'cpu_ticks_total' => 8400000, 'cpu_ticks_idle' => 7240000, 'mem_usage' => 31, 'swap_usage' => 0, 'uptime_sec' => 1248920,
            'temp_c' => 48, 'temp_source' => 'dev.cpu.0.temperature',
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

    /** @return list<array<string, mixed>> */
    private function interfaces(bool $degraded): array
    {
        return [
            ['name' => 'wan', 'descr' => 'WAN', 'hwif' => 'vtnet0', 'status' => 'up', 'enable' => true, 'ipaddr' => '198.51.100.24', 'subnet' => '255.255.255.0', 'macaddr' => '02:00:00:00:00:10', 'media' => '10Gbase-T <full-duplex>', 'gateway' => 'WAN_DHCP', 'counters_present' => true, 'inbytes' => 938443211, 'outbytes' => 286900442, 'inpkts' => 1201900, 'outpkts' => 886210, 'inerrs' => 0, 'outerrs' => 0, 'collisions' => 0],
            ['name' => 'lan', 'descr' => 'LAN', 'hwif' => 'vtnet1', 'status' => 'up', 'enable' => true, 'ipaddr' => '192.0.2.1', 'subnet' => '255.255.255.0', 'macaddr' => '02:00:00:00:00:11', 'media' => '10Gbase-T <full-duplex>', 'counters_present' => true, 'inbytes' => 643110223, 'outbytes' => 1224771109, 'inpkts' => 945110, 'outpkts' => 1442992, 'inerrs' => 0, 'outerrs' => 0, 'collisions' => 0],
            ['name' => 'opt1', 'descr' => 'OPENVPN1', 'hwif' => 'ovpns1', 'status' => $degraded ? 'down' : 'up', 'enable' => true, 'ipaddr' => '192.0.2.129', 'subnet' => '255.255.255.0', 'counters_present' => true, 'inbytes' => 88120554, 'outbytes' => 42771209, 'inpkts' => 152110, 'outpkts' => 98002, 'inerrs' => 0, 'outerrs' => 0, 'collisions' => 0],
        ];
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
