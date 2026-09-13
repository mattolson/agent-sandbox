"""
DNS sinkhole addon for mitmproxy.

Runs next to the HTTP policy enforcer in the same mitmdump process, in DNS
mode (`--mode dns@5353`). The agent container's firewall rewrites its port 53
traffic to this listener and rejects every other resolver, so this addon is
the only thing that ever answers a name for the agent.

Behaviour:
  - A name in the allowed set with an A or AAAA question is resolved through
    this container's own resolver and answered with a short TTL. That set is
    the compose service names the agent must reach, `proxy` by default.
  - A name in the allowed set with any other question type gets an empty
    NOERROR answer.
  - Every other name gets NXDOMAIN, immediately, so a blocked lookup fails
    fast instead of hanging on a timeout.
  - A query the addon does not answer at all gets SERVFAIL from mitmproxy's
    DNS layer, because DNS mode has no upstream server. That is the fail-closed
    property, and it is why the built-in DnsResolver addon is removed at load:
    it runs before script addons and would resolve every query upstream first.

The addon never resolves a name outside the allowed set. This container's
resolver forwards unknown names to the host, so asking it about arbitrary
names would move the exfiltration channel to the proxy rather than close it.

Environment variables:
  AGENTBOX_DNS_ALLOW: comma-separated exact names to answer in addition to
    `proxy`. Wildcards are rejected. Set it on the proxy service when the
    agent must reach another sidecar by name.
  PROXY_LOG_LEVEL: quiet suppresses the per-refusal events; normal (default)
    logs each refused name once per query.
"""

from __future__ import annotations

import asyncio
import ipaddress
import json
import os
import re
import socket
import sys
from datetime import datetime, timezone

try:
    from mitmproxy import ctx, dns
    from mitmproxy.net.dns import classes, op_codes, response_codes, types
except ImportError:  # pragma: no cover - unit tests may import without mitmproxy.
    ctx = None
    dns = None
    classes = None
    op_codes = None
    response_codes = None
    types = None


ALLOW_ENV = "AGENTBOX_DNS_ALLOW"
DEFAULT_ALLOWED_NAMES = frozenset({"proxy"})
ANSWER_TTL = 30
BUILTIN_RESOLVER_NAME = "dnsresolver"

# One or more labels of letters, digits, and hyphens, joined by dots. Exact names only.
_LABEL = r"[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?"
_NAME_RE = re.compile(rf"^{_LABEL}(?:\.{_LABEL})*$")

# Question types and response codes as integers, so the classification logic
# works without mitmproxy imported.
TYPE_A = 1
TYPE_AAAA = 28
RCODE_NOERROR = 0
RCODE_FORMERR = 1
RCODE_NXDOMAIN = 3
RCODE_NOTIMP = 4
OPCODE_QUERY = 0
CLASS_IN = 1


class DnsAllowlistError(ValueError):
    """Raised when AGENTBOX_DNS_ALLOW contains a name the sinkhole will not serve."""


def normalize_name(name):
    """Lowercase a DNS name and drop the trailing dot."""
    return name.rstrip(".").lower()


def parse_allowed_names(value, default=DEFAULT_ALLOWED_NAMES):
    """Parse AGENTBOX_DNS_ALLOW into a frozenset that always includes the defaults."""
    names = set(default)
    if value is None:
        return frozenset(names)
    for raw in value.split(","):
        name = normalize_name(raw.strip())
        if not name:
            continue
        if not _NAME_RE.match(name):
            raise DnsAllowlistError(
                f"{ALLOW_ENV} entry {raw.strip()!r} is not an exact host name; "
                "wildcards and other patterns are not supported"
            )
        names.add(name)
    return frozenset(names)


def classify(op_code, questions, allowed_names):
    """Decide what to do with a query.

    Returns a tuple (action, rcode, name, qtype) where action is one of
    "refused", "nxdomain", "nodata", or "resolve". The caller builds the
    response; this function is pure so it can be unit tested without mitmproxy.
    """
    if op_code != OPCODE_QUERY:
        return ("refused", RCODE_NOTIMP, None, None)
    if len(questions) != 1:
        return ("refused", RCODE_FORMERR, None, None)
    question = questions[0]
    if question.class_ != CLASS_IN:
        return ("refused", RCODE_NOTIMP, normalize_name(question.name), question.type)
    name = normalize_name(question.name)
    if name not in allowed_names:
        return ("nxdomain", RCODE_NXDOMAIN, name, question.type)
    if question.type not in (TYPE_A, TYPE_AAAA):
        return ("nodata", RCODE_NOERROR, name, question.type)
    return ("resolve", RCODE_NOERROR, name, question.type)


class _StdoutJsonLogger:
    """Minimal stand-in for the enforcer's JsonLogger when the addon runs alone."""

    def __init__(self, log_level="normal", stream=None):
        self.log_level = log_level
        self.stream = stream if stream is not None else sys.stdout

    def timestamp(self):
        return datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S")

    def info(self, message):
        self._emit({"ts": self.timestamp(), "type": "info", "msg": message})

    def event(self, entry, always=False):
        if self.log_level == "quiet" and not always:
            return
        self._emit(entry)

    def _emit(self, entry):
        print(json.dumps(entry), file=self.stream, flush=True)


async def getaddrinfo_resolver(name, qtype):
    """Resolve an allowed name through this container's resolver. Returns IP strings."""
    family = socket.AF_INET if qtype == TYPE_A else socket.AF_INET6
    loop = asyncio.get_running_loop()
    try:
        infos = await loop.getaddrinfo(name, None, family=family, type=socket.SOCK_STREAM)
    except socket.gaierror:
        return []
    addresses = []
    for info in infos:
        address = info[4][0]
        if address not in addresses:
            addresses.append(address)
    return addresses


class DnsSinkhole:
    def __init__(
        self,
        allowed_names=None,
        logger=None,
        log_level=None,
        resolver=None,
        ttl=ANSWER_TTL,
    ):
        self.log_level = log_level or os.getenv("PROXY_LOG_LEVEL", "normal")
        self.logger = logger or _StdoutJsonLogger(log_level=self.log_level)
        if allowed_names is None:
            allowed_names = parse_allowed_names(os.getenv(ALLOW_ENV))
        self.allowed_names = frozenset(normalize_name(name) for name in allowed_names)
        self.resolver = resolver or getaddrinfo_resolver
        self.ttl = ttl

    # --- mitmproxy hooks -------------------------------------------------

    def load(self, loader):
        removed = self.remove_builtin_resolver()
        self.logger.event(
            {
                "ts": self.logger.timestamp(),
                "type": "dns",
                "action": "listening",
                "allowed": sorted(self.allowed_names),
                "builtin_resolver_removed": removed,
            },
            always=True,
        )

    async def dns_request(self, flow):
        request = flow.request
        action, rcode, name, qtype = classify(
            request.op_code, list(request.questions), self.allowed_names
        )
        client = self._client_address(flow)
        if action == "refused":
            flow.response = request.fail(rcode)
            self._log("refused", name, qtype, client, rcode=rcode)
            return
        if action == "nxdomain":
            flow.response = request.fail(rcode)
            self._log("nxdomain", name, qtype, client)
            return
        if action == "nodata":
            flow.response = request.succeed([])
            return
        addresses = await self.resolver(name, qtype)
        records = self._records(request.questions[0].name, qtype, addresses)
        flow.response = request.succeed(records)

    # --- helpers ---------------------------------------------------------

    def remove_builtin_resolver(self):
        """Take the built-in DnsResolver out of the addon chain. Returns True when removed."""
        master = getattr(ctx, "master", None) if ctx is not None else None
        if master is None:
            return False
        builtin = master.addons.get(BUILTIN_RESOLVER_NAME)
        if builtin is None:
            return False
        master.addons.remove(builtin)
        return True

    def _records(self, question_name, qtype, addresses):
        records = []
        for address in addresses:
            ip = ipaddress.ip_address(address)
            if qtype == TYPE_A and ip.version == 4:
                records.append(dns.ResourceRecord.A(question_name, ip, ttl=self.ttl))
            elif qtype == TYPE_AAAA and ip.version == 6:
                records.append(dns.ResourceRecord.AAAA(question_name, ip, ttl=self.ttl))
        return records

    @staticmethod
    def _client_address(flow):
        peername = getattr(getattr(flow, "client_conn", None), "peername", None)
        if not peername:
            return None
        return peername[0]

    def _log(self, action, name, qtype, client, rcode=None):
        entry = {
            "ts": self.logger.timestamp(),
            "type": "dns",
            "action": action,
            "name": name,
            "qtype": _type_name(qtype),
            "client": client,
        }
        if rcode is not None:
            entry["rcode"] = rcode
        self.logger.event(entry)


def _type_name(qtype):
    if qtype is None:
        return None
    if types is not None:
        try:
            return types.to_str(qtype)
        except Exception:  # pragma: no cover - unknown type numbers
            pass
    return str(qtype)

