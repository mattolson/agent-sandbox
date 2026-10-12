"""Unit tests for the proxy address guard (images/proxy/addons/address_guard.py).

The tests named `test_invariant_*` pin down facts about Python and asyncio that
the guard's pinning depends on. If one fails after a Python or mitmproxy bump,
the pin no longer holds; do not relax the test, revisit the design in
docs/plan/milestones/m18-dns-egress-controls/tasks/m18.4-proxy-address-guard/.
"""

import asyncio
import io
import ipaddress
import json
import socket
import sys
import tempfile
import unittest
from contextlib import redirect_stdout
from pathlib import Path

from test_enforcer import FakeFlow, FakeResponse, load_enforcer_module


REPO_ROOT = Path(__file__).resolve().parents[3]
ADDON_DIR = REPO_ROOT / "images" / "proxy" / "addons"
if str(ADDON_DIR) not in sys.path:
    sys.path.insert(0, str(ADDON_DIR))

import address_guard  # noqa: E402
from address_guard import (  # noqa: E402
    REFUSAL_MARKER,
    AddressGuard,
    AddressRefused,
    PinningUnavailable,
    classify_address,
    is_dial_lookup,
    read_sandbox_networks,
)


def info(address, port=443):
    """One getaddrinfo tuple for an address string."""
    family = socket.AF_INET6 if ":" in address else socket.AF_INET
    sockaddr = (address, port, 0, 0) if family == socket.AF_INET6 else (address, port)
    return (family, socket.SOCK_STREAM, 6, "", sockaddr)


class RecordingLogger:
    def __init__(self):
        self.events = []

    def timestamp(self):
        return "2026-09-27 00:00:00"

    def event(self, entry, always=False):
        self.events.append(entry)


class FakeServer:
    def __init__(self, host, port):
        self.address = (host, port)
        self.error = None


class FakeHookData:
    def __init__(self, host, port=443):
        self.server = FakeServer(host, port)


def fake_resolver(table):
    """A resolver over a {host: [address, ...]} table; unknown hosts raise like getaddrinfo."""
    calls = []

    async def resolve(host, port):
        calls.append((host, port))
        if host not in table:
            raise socket.gaierror(socket.EAI_NONAME, "Name or service not known")
        return [info(address, port) for address in table[host]]

    resolve.calls = calls
    return resolve


def run(coroutine):
    return asyncio.run(coroutine)


class ClassifyAddressTests(unittest.TestCase):
    def assertClass(self, address, expected, sandbox_networks=()):
        self.assertEqual(
            classify_address(address, sandbox_networks),
            expected,
            f"{address} classified wrongly",
        )

    def test_public_addresses_pass(self):
        for address in ("8.8.8.8", "1.1.1.1", "140.82.112.3", "2606:4700:4700::1111", "2001:4860:4860::8888"):
            self.assertClass(address, None)

    def test_each_denied_range_at_both_ends(self):
        cases = {
            "loopback": ("127.0.0.0/8", "::1/128"),
            "private": ("10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16"),
            "unique_local": ("fc00::/7",),
            "link_local": ("169.254.0.0/16", "fe80::/10"),
            "shared": ("100.64.0.0/10",),
            "unspecified": ("0.0.0.0/8", "::/128"),
            "multicast": ("224.0.0.0/4", "ff00::/8"),
        }
        for expected, networks in cases.items():
            for text in networks:
                network = ipaddress.ip_network(text)
                for address in (network[0], network[-1]):
                    if expected == "link_local" and str(address) == "169.254.169.254":
                        continue
                    with self.subTest(network=text, address=str(address)):
                        self.assertClass(str(address), expected)

    def test_neighbours_of_private_ranges_are_public(self):
        for address in ("9.255.255.255", "11.0.0.0", "172.15.255.255", "172.32.0.0", "192.167.255.255", "192.169.0.0"):
            self.assertClass(address, None)

    def test_metadata_is_named_before_link_local_and_unique_local(self):
        self.assertClass("169.254.169.254", "metadata")
        self.assertClass("fd00:ec2::254", "metadata")

    def test_other_non_global_addresses_are_reserved(self):
        for address in ("240.0.0.1", "192.0.2.1", "198.51.100.7", "203.0.113.9", "198.18.0.1", "255.255.255.255"):
            self.assertClass(address, "reserved")

    def test_ipv4_mapped_ipv6_is_classified_by_its_ipv4_address(self):
        self.assertClass("::ffff:10.0.0.1", "private")
        self.assertClass("::ffff:169.254.169.254", "metadata")
        self.assertClass("::ffff:8.8.8.8", None)

    def test_zone_suffix_is_ignored(self):
        self.assertClass("fe80::1%eth0", "link_local")

    def test_sandbox_network_is_named_before_private(self):
        sandbox = [ipaddress.ip_network("172.22.0.0/16"), ipaddress.ip_network("fd9f:73ac:d109::/64")]
        self.assertClass("172.22.0.2", "sandbox_network", sandbox)
        self.assertClass("fd9f:73ac:d109::2", "sandbox_network", sandbox)
        self.assertClass("172.23.0.2", "private", sandbox)

    def test_sandbox_network_outside_private_space_is_denied(self):
        # A daemon configured with an address pool outside RFC 1918.
        sandbox = [ipaddress.ip_network("44.1.0.0/16")]
        self.assertClass("44.1.2.3", "sandbox_network", sandbox)
        self.assertClass("44.2.0.1", None, sandbox)

    def test_garbage_is_unparseable(self):
        self.assertClass("not-an-address", "unparseable")


class ReadSandboxNetworksTests(unittest.TestCase):
    ROUTE = (
        "Iface\tDestination\tGateway \tFlags\tRefCnt\tUse\tMetric\tMask\t\tMTU\tWindow\tIRTT\n"
        "eth0\t00000000\t010016AC\t0003\t0\t0\t0\t00000000\t0\t0\t0\n"
        "eth0\t000016AC\t00000000\t0001\t0\t0\t0\t0000FFFF\t0\t0\t0\n"
        "lo\t0000007F\t00000000\t0001\t0\t0\t0\t000000FF\t0\t0\t0\n"
    )
    IPV6_ROUTE = (
        "fd9f73acd10900000000000000000000 40 00000000000000000000000000000000 00 "
        "00000000000000000000000000000000 00000100 00000001 00000000 00000001 eth0\n"
        "fe800000000000000000000000000000 40 00000000000000000000000000000000 00 "
        "00000000000000000000000000000000 00000100 00000001 00000000 00000001 eth0\n"
        "00000000000000000000000000000000 00 00000000000000000000000000000000 00 "
        "fd9f73acd10900000000000000000001 00000400 00000001 00000000 00000003 eth0\n"
        "00000000000000000000000000000001 80 00000000000000000000000000000000 00 "
        "00000000000000000000000000000000 00000000 00000001 00000000 00000001 lo\n"
    )

    def proc_root(self, route=None, ipv6_route=None):
        tempdir = tempfile.TemporaryDirectory()
        self.addCleanup(tempdir.cleanup)
        net = Path(tempdir.name, "net")
        net.mkdir()
        if route is not None:
            (net / "route").write_text(route)
        if ipv6_route is not None:
            (net / "ipv6_route").write_text(ipv6_route)
        return tempdir.name

    def test_reads_attached_networks_and_skips_default_loopback_and_link_local(self):
        networks = read_sandbox_networks(self.proc_root(self.ROUTE, self.IPV6_ROUTE))
        self.assertEqual(
            networks,
            [ipaddress.ip_network("172.22.0.0/16"), ipaddress.ip_network("fd9f:73ac:d109::/64")],
        )

    def test_missing_tables_yield_nothing(self):
        self.assertEqual(read_sandbox_networks(self.proc_root()), [])


class CheckTests(unittest.TestCase):
    def test_any_denied_answer_refuses_the_host(self):
        guard = AddressGuard(mode="enforce", logger=RecordingLogger(), sandbox_networks=[])
        refusal = guard.check("mixed.example", 443, [info("140.82.112.3"), info("10.0.0.5")])
        self.assertEqual(refusal.address, "10.0.0.5")
        self.assertEqual(refusal.address_class, "private")
        self.assertEqual(refusal.answers, ("140.82.112.3", "10.0.0.5"))
        self.assertTrue(refusal.message().startswith(REFUSAL_MARKER))
        self.assertIn("mixed.example resolves to 10.0.0.5 (private)", refusal.message())

    def test_all_public_answers_pass(self):
        guard = AddressGuard(mode="enforce", logger=RecordingLogger(), sandbox_networks=[])
        self.assertIsNone(guard.check("api.github.com", 443, [info("140.82.112.3"), info("2606:50c0::1")]))


def make_guard(table=None, mode="enforce", classifier=None):
    logger = RecordingLogger()
    guard = AddressGuard(
        mode=mode,
        logger=logger,
        resolver=fake_resolver(table) if table is not None else None,
        sandbox_networks=[],
        classifier=classifier,
    )
    return guard, logger


async def dial_lookup(guard, host, port=443, real=None):
    """Install the wrapper on the running loop and make the lookup asyncio makes for a dial."""
    loop = asyncio.get_running_loop()
    if real is not None:
        loop.getaddrinfo = real
    guard.install_pinning(loop)
    return await loop.getaddrinfo(host, port, family=0, type=socket.SOCK_STREAM, proto=0, flags=0)


class DialLookupTests(unittest.TestCase):
    def test_denied_answer_raises_before_any_connection(self):
        guard, logger = make_guard({"rebound.example": ["169.254.169.254"]})
        with self.assertRaises(AddressRefused) as raised:
            run(dial_lookup(guard, "rebound.example"))
        self.assertIsInstance(raised.exception, OSError, "mitmproxy must see a failed connection")
        self.assertTrue(str(raised.exception).startswith(REFUSAL_MARKER))
        self.assertIn("rebound.example resolves to 169.254.169.254 (metadata)", str(raised.exception))
        self.assertEqual(
            logger.events[-1],
            {
                "ts": "2026-09-27 00:00:00",
                "type": "address_guard",
                "action": "blocked",
                "phase": "connect",
                "host": "rebound.example",
                "port": 443,
                "address": "169.254.169.254",
                "address_class": "metadata",
                "answers": ["169.254.169.254"],
            },
        )

    def test_allowed_answers_are_returned_for_the_dial(self):
        guard, logger = make_guard({"api.github.com": ["140.82.112.3", "140.82.112.4"]})
        answers = run(dial_lookup(guard, "api.github.com"))
        self.assertEqual([a[4][0] for a in answers], ["140.82.112.3", "140.82.112.4"])
        self.assertEqual(logger.events, [])

    def test_mixed_answer_is_refused(self):
        guard, _ = make_guard({"mixed.example": ["140.82.112.3", "10.0.0.5"]})
        with self.assertRaises(AddressRefused):
            run(dial_lookup(guard, "mixed.example"))

    def test_the_dial_lookup_itself_is_checked_so_nothing_can_slip_past_it(self):
        # The #204 review found staged answers could fail or expire and leave the dial
        # an unchecked fallback. There is no fallback now: whatever the real resolver
        # answers for the dial is what gets checked.
        guard, _ = make_guard()

        async def answers_private(host, port, *args, **kwargs):
            return [info("10.0.0.7", port)]

        with self.assertRaises(AddressRefused):
            run(dial_lookup(guard, "flaky.example", real=answers_private))

    def test_lookup_failure_propagates_unchanged(self):
        guard, logger = make_guard({})
        with self.assertRaises(socket.gaierror):
            run(dial_lookup(guard, "nx.invalid"))
        self.assertEqual(logger.events, [])

    def test_log_mode_records_but_returns_the_answers(self):
        guard, logger = make_guard({"rebound.example": ["10.0.0.1"]}, mode="log")
        answers = run(dial_lookup(guard, "rebound.example"))
        self.assertEqual(answers[0][4][0], "10.0.0.1")
        self.assertEqual(logger.events[-1]["action"], "logged")

    def test_family_filter_applies_to_injected_answers(self):
        guard, _ = make_guard({"dual.example": ["140.82.112.3", "2606:50c0::1"]})

        async def scenario():
            guard.install_pinning(asyncio.get_running_loop())
            return await asyncio.get_running_loop().getaddrinfo("dual.example", 443, family=socket.AF_INET6)

        self.assertEqual([a[4][0] for a in run(scenario())], ["2606:50c0::1"])

    def test_lookups_that_are_not_dials_pass_through_unchecked(self):
        # The sinkhole resolves allowed names with no port, and a server binding every
        # interface resolves (None, port) with AI_PASSIVE. Both answer denied addresses.
        guard, logger = make_guard()
        calls = []

        async def real(host, port, *args, **kwargs):
            calls.append((host, port))
            return [info("172.22.0.2", port or 0)]

        async def scenario():
            loop = asyncio.get_running_loop()
            loop.getaddrinfo = real
            guard.install_pinning(loop)
            await loop.getaddrinfo("proxy", None, family=socket.AF_INET, type=socket.SOCK_STREAM)
            await loop.getaddrinfo(None, 8080, family=0, type=socket.SOCK_STREAM, flags=socket.AI_PASSIVE)
            await loop.getaddrinfo("", 8080, family=0, type=socket.SOCK_STREAM)
            await loop.getaddrinfo("proxy", 8080, family=0, type=socket.SOCK_STREAM, flags=socket.AI_PASSIVE)

        run(scenario())
        self.assertEqual(len(calls), 4)
        self.assertEqual(logger.events, [])

    def test_is_dial_lookup(self):
        self.assertTrue(is_dial_lookup("api.github.com", 443, {"flags": 0}))
        self.assertFalse(is_dial_lookup("proxy", None, {}))
        self.assertFalse(is_dial_lookup(None, 8080, {"flags": socket.AI_PASSIVE}))
        self.assertFalse(is_dial_lookup("", 8080, {}))
        self.assertFalse(is_dial_lookup("proxy", 8080, {"flags": socket.AI_PASSIVE}))
        self.assertFalse(is_dial_lookup("10.0.0.1", 443, {}))


class ServerConnectTests(unittest.TestCase):
    def test_installs_the_wrapper_before_a_dial(self):
        guard, _ = make_guard()
        data = FakeHookData("api.github.com")

        async def scenario():
            guard.server_connect(data)
            return asyncio.get_running_loop().getaddrinfo == guard._checked_getaddrinfo

        self.assertTrue(run(scenario()))
        self.assertIsNone(data.server.error)

    def test_unpinnable_loop_refuses_names_in_enforce_mode(self):
        guard, _ = make_guard()

        def refuse(loop):
            raise PinningUnavailable("no")

        guard.install_pinning = refuse
        data = FakeHookData("api.github.com")

        async def scenario():
            guard.server_connect(data)

        run(scenario())
        self.assertTrue(data.server.error.startswith(REFUSAL_MARKER))
        self.assertIn("pinning unavailable", data.server.error)

    def test_ip_literals_and_killed_connections_are_left_alone(self):
        guard, _ = make_guard()
        guard.install_pinning = lambda loop: self.fail("must not be called")
        literal = FakeHookData("10.0.0.1")
        killed = FakeHookData("api.github.com")
        killed.server.error = "killed by someone else"

        async def scenario():
            guard.server_connect(literal)
            guard.server_connect(killed)

        run(scenario())
        self.assertIsNone(literal.server.error)
        self.assertEqual(killed.server.error, "killed by someone else")


class InvariantTests(unittest.TestCase):
    def test_invariant_asyncio_open_connection_resolves_through_loop_getaddrinfo(self):
        """The guard works only if asyncio's dial resolves through the loop's getaddrinfo.

        `pinned.invalid` cannot resolve anywhere (RFC 2606), so this connection
        succeeds only if asyncio used the answer the wrapper returned.
        """
        guard, _ = make_guard({"pinned.invalid": ["127.0.0.1"]}, classifier=lambda address, networks: None)

        async def scenario():
            accepted = asyncio.Event()

            async def on_connect(reader, writer):
                accepted.set()
                writer.close()

            server = await asyncio.start_server(on_connect, "127.0.0.1", 0)
            port = server.sockets[0].getsockname()[1]
            guard.install_pinning(asyncio.get_running_loop())
            reader, writer = await asyncio.open_connection("pinned.invalid", port)
            peer = writer.get_extra_info("peername")
            await asyncio.wait_for(accepted.wait(), 2)
            writer.close()
            server.close()
            return peer

        try:
            peer = run(scenario())
        except OSError as error:
            self.fail(
                "asyncio.open_connection no longer resolves through loop.getaddrinfo, "
                f"so the address guard cannot check dials: {error}"
            )
        self.assertEqual(peer[0], "127.0.0.1")

    def test_invariant_a_refused_dial_opens_no_connection(self):
        guard, _ = make_guard({"refused.invalid": ["127.0.0.1"]})

        async def scenario():
            accepted = []

            async def on_connect(reader, writer):
                accepted.append(1)
                writer.close()

            server = await asyncio.start_server(on_connect, "127.0.0.1", 0)
            port = server.sockets[0].getsockname()[1]
            guard.install_pinning(asyncio.get_running_loop())
            refused = None
            try:
                await asyncio.open_connection("refused.invalid", port)
            except AddressRefused as error:
                refused = error
            await asyncio.sleep(0.1)
            server.close()
            return refused, len(accepted)

        refused, accepted = run(scenario())
        self.assertIsNotNone(refused, "the dial to a denied address must be refused")
        self.assertEqual(accepted, 0, "a refused dial must not open a connection")

    def test_invariant_binding_every_interface_is_not_checked(self):
        """A bind to every interface must pass through the wrapper unchecked.

        asyncio resolves it as a lookup with no host and AI_PASSIVE, and the
        wrapper passes it on either count, so both would have to change before
        the check refused 0.0.0.0. mitmdump binds at startup, before the wrapper
        is installed, but would rebind through it after an options change.
        """
        guard, _ = make_guard()

        async def scenario():
            guard.install_pinning(asyncio.get_running_loop())
            server = await asyncio.start_server(lambda r, w: w.close(), host="", port=0)
            ports = {sock.getsockname()[1] for sock in server.sockets}
            server.close()
            return ports

        try:
            ports = run(scenario())
        except AddressRefused as error:
            self.fail(f"binding every interface went through the dial check: {error}")
        self.assertTrue(ports)

    def test_invariant_default_event_loop_accepts_the_wrapper(self):
        """A loop class that forbids instance attributes would leave dials unchecked."""
        guard, _ = make_guard()

        async def scenario():
            loop = asyncio.get_running_loop()
            guard.install_pinning(loop)
            return loop.getaddrinfo == guard._checked_getaddrinfo

        self.assertTrue(run(scenario()))

    def test_install_raises_when_the_loop_refuses_the_wrapper(self):
        guard, _ = make_guard()

        class SlottedLoop:
            __slots__ = ()

            def getaddrinfo(self, *args, **kwargs):  # pragma: no cover - never called
                raise AssertionError

        with self.assertRaises(PinningUnavailable):
            guard.install_pinning(SlottedLoop())


class RequestPreCheckTests(unittest.TestCase):
    def make_guard(self, table, mode="enforce"):
        refused = []
        logger = RecordingLogger()
        guard = AddressGuard(
            mode=mode,
            logger=logger,
            resolver=fake_resolver(table),
            sandbox_networks=[],
            on_refused=lambda flow, refusal: refused.append((flow, refusal)),
        )
        return guard, logger, refused

    def flow(self, host, scheme="http", port=80):
        flow = FakeFlow(host, scheme=scheme)
        flow.request.port = port
        return flow

    def test_plain_http_to_a_denied_name_is_refused_before_the_connection(self):
        guard, logger, refused = self.make_guard({"localhost": ["127.0.0.1"]})
        flow = self.flow("localhost")
        run(guard.requestheaders(flow))
        self.assertEqual(len(refused), 1)
        self.assertEqual(refused[0][1].address_class, "loopback")
        self.assertEqual(logger.events[-1]["phase"], "request")

    def test_https_is_left_to_the_connection_check(self):
        guard, _, refused = self.make_guard({"localhost": ["127.0.0.1"]})
        run(guard.requestheaders(self.flow("localhost", scheme="https", port=443)))
        self.assertEqual(refused, [])
        self.assertEqual(guard.resolver.calls, [])

    def test_request_the_policy_already_blocked_is_left_alone(self):
        guard, _, refused = self.make_guard({"localhost": ["127.0.0.1"]})
        flow = self.flow("localhost")
        flow.response = FakeResponse(403, "Blocked by proxy policy: localhost")
        run(guard.requestheaders(flow))
        self.assertEqual(refused, [])

    def test_literals_and_public_names_pass(self):
        guard, _, refused = self.make_guard({"example.com": ["93.184.215.14"]})
        run(guard.requestheaders(self.flow("127.0.0.1")))
        run(guard.requestheaders(self.flow("example.com")))
        self.assertEqual(refused, [])

    def test_log_mode_does_not_pre_check(self):
        guard, _, refused = self.make_guard({"localhost": ["127.0.0.1"]}, mode="log")
        run(guard.requestheaders(self.flow("localhost")))
        self.assertEqual(refused, [])


class EnforcerIntegrationTests(unittest.TestCase):
    """The enforcer's side: refusals become 403 with a stored blocked decision."""

    @classmethod
    def setUpClass(cls):
        cls.module = load_enforcer_module()

    def make_enforcer(self):
        stream = io.StringIO()
        enforcer = self.module.PolicyEnforcer(
            mode="enforce",
            matcher=self.module.PolicyMatcher.from_policy_data({"domains": ["localhost", "api.github.com"]}),
            logger=self.module.JsonLogger(stream=stream),
            response_factory=FakeResponse,
        )
        return enforcer, stream

    def connect_flow(self, error):
        flow = FakeFlow("rebound.example", scheme="http", method="CONNECT")
        flow.response = FakeResponse(502, "Cannot connect")
        flow.server_conn = FakeServer("rebound.example", 443)
        flow.server_conn.error = error
        return flow

    def test_connect_refused_by_the_guard_gets_403_with_the_reason(self):
        enforcer, _ = self.make_enforcer()
        message = f"{REFUSAL_MARKER} rebound.example resolves to 10.0.0.1 (private); refused"
        flow = self.connect_flow(message)
        enforcer.http_connect_error(flow)
        self.assertEqual(flow.response.status_code, 403)
        self.assertEqual(flow.response.body, message)
        stored = flow.metadata[self.module.FLOW_DECISION_METADATA_KEY]
        self.assertEqual((stored["action"], stored["reason"], stored["phase"]), ("blocked", "address_guard", "connect"))

    def test_other_connect_failures_keep_mitmproxys_502(self):
        enforcer, _ = self.make_enforcer()
        flow = self.connect_flow("[Errno 111] Connection refused")
        enforcer.http_connect_error(flow)
        self.assertEqual(flow.response.status_code, 502)
        self.assertEqual(flow.metadata, {})

    def test_request_refusal_gets_403_and_suppresses_the_allowed_log_line(self):
        enforcer, stream = self.make_enforcer()
        flow = FakeFlow("localhost", scheme="http")
        enforcer.requestheaders(flow)
        refusal = address_guard.Refusal("localhost", 80, "127.0.0.1", "loopback", ("127.0.0.1",))
        enforcer.address_guard_refused(flow, refusal)
        self.assertEqual(flow.response.status_code, 403)
        self.assertEqual(flow.response.body, refusal.message())
        before = stream.getvalue()
        enforcer.response(flow)
        self.assertEqual(stream.getvalue(), before, "a guard refusal must not be logged as allowed")

    def test_build_addons_orders_the_guard_after_the_enforcer(self):
        with redirect_stdout(io.StringIO()):
            addons = self.module.build_addons()
        names = [type(addon).__name__ for addon in addons]
        if not names:
            self.skipTest("mitmproxy not importable")
        self.assertLess(names.index("PolicyEnforcer"), names.index("AddressGuard"))


if __name__ == "__main__":
    unittest.main()
