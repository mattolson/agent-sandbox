"""
Proxy address guard addon for mitmproxy.

Runs next to the policy enforcer in the same mitmdump process. The policy
decides which names the agent may reach; this addon decides which addresses
those names may resolve to. An allowed name whose DNS answer is loopback,
private, link-local, the cloud metadata endpoint, the sandbox's own network,
or any other non-global address is refused before the proxy dials it.

How it works:
  - `server_connect` fires for every upstream connection mitmproxy opens:
    CONNECT tunnels, decrypted requests, and plain HTTP alike. The guard
    resolves the host there and refuses the connection, by setting
    `server.error`, if any answer is denied. Nothing is sent to the address.
  - Otherwise the guard pins the dial to the answers it checked. mitmproxy dials
    with `asyncio.open_connection(host, port)`, which resolves through the
    running loop's `getaddrinfo`. The guard wraps that one method on that one
    loop and returns the checked answers for the key it just staged, so a
    second lookup cannot hand the dial a different address. Every other lookup
    passes through unchanged. A lookup that fails during the check is pinned as a
    failure, so the dial cannot fall back to a fresh, unchecked lookup.
    `server.address` is never modified: it stays the
    hostname, which keeps SNI, certificate verification, connection reuse, and
    `request.host` intact.
  - Hosts written as IP literals are not checked. The guard protects a name from
    being pointed somewhere unexpected; a literal is an explicit address in a
    policy the agent cannot edit.
  - Refusals reach the client as the enforcer's 403. On a CONNECT the enforcer
    replaces mitmproxy's 502 in `http_connect_error`. A plain `http` request's
    connection opens after the request hooks, and mitmproxy's error response
    there cannot be replaced, so the guard's own `requestheaders` hook checks
    those requests first and hands a refusal to the enforcer's `on_refused`
    callback. The connection is still checked and pinned when it opens.

The wrapper relies on two facts about the pinned mitmproxy and Python: that
mitmproxy dials by hostname through `asyncio.open_connection`, and that asyncio
resolves through `loop.getaddrinfo`. `test_address_guard.py` and the
integration tests fail if either stops holding. If the wrapper cannot be
installed, the guard refuses every connection to a name rather than run
unpinned.

Environment variables:
  PROXY_MODE: enforce refuses; log records what would be refused and refuses
    nothing.
  PROXY_LOG_LEVEL: quiet suppresses the per-refusal events.
"""

from __future__ import annotations

import asyncio
import ipaddress
import json
import os
import socket
import sys
import time
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path


REFUSAL_MARKER = "agent-sandbox address guard:"
STAGE_SECONDS = 5.0

# Checked in order; the first match names the class. The specific names come
# before the general ones so the log says `metadata`, not `link_local`.
METADATA_NETWORKS = (
    ipaddress.ip_network("169.254.169.254/32"),
    ipaddress.ip_network("fd00:ec2::254/128"),
)
DENIED_NETWORKS = (
    ("loopback", ipaddress.ip_network("127.0.0.0/8")),
    ("loopback", ipaddress.ip_network("::1/128")),
    ("private", ipaddress.ip_network("10.0.0.0/8")),
    ("private", ipaddress.ip_network("172.16.0.0/12")),
    ("private", ipaddress.ip_network("192.168.0.0/16")),
    ("unique_local", ipaddress.ip_network("fc00::/7")),
    ("link_local", ipaddress.ip_network("169.254.0.0/16")),
    ("link_local", ipaddress.ip_network("fe80::/10")),
    ("shared", ipaddress.ip_network("100.64.0.0/10")),
    ("unspecified", ipaddress.ip_network("0.0.0.0/8")),
    ("unspecified", ipaddress.ip_network("::/128")),
    ("multicast", ipaddress.ip_network("224.0.0.0/4")),
    ("multicast", ipaddress.ip_network("ff00::/8")),
)


def parse_ip(value):
    """Parse an address string, dropping an IPv6 zone suffix. Returns None if it is not an IP."""
    try:
        return ipaddress.ip_address(value.split("%", 1)[0])
    except ValueError:
        return None


def classify_address(address, sandbox_networks=()):
    """Return the denied class of an address, or None when it may be dialled."""
    ip = parse_ip(address) if isinstance(address, str) else address
    if ip is None:
        return "unparseable"
    if ip.version == 6 and ip.ipv4_mapped is not None:
        ip = ip.ipv4_mapped
    for network in METADATA_NETWORKS:
        if ip.version == network.version and ip in network:
            return "metadata"
    for network in sandbox_networks:
        if ip.version == network.version and ip in network:
            return "sandbox_network"
    for name, network in DENIED_NETWORKS:
        if ip.version == network.version and ip in network:
            return name
    if not ip.is_global:
        return "reserved"
    return None


def _ipv4_network_from_route(destination_hex, mask_hex):
    destination = ipaddress.IPv4Address(int.from_bytes(bytes.fromhex(destination_hex), "little"))
    mask = ipaddress.IPv4Address(int.from_bytes(bytes.fromhex(mask_hex), "little"))
    return ipaddress.IPv4Network(f"{destination}/{mask}", strict=False)


def read_sandbox_networks(proc_root="/proc"):
    """The networks this container is attached to, from its routing tables.

    Default routes, loopback, link-local, multicast, and host routes are skipped;
    what remains is the compose network the proxy shares with the agent. On a
    default Docker daemon these are also `private`; the specific name matters
    when a daemon hands out pools outside RFC 1918. Unreadable tables yield
    nothing rather than an error.
    """
    networks = []
    try:
        lines = Path(proc_root, "net", "route").read_text().splitlines()[1:]
    except OSError:
        lines = []
    for line in lines:
        fields = line.split()
        if len(fields) < 8 or fields[0] == "lo":
            continue
        try:
            network = _ipv4_network_from_route(fields[1], fields[7])
        except ValueError:
            continue
        if network.prefixlen == 0 or network.prefixlen == 32:
            continue
        if network not in networks:
            networks.append(network)
    try:
        lines = Path(proc_root, "net", "ipv6_route").read_text().splitlines()
    except OSError:
        lines = []
    for line in lines:
        fields = line.split()
        if len(fields) < 10 or fields[9] == "lo":
            continue
        try:
            prefix = int(fields[1], 16)
            address = ipaddress.IPv6Address(bytes.fromhex(fields[0]))
            network = ipaddress.IPv6Network(f"{address}/{prefix}", strict=False)
        except ValueError:
            continue
        if prefix == 0 or prefix == 128 or network.is_link_local or network.is_multicast:
            continue
        if network not in networks:
            networks.append(network)
    return networks


@dataclass(frozen=True)
class Refusal:
    host: str
    port: int
    address: str
    address_class: str
    answers: tuple

    def message(self):
        return (
            f"{REFUSAL_MARKER} {self.host} resolves to {self.address} "
            f"({self.address_class}); refused"
        )


def is_refusal_message(text):
    return isinstance(text, str) and text.startswith(REFUSAL_MARKER)


class PinningUnavailable(RuntimeError):
    """The loop's getaddrinfo could not be wrapped, so dials cannot be pinned."""


class _StdoutJsonLogger:
    """Minimal stand-in for the enforcer's JsonLogger when the addon runs alone."""

    def __init__(self, log_level="normal", stream=None):
        self.log_level = log_level
        self.stream = stream if stream is not None else sys.stdout

    def timestamp(self):
        return datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S")

    def event(self, entry, always=False):
        if self.log_level == "quiet" and not always:
            return
        print(json.dumps(entry), file=self.stream, flush=True)


class AddressGuard:
    def __init__(
        self,
        mode=None,
        logger=None,
        log_level=None,
        resolver=None,
        sandbox_networks=None,
        clock=None,
        on_refused=None,
        classifier=None,
    ):
        self.mode = mode or os.getenv("PROXY_MODE", "log")
        self.log_level = log_level or os.getenv("PROXY_LOG_LEVEL", "normal")
        self.logger = logger or _StdoutJsonLogger(log_level=self.log_level)
        # resolver(host, port) -> getaddrinfo-style tuples. Defaults to the real
        # loop.getaddrinfo, captured before the wrapper replaces it.
        self.resolver = resolver
        self.sandbox_networks = sandbox_networks
        self.clock = clock or time.monotonic
        # classifier(address, sandbox_networks) -> denied class or None.
        self.classifier = classifier or classify_address
        # on_refused(flow, refusal) answers a refused plain-http request; the
        # enforcer supplies it so the refusal gets its 403 and its stored decision.
        self.on_refused = on_refused
        self._staged = {}
        self._pinned_loop = None
        self._real_getaddrinfo = None

    # --- mitmproxy hooks -------------------------------------------------

    def load(self, loader):
        if self.sandbox_networks is None:
            self.sandbox_networks = read_sandbox_networks()

    def running(self):
        try:
            self.install_pinning(asyncio.get_running_loop())
        except PinningUnavailable as error:
            self._log({"action": "pinning_unavailable", "error": str(error)}, always=True)
            return
        self._log(
            {
                "action": "enabled",
                "sandbox_networks": [str(network) for network in self.sandbox_networks or ()],
            },
            always=True,
        )

    async def server_connect(self, data):
        server = data.server
        if server.error or not server.address:
            return
        host, port = server.address
        if parse_ip(host) is not None:
            return
        if self.mode == "enforce":
            try:
                self.install_pinning(asyncio.get_running_loop())
            except PinningUnavailable as error:
                server.error = f"{REFUSAL_MARKER} {host} not dialled; pinning unavailable ({error})"
                return
        try:
            answers = await self._resolve(host, port)
        except OSError as error:
            # Pin the failure too. Without it the dial would look the name up again,
            # unchecked, and a nameserver could fail the check and answer the dial with
            # a private address. The dial now fails with the same error, and mitmproxy
            # reports it as it would any failed lookup.
            if self.mode == "enforce":
                self._stage(host, port, error)
            return
        refusal = self.check(host, port, answers)
        if refusal is not None:
            self._log_refusal(refusal, phase="connect")
            if self.mode == "enforce":
                server.error = refusal.message()
            return
        if self.mode == "enforce":
            self._stage(host, port, answers)

    async def requestheaders(self, flow):
        """Refuse a plain `http` request before its connection opens.

        Runs after the enforcer's hook, so a request the policy already blocked
        is left alone. Requests inside a tunnel use the connection the CONNECT
        opened, which `server_connect` already checked.
        """
        if self.mode != "enforce" or self.on_refused is None:
            return
        if flow.response is not None or flow.request.scheme != "http":
            return
        host, port = flow.request.host, flow.request.port
        if parse_ip(host) is not None:
            return
        try:
            answers = await self._resolve(host, port)
        except OSError:
            return
        refusal = self.check(host, port, answers)
        if refusal is not None:
            self._log_refusal(refusal, phase="request")
            self.on_refused(flow, refusal)

    def check(self, host, port, answers):
        """The first denied answer as a Refusal, or None when every answer may be dialled."""
        addresses = tuple(dict.fromkeys(info[4][0] for info in answers))
        for address in addresses:
            address_class = self.classifier(address, self.sandbox_networks or ())
            if address_class is not None:
                return Refusal(host, port, address, address_class, addresses)
        return None

    # --- pinning ---------------------------------------------------------

    def install_pinning(self, loop):
        """Wrap `loop.getaddrinfo` so staged keys return their checked answers. Idempotent."""
        if self._pinned_loop is loop:
            return
        real = loop.getaddrinfo
        try:
            loop.getaddrinfo = self._pinned_getaddrinfo
        except (AttributeError, TypeError) as error:
            raise PinningUnavailable(f"cannot wrap {type(loop).__name__}.getaddrinfo: {error}") from error
        if loop.getaddrinfo != self._pinned_getaddrinfo:
            raise PinningUnavailable(f"{type(loop).__name__}.getaddrinfo did not take the wrapper")
        self._real_getaddrinfo = real
        self._pinned_loop = loop

    async def _pinned_getaddrinfo(self, host, port, *args, **kwargs):
        staged = self._staged.get((host, port))
        if staged is not None:
            answers, expires = staged
            if self.clock() < expires:
                if isinstance(answers, OSError):
                    raise type(answers)(*answers.args)
                family = kwargs.get("family", args[0] if args else 0)
                if family:
                    answers = [info for info in answers if info[0] == family]
                return list(answers)
        return await self._real_getaddrinfo(host, port, *args, **kwargs)

    def _stage(self, host, port, answers):
        """Stage checked answers, or the error the check's lookup raised, for the dial."""
        now = self.clock()
        for key in [key for key, (_, expires) in self._staged.items() if expires <= now]:
            del self._staged[key]
        staged = answers if isinstance(answers, OSError) else tuple(answers)
        self._staged[(host, port)] = (staged, now + STAGE_SECONDS)

    async def _resolve(self, host, port):
        if self.resolver is not None:
            return await self.resolver(host, port)
        getaddrinfo = self._real_getaddrinfo or asyncio.get_running_loop().getaddrinfo
        return await getaddrinfo(host, port, type=socket.SOCK_STREAM)

    # --- logging ---------------------------------------------------------

    def _log_refusal(self, refusal, phase):
        self._log(
            {
                "action": "blocked" if self.mode == "enforce" else "logged",
                "phase": phase,
                "host": refusal.host,
                "port": refusal.port,
                "address": refusal.address,
                "address_class": refusal.address_class,
                "answers": list(refusal.answers),
            }
        )

    def _log(self, fields, always=False):
        entry = {"ts": self.logger.timestamp(), "type": "address_guard"}
        entry.update(fields)
        self.logger.event(entry, always=always)
