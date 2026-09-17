(function () {
  'use strict';

  const password = document.body.dataset.demoPassword || 'vaktpost-demo';
  const labels = {
    connection: 'Connection',
    dashboard: 'Dashboard',
    interfaces: 'Interfaces',
    clients: 'Clients',
    packages: 'Packages',
    updates: 'Package updates',
    rules: 'Firewall rules',
    logs: 'Firewall log poll',
    logBurst: 'Firewall log burst',
    logReset: 'Reset firewall log',
  };
  const profiles = {
    review: ['Healthy review', 'All core services are healthy.'],
    updates: ['Updates available', 'Firmware and one package are outdated.'],
    degraded: ['Degraded network', 'A gateway, VPN, and service report problems.'],
    fault: ['XML-RPC fault', 'Sign-in succeeds; feature requests return a deliberate fault.'],
    noaccess: ['No privilege', 'The password is right, but the account lacks System - HA node sync.'],
  };
  const scripts = {
    connection: '$toreturn = ["version" => trim(file_get_contents("/etc/version"))];',
    dashboard: '$vaktpost_batch = []; $vaktpost_batch["telemetry"] = []; $vaktpost_batch["firmware"] = []; $toreturn = ["sections" => $vaktpost_batch];',
    interfaces: '$rows = []; foreach (get_configured_interface_with_descr() as $ifdescr => $ifname) { $rows[] = $ifdescr; } $toreturn = ["data" => $rows];',
    clients: '$vaktpost_batch = []; $vaktpost_batch["arp_table"] = []; $vaktpost_batch["dhcp_leases"] = []; $toreturn = ["sections" => $vaktpost_batch];',
    packages: 'global $config; $installed = $config["installedpackages"]; $toreturn = ["data" => $installed["package"]];',
    updates: '$rows = []; $info = get_pkg_info("all", false, true); $toreturn = ["available" => true, "data" => $rows];',
    rules: 'global $config; $filter = $config["filter"]; $toreturn = ["data" => $filter["rule"]];',
    logs: '$path = "/var/log/filter.log"; $chunk = file_get_contents($path); $toreturn = ["data" => []];',
    logBurst: '/* VAKTPOST_LAB_LOG_BURST */ $path = "/var/log/filter.log"; $toreturn = ["data" => []];',
    logReset: '/* VAKTPOST_LAB_LOG_RESET */ $path = "/var/log/filter.log"; $toreturn = ["data" => []];',
  };
  let scenario = 'review';
  let probe = 'dashboard';

  const baseUrl = document.getElementById('base-url');
  baseUrl.textContent = window.location.origin;

  function xmlEscape(value) {
    return value.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');
  }

  function decodePayload(xml) {
    const match = xml.match(/<string>([\s\S]*?)<\/string>/);
    if (!match) return { response: xml.slice(0, 500) };
    const json = match[1].replaceAll('&lt;', '<').replaceAll('&gt;', '>').replaceAll('&quot;', '"').replaceAll('&apos;', "'").replaceAll('&amp;', '&');
    try { return JSON.parse(json); } catch { return { response: json }; }
  }

  document.querySelectorAll('[data-copy]').forEach((button) => {
    button.addEventListener('click', async () => {
      const node = document.getElementById(button.dataset.copy);
      const value = node.dataset.copyValue || node.textContent;
      await navigator.clipboard.writeText(value);
      const old = button.textContent;
      button.textContent = 'Copied';
      window.setTimeout(() => { button.textContent = old; }, 1200);
    });
  });

  document.querySelectorAll('[data-scenario]').forEach((button) => {
    button.addEventListener('click', () => {
      scenario = button.dataset.scenario;
      document.querySelectorAll('[data-scenario]').forEach((item) => item.setAttribute('aria-selected', String(item === button)));
      document.getElementById('username').textContent = scenario;
      document.getElementById('scenario-title').textContent = profiles[scenario][0];
      document.getElementById('scenario-detail').textContent = profiles[scenario][1];
    });
  });

  document.querySelectorAll('[data-probe]').forEach((button) => {
    button.addEventListener('click', () => {
      probe = button.dataset.probe;
      document.querySelectorAll('[data-probe]').forEach((item) => item.classList.toggle('is-selected', item === button));
      document.getElementById('run-probe').textContent = `Run ${labels[probe]} probe`;
    });
  });

  document.getElementById('run-probe').addEventListener('click', async (event) => {
    const button = event.currentTarget;
    const output = document.getElementById('response-output');
    const status = document.getElementById('response-status');
    const started = performance.now();
    button.disabled = true;
    button.textContent = 'Sending…';
    status.className = '';
    status.textContent = 'Waiting';
    try {
      const body = `<?xml version="1.0"?><methodCall><methodName>pfsense.exec_php</methodName><params><param><value><string>${xmlEscape(scripts[probe])}</string></value></param></params></methodCall>`;
      const response = await fetch('xmlrpc.php', {
        method: 'POST',
        credentials: 'same-origin',
        headers: { 'Content-Type': 'text/xml; charset=utf-8', Authorization: `Basic ${btoa(`${scenario}:${password}`)}` },
        body,
      });
      const text = await response.text();
      status.textContent = `${response.status} · ${Math.round(performance.now() - started)} ms`;
      status.className = response.ok ? 'is-ok' : 'is-error';
      output.textContent = JSON.stringify(decodePayload(text), null, 2);
    } catch (error) {
      status.textContent = 'Network error';
      status.className = 'is-error';
      output.textContent = String(error);
    } finally {
      button.disabled = false;
      button.textContent = `Run ${labels[probe]} probe`;
    }
  });
})();
