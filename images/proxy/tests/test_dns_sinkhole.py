import asyncio
import importlib.util
import io
import ipaddress
import os
import sys
import unittest
from importlib.machinery import SourceFileLoader
from pathlib import Path
from types import SimpleNamespace
from unittest import mock

try:
    from mitmproxy import dns
except ImportError:  # pragma: no cover - CI installs mitmproxy; local minimal envs skip.
    dns = None


REPO_ROOT = Path(__file__).resolve().parents[3]
ADDON_PATH = REPO_ROOT / "images" / "proxy" / "addons" / "dns_sinkhole.py"


def load_module():
    loader = SourceFileLoader("dns_sinkhole_module", str(ADDON_PATH))
    spec = importlib.util.spec_from_loader(loader.name, loader)
    module = importlib.util.module_from_spec(spec)
    sys.modules[loader.name] = module
    loader.exec_module(module)
    return module


class RecordingLogger:
    def __init__(self):
        self.events = []
        self.infos = []

    def timestamp(self):
        return "2026-09-12 00:00:00"

    def info(self, message):
        self.infos.append(message)

    def event(self, entry, always=False):
        self.events.append((entry, always))


class FakeFlow:
    def __init__(self, request, client="172.22.0.3"):
        self.request = request
        self.response = None
        self.client_conn = SimpleNamespace(peername=(client, 40000))


def make_query(name="proxy.", qtype=1, class_=1, op_code=0, questions=None):
    if questions is None:
        questions = [dns.Question(name, qtype, class_)]
    return dns.Message(
        timestamp=0.0,
        id=42,
        query=True,
        op_code=op_code,
        authoritative_answer=False,
        truncation=False,
        recursion_desired=True,
        recursion_available=False,
        reserved=0,
        response_code=0,
        questions=questions,
        answers=[],
        authorities=[],
        additionals=[],
    )


class FakeResolver:
    def __init__(self, table):
        self.table = table
        self.calls = []

    async def __call__(self, name, qtype):
        self.calls.append((name, qtype))
        return list(self.table.get((name, qtype), []))


def run(coro):
    return asyncio.run(coro)


class AllowlistParsingTests(unittest.TestCase):
    def setUp(self):
        self.module = load_module()

    def test_default_is_proxy_only(self):
        self.assertEqual(self.module.parse_allowed_names(None), frozenset({"proxy"}))
        self.assertEqual(self.module.parse_allowed_names(""), frozenset({"proxy"}))

    def test_extends_default_and_normalizes(self):
        names = self.module.parse_allowed_names(" db , Cache. ,,redis-1")
        self.assertEqual(names, frozenset({"proxy", "db", "cache", "redis-1"}))

    def test_rejects_patterns(self):
        for bad in ("*.example", "db:53", "http://db", "a b", "-lead", "under_score"):
            with self.subTest(bad=bad):
                with self.assertRaises(self.module.DnsAllowlistError):
                    self.module.parse_allowed_names(bad)

    def test_constructor_reads_environment(self):
        with mock.patch.dict(os.environ, {"AGENTBOX_DNS_ALLOW": "db"}, clear=False):
            sinkhole = self.module.DnsSinkhole(logger=RecordingLogger())
        self.assertEqual(sinkhole.allowed_names, frozenset({"proxy", "db"}))


class ClassifyTests(unittest.TestCase):
    """The pure decision function, exercised without mitmproxy objects."""

    def setUp(self):
        self.module = load_module()
        self.allowed = frozenset({"proxy"})

    def question(self, name, qtype=1, class_=1):
        return SimpleNamespace(name=name, type=qtype, class_=class_)

    def test_non_query_opcode_is_refused_notimp(self):
        action, rcode, _, _ = self.module.classify(2, [self.question("proxy.")], self.allowed)
        self.assertEqual((action, rcode), ("refused", self.module.RCODE_NOTIMP))

    def test_question_count_other_than_one_is_formerr(self):
        action, rcode, _, _ = self.module.classify(0, [], self.allowed)
        self.assertEqual((action, rcode), ("refused", self.module.RCODE_FORMERR))
        two = [self.question("proxy."), self.question("proxy.")]
        action, rcode, _, _ = self.module.classify(0, two, self.allowed)
        self.assertEqual((action, rcode), ("refused", self.module.RCODE_FORMERR))

    def test_non_internet_class_is_refused(self):
        action, rcode, name, _ = self.module.classify(0, [self.question("proxy.", 1, 3)], self.allowed)
        self.assertEqual((action, rcode, name), ("refused", self.module.RCODE_NOTIMP, "proxy"))

    def test_unknown_name_is_nxdomain(self):
        action, rcode, name, qtype = self.module.classify(0, [self.question("example.com.", 16)], self.allowed)
        self.assertEqual((action, rcode, name, qtype), ("nxdomain", self.module.RCODE_NXDOMAIN, "example.com", 16))

    def test_allowed_name_is_case_and_dot_insensitive(self):
        action, _, name, _ = self.module.classify(0, [self.question("PROXY.")], self.allowed)
        self.assertEqual((action, name), ("resolve", "proxy"))

    def test_allowed_name_with_other_type_is_nodata(self):
        action, rcode, _, _ = self.module.classify(0, [self.question("proxy.", 16)], self.allowed)
        self.assertEqual((action, rcode), ("nodata", self.module.RCODE_NOERROR))

    def test_allowed_name_with_aaaa_resolves(self):
        action, _, _, qtype = self.module.classify(0, [self.question("proxy.", 28)], self.allowed)
        self.assertEqual((action, qtype), ("resolve", 28))


@unittest.skipIf(dns is None, "mitmproxy not importable")
class DnsRequestTests(unittest.TestCase):
    def setUp(self):
        self.module = load_module()
        self.logger = RecordingLogger()
        self.resolver = FakeResolver({
            ("proxy", 1): ["172.22.0.2"],
            ("proxy", 28): [],
            ("db", 1): ["172.22.0.9", "172.22.0.9"],
        })
        self.sinkhole = self.module.DnsSinkhole(
            allowed_names={"proxy", "db"},
            logger=self.logger,
            resolver=self.resolver,
            ttl=30,
        )

    def test_allowed_a_query_is_answered_with_ttl(self):
        flow = FakeFlow(make_query("Proxy.", 1))
        run(self.sinkhole.dns_request(flow))
        response = flow.response
        self.assertEqual(response.response_code, 0)
        self.assertEqual(response.id, 42)
        self.assertEqual(len(response.answers), 1)
        record = response.answers[0]
        self.assertEqual(record.type, 1)
        self.assertEqual(record.ttl, 30)
        self.assertEqual(record.data, ipaddress.IPv4Address("172.22.0.2").packed)
        self.assertEqual(self.resolver.calls, [("proxy", 1)])
        self.assertEqual(self.logger.events, [])

    def test_duplicate_addresses_are_deduplicated_by_resolver_contract(self):
        flow = FakeFlow(make_query("db.", 1))
        run(self.sinkhole.dns_request(flow))
        # The fake returns a duplicate on purpose; the addon answers what the resolver gives it,
        # and the real resolver deduplicates. Two records with the same data is still a valid answer.
        self.assertEqual(flow.response.response_code, 0)
        self.assertEqual(len(flow.response.answers), 2)

    def test_allowed_aaaa_without_address_is_empty_noerror(self):
        flow = FakeFlow(make_query("proxy.", 28))
        run(self.sinkhole.dns_request(flow))
        self.assertEqual(flow.response.response_code, 0)
        self.assertEqual(flow.response.answers, [])

    def test_allowed_txt_is_empty_noerror_without_resolving(self):
        flow = FakeFlow(make_query("proxy.", 16))
        run(self.sinkhole.dns_request(flow))
        self.assertEqual(flow.response.response_code, 0)
        self.assertEqual(flow.response.answers, [])
        self.assertEqual(self.resolver.calls, [])

    def test_unknown_name_is_nxdomain_logged_and_never_resolved(self):
        flow = FakeFlow(make_query("secret-data.example.com.", 1), client="172.22.0.3")
        run(self.sinkhole.dns_request(flow))
        self.assertEqual(flow.response.response_code, 3)
        self.assertEqual(flow.response.answers, [])
        self.assertEqual(self.resolver.calls, [])
        self.assertEqual(len(self.logger.events), 1)
        entry, always = self.logger.events[0]
        self.assertFalse(always)
        self.assertEqual(entry["type"], "dns")
        self.assertEqual(entry["action"], "nxdomain")
        self.assertEqual(entry["name"], "secret-data.example.com")
        self.assertEqual(entry["qtype"], "A")
        self.assertEqual(entry["client"], "172.22.0.3")

    def test_non_query_opcode_is_refused_with_notimp(self):
        flow = FakeFlow(make_query("proxy.", 1, op_code=2))
        run(self.sinkhole.dns_request(flow))
        self.assertEqual(flow.response.response_code, 4)
        entry, _ = self.logger.events[0]
        self.assertEqual(entry["action"], "refused")
        self.assertEqual(entry["rcode"], 4)

    def test_two_questions_is_formerr(self):
        flow = FakeFlow(make_query(questions=[dns.Question("proxy.", 1, 1), dns.Question("db.", 1, 1)]))
        run(self.sinkhole.dns_request(flow))
        self.assertEqual(flow.response.response_code, 1)

    def test_chaos_class_is_refused(self):
        flow = FakeFlow(make_query("proxy.", 16, class_=3))
        run(self.sinkhole.dns_request(flow))
        self.assertEqual(flow.response.response_code, 4)
        self.assertEqual(self.resolver.calls, [])


class LifecycleTests(unittest.TestCase):
    def setUp(self):
        self.module = load_module()

    def test_remove_builtin_resolver_when_present(self):
        builtin = object()
        removed = []

        class Manager:
            def get(self, name):
                return builtin if name == "dnsresolver" else None

            def remove(self, addon):
                removed.append(addon)

        fake_ctx = SimpleNamespace(master=SimpleNamespace(addons=Manager()))
        with mock.patch.object(self.module, "ctx", fake_ctx):
            sinkhole = self.module.DnsSinkhole(allowed_names={"proxy"}, logger=RecordingLogger())
            self.assertTrue(sinkhole.remove_builtin_resolver())
        self.assertEqual(removed, [builtin])

    def test_remove_builtin_resolver_when_absent_or_no_master(self):
        class Manager:
            def get(self, name):
                return None

            def remove(self, addon):
                raise AssertionError("must not remove")

        fake_ctx = SimpleNamespace(master=SimpleNamespace(addons=Manager()))
        with mock.patch.object(self.module, "ctx", fake_ctx):
            sinkhole = self.module.DnsSinkhole(allowed_names={"proxy"}, logger=RecordingLogger())
            self.assertFalse(sinkhole.remove_builtin_resolver())
        with mock.patch.object(self.module, "ctx", SimpleNamespace()):
            self.assertFalse(sinkhole.remove_builtin_resolver())

    def test_load_logs_listening_event_always(self):
        logger = RecordingLogger()
        with mock.patch.object(self.module, "ctx", SimpleNamespace()):
            sinkhole = self.module.DnsSinkhole(allowed_names={"db", "proxy"}, logger=logger)
            sinkhole.load(loader=None)
        entry, always = logger.events[0]
        self.assertTrue(always)
        self.assertEqual(entry["action"], "listening")
        self.assertEqual(entry["allowed"], ["db", "proxy"])
        self.assertFalse(entry["builtin_resolver_removed"])

    def test_quiet_level_suppresses_refusal_events(self):
        stream = io.StringIO()
        logger = self.module._StdoutJsonLogger(log_level="quiet", stream=stream)
        logger.event({"type": "dns", "action": "nxdomain"})
        logger.event({"type": "dns", "action": "listening"}, always=True)
        lines = [line for line in stream.getvalue().splitlines() if line]
        self.assertEqual(len(lines), 1)
        self.assertIn('"listening"', lines[0])


if __name__ == "__main__":
    unittest.main()
