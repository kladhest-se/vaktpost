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
            return ['payload' => $this->rrdTraffic()];
        }

        $log = $this->logRequest($script);
        if ($log !== null) {
            return ['payload' => $log];
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
    private function rrdTraffic(): array
    {
        $start = 1789461000;
        $series = [];
        foreach ([['wan', 'inpass', 192000.0], ['wan', 'outpass', 64000.0], ['lan', 'inpass', 88000.0], ['lan', 'outpass', 210000.0]] as $definition) {
            [$file, $name, $base] = $definition;
            $points = [];
            for ($index = 0; $index < 12; $index++) {
                $points[] = ['at' => $start + ($index * 300), 'value' => $base + (($index % 4) * 12500)];
            }
            $series[] = [
                'file' => $file, 'series' => $name, 'last_update' => $start + 3300,
                'age_seconds' => 60, 'resolution' => 300, 'values_seen' => 12,
                'values_kept' => 12, 'points' => $points,
            ];
        }
        return ['available' => true, 'data' => $series];
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
