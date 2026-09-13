"""Integration tests for the DNS sinkhole served by the real mitmdump process.

Spawns mitmdump with both the regular proxy mode and a DNS-mode listener, the way
the proxy image runs it, then sends hand-packed DNS queries over UDP and TCP and
asserts on the answers and on the structured events.
"""

from __future__ import annotations

import socket
import struct
import time
import unittest

import yaml

from .harness import mitmdump_available, spawn_proxy


def _skip_reason():
    return "mitmdump not available on PATH; install mitmproxy to run integration tests"


def pack_query(name, qtype, qid=0x1234):
    header = struct.pack("!HHHHHH", qid, 0x0100, 1, 0, 0, 0)
    labels = b"".join(bytes([len(label)]) + label.encode("ascii") for label in name.rstrip(".").split("."))
    return header + labels + b"\x00" + struct.pack("!HH", qtype, 1)


def _skip_name(data, offset):
    while True:
        length = data[offset]
        if length == 0:
            return offset + 1
        if length & 0xC0 == 0xC0:
            return offset + 2
        offset += 1 + length


def parse_response(data):
    qid, flags, qdcount, ancount, _, _ = struct.unpack("!HHHHHH", data[:12])
    rcode = flags & 0x000F
    offset = 12
    for _ in range(qdcount):
        offset = _skip_name(data, offset) + 4
    answers = []
    for _ in range(ancount):
        offset = _skip_name(data, offset)
        rtype, rclass, ttl, rdlength = struct.unpack("!HHIH", data[offset:offset + 10])
        offset += 10
        answers.append((rtype, ttl, data[offset:offset + rdlength]))
        offset += rdlength
    return qid, rcode, answers


def query_udp(port, name, qtype, timeout=2.0):
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        sock.settimeout(timeout)
        sock.sendto(pack_query(name, qtype), ("127.0.0.1", port))
        data, _ = sock.recvfrom(4096)
    finally:
        sock.close()
    return parse_response(data)


def query_tcp(port, name, qtype, timeout=2.0):
    packet = pack_query(name, qtype)
    with socket.create_connection(("127.0.0.1", port), timeout=timeout) as sock:
        sock.sendall(struct.pack("!H", len(packet)) + packet)
        header = sock.recv(2)
        length = struct.unpack("!H", header)[0]
        data = b""
        while len(data) < length:
            chunk = sock.recv(length - len(data))
            if not chunk:
                break
            data += chunk
    return parse_response(data)


def wait_for_dns(port, timeout=5.0):
    deadline = time.monotonic() + timeout
    last_error = None
    while time.monotonic() < deadline:
        try:
            return query_udp(port, "readiness.invalid", 1, timeout=0.5)
        except OSError as error:
            last_error = error
            time.sleep(0.1)
    raise RuntimeError(f"DNS listener on {port} never answered: {last_error}")


@unittest.skipUnless(mitmdump_available(), _skip_reason())
class DnsSinkholeIntegrationTests(unittest.TestCase):
    def spawn(self, **env):
        overrides = {"AGENTBOX_DNS_ALLOW": "localhost"}
        overrides.update(env)
        harness = spawn_proxy(
            yaml.safe_dump({"domains": ["example.com"]}, sort_keys=False),
            dns=True,
            env_overrides=overrides,
        )
        self.addCleanup(harness.terminate)
        wait_for_dns(harness.dns_port)
        return harness

    def test_listener_starts_with_builtin_resolver_removed(self):
        harness = self.spawn()
        event = harness.wait_for_event(lambda e: e.get("type") == "dns" and e.get("action") == "listening")
        self.assertTrue(event["builtin_resolver_removed"])
        self.assertEqual(event["allowed"], ["localhost", "proxy"])

    def test_unknown_name_is_nxdomain_over_udp_and_tcp(self):
        harness = self.spawn()
        for query in (query_udp, query_tcp):
            with self.subTest(transport=query.__name__):
                qid, rcode, answers = query(harness.dns_port, "exfil-label.example.com", 1)
                self.assertEqual(qid, 0x1234)
                self.assertEqual(rcode, 3)
                self.assertEqual(answers, [])
        event = harness.wait_for_event(
            lambda e: e.get("type") == "dns" and e.get("action") == "nxdomain" and e.get("name") == "exfil-label.example.com"
        )
        self.assertEqual(event["qtype"], "A")
        self.assertEqual(event["client"], "127.0.0.1")

    def test_policy_allowed_http_host_is_still_nxdomain_for_dns(self):
        # example.com is on the HTTP allowlist; the sinkhole does not consult policy.
        harness = self.spawn()
        _, rcode, _ = query_udp(harness.dns_port, "example.com", 1)
        self.assertEqual(rcode, 3)

    def test_allowed_name_is_answered_with_addresses_and_ttl(self):
        harness = self.spawn()
        for query in (query_udp, query_tcp):
            with self.subTest(transport=query.__name__):
                _, rcode, answers = query(harness.dns_port, "localhost", 1)
                self.assertEqual(rcode, 0)
                self.assertTrue(answers, "expected at least one A record for localhost")
                for rtype, ttl, rdata in answers:
                    self.assertEqual(rtype, 1)
                    self.assertEqual(ttl, 30)
                self.assertIn(socket.inet_aton("127.0.0.1"), [rdata for _, _, rdata in answers])

    def test_allowed_name_with_txt_is_empty_noerror(self):
        harness = self.spawn()
        _, rcode, answers = query_udp(harness.dns_port, "localhost", 16)
        self.assertEqual(rcode, 0)
        self.assertEqual(answers, [])

    def test_http_proxy_still_enforces_next_to_the_sinkhole(self):
        harness = self.spawn()
        status, _ = harness.send_request("GET", "http://blocked.invalid/")
        self.assertEqual(status, 403)


if __name__ == "__main__":
    unittest.main()
