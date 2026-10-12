"""Test-only mitmdump addon: gives the address guard a fake DNS table.

Loaded after the enforcer with an extra `-s` by the integration harness, never
by the proxy image. It lets a test make a name "resolve" to any address
without real DNS, and let chosen addresses past the classifier so a pinned
dial can reach a loopback upstream. Configuration comes from the environment:

  AGENTBOX_TEST_GUARD_DNS      JSON object, host -> list of addresses
  AGENTBOX_TEST_GUARD_ALLOW    JSON list of addresses the classifier passes
  AGENTBOX_TEST_GUARD_SANDBOX  JSON list of CIDRs used as the sandbox networks

Hosts missing from the table resolve for real.
"""

import asyncio
import ipaddress
import json
import os
import socket

from mitmproxy import ctx

import address_guard


def _load_json(name, default):
    value = os.environ.get(name)
    return json.loads(value) if value else default


class AddressGuardTestConfig:
    def load(self, loader):
        guard = ctx.master.addons.get("addressguard")
        if guard is None:
            raise RuntimeError("address guard addon not loaded; load the enforcer first")
        table = _load_json("AGENTBOX_TEST_GUARD_DNS", {})
        allowed = set(_load_json("AGENTBOX_TEST_GUARD_ALLOW", []))
        sandbox = _load_json("AGENTBOX_TEST_GUARD_SANDBOX", None)

        async def resolver(host, port):
            if host in table:
                infos = []
                for address in table[host]:
                    if ":" in address:
                        infos.append((socket.AF_INET6, socket.SOCK_STREAM, 6, "", (address, port, 0, 0)))
                    else:
                        infos.append((socket.AF_INET, socket.SOCK_STREAM, 6, "", (address, port)))
                return infos
            loop = asyncio.get_running_loop()
            return await loop.run_in_executor(
                None, socket.getaddrinfo, host, port, 0, socket.SOCK_STREAM
            )

        def classifier(address, sandbox_networks):
            if address in allowed:
                return None
            return address_guard.classify_address(address, sandbox_networks)

        guard.resolver = resolver
        guard.classifier = classifier
        if sandbox is not None:
            guard.sandbox_networks = [ipaddress.ip_network(cidr) for cidr in sandbox]
        print(json.dumps({"type": "info", "msg": "address guard test config loaded"}), flush=True)


addons = [AddressGuardTestConfig()]
