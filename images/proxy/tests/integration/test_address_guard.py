"""Integration tests for the proxy address guard against the real mitmdump.

`test_invariant_*` tests pin down how mitmproxy behaves around the guard: that
it dials by hostname through asyncio, so staged answers pin the dial; that a
connection killed in `server_connect` never reaches the network; and that the
CONNECT error response can be replaced. If one fails after a mitmproxy or
Python bump, the guard's design no longer holds. Do not relax the test; see
docs/plan/milestones/m18-dns-egress-controls/tasks/m18.4-proxy-address-guard/.

Names under `.invalid` never resolve (RFC 2606), so a request to one succeeds
only if the dial used the answer the guard staged.
"""

from __future__ import annotations

import datetime
import http.client
import json
import ssl
import tempfile
import unittest
from pathlib import Path

import yaml

from .harness import (
    ConnectionCounter,
    FakeTlsUpstream,
    FakeUpstream,
    mitmdump_available,
    spawn_proxy,
)


TEST_ADDON = Path(__file__).resolve().parent / "address_guard_test_addon.py"
MARKER = "agent-sandbox address guard:"


def _skip_reason():
    return "mitmdump not available on PATH; install mitmproxy to run integration tests"


def _policy(hosts):
    return yaml.safe_dump({"domains": list(hosts)}, sort_keys=False)


def _write_test_pki(directory, names):
    """A CA and a leaf certificate for `names`, as PEM files. Returns (ca, cert, key) paths."""
    from cryptography import x509
    from cryptography.hazmat.primitives import hashes, serialization
    from cryptography.hazmat.primitives.asymmetric import ec
    from cryptography.x509.oid import NameOID

    now = datetime.datetime.now(datetime.timezone.utc)
    ca_key = ec.generate_private_key(ec.SECP256R1())
    ca_name = x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, "address-guard-test-ca")])
    ca_cert = (
        x509.CertificateBuilder()
        .subject_name(ca_name)
        .issuer_name(ca_name)
        .public_key(ca_key.public_key())
        .serial_number(x509.random_serial_number())
        .not_valid_before(now - datetime.timedelta(minutes=5))
        .not_valid_after(now + datetime.timedelta(days=1))
        .add_extension(x509.BasicConstraints(ca=True, path_length=None), critical=True)
        .add_extension(
            x509.KeyUsage(
                digital_signature=True, content_commitment=False, key_encipherment=False,
                data_encipherment=False, key_agreement=False, key_cert_sign=True, crl_sign=True,
                encipher_only=False, decipher_only=False,
            ),
            critical=True,
        )
        .add_extension(x509.SubjectKeyIdentifier.from_public_key(ca_key.public_key()), critical=False)
        .sign(ca_key, hashes.SHA256())
    )
    leaf_key = ec.generate_private_key(ec.SECP256R1())
    leaf_cert = (
        x509.CertificateBuilder()
        .subject_name(x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, names[0])]))
        .issuer_name(ca_name)
        .public_key(leaf_key.public_key())
        .serial_number(x509.random_serial_number())
        .not_valid_before(now - datetime.timedelta(minutes=5))
        .not_valid_after(now + datetime.timedelta(days=1))
        .add_extension(x509.SubjectAlternativeName([x509.DNSName(name) for name in names]), critical=False)
        .add_extension(x509.BasicConstraints(ca=False, path_length=None), critical=True)
        .add_extension(x509.ExtendedKeyUsage([x509.oid.ExtendedKeyUsageOID.SERVER_AUTH]), critical=False)
        .add_extension(
            x509.AuthorityKeyIdentifier.from_issuer_public_key(ca_key.public_key()), critical=False
        )
        .sign(ca_key, hashes.SHA256())
    )
    ca_path = Path(directory, "ca.pem")
    cert_path = Path(directory, "leaf.pem")
    key_path = Path(directory, "leaf.key")
    ca_path.write_bytes(ca_cert.public_bytes(serialization.Encoding.PEM))
    cert_path.write_bytes(leaf_cert.public_bytes(serialization.Encoding.PEM))
    key_path.write_bytes(
        leaf_key.private_bytes(
            serialization.Encoding.PEM,
            serialization.PrivateFormat.PKCS8,
            serialization.NoEncryption(),
        )
    )
    return ca_path, cert_path, key_path


@unittest.skipUnless(mitmdump_available(), _skip_reason())
class AddressGuardIntegrationTests(unittest.TestCase):
    def spawn(self, hosts, *, dns=None, allow=None, sandbox=None, settings=(), listen_host="127.0.0.1"):
        env = {}
        extra = ()
        if dns is not None or allow is not None or sandbox is not None:
            env = {
                "AGENTBOX_TEST_GUARD_DNS": json.dumps(dns or {}),
                "AGENTBOX_TEST_GUARD_ALLOW": json.dumps(allow or []),
            }
            if sandbox is not None:
                env["AGENTBOX_TEST_GUARD_SANDBOX"] = json.dumps(sandbox)
            extra = (TEST_ADDON,)
        harness = spawn_proxy(
            _policy(hosts), env_overrides=env, extra_addons=extra, mitmdump_settings=settings, listen_host=listen_host
        )
        self.addCleanup(harness.terminate)
        if extra:
            harness.wait_for_event(lambda e: e.get("msg") == "address guard test config loaded", timeout=5.0)
        return harness

    def guard_events(self, harness, action="blocked"):
        return [
            e for e in harness.snapshot_events()
            if e.get("type") == "address_guard" and e.get("action") == action
        ]

    def plain_upstream(self):
        upstream = FakeUpstream()
        upstream.start()
        self.addCleanup(upstream.stop)
        return upstream

    # --- refusals --------------------------------------------------------

    def test_allowed_name_resolving_to_loopback_is_refused_with_403(self):
        # Real DNS: localhost resolves to loopback on every machine.
        upstream = self.plain_upstream()
        harness = self.spawn(["localhost"])
        status, data = harness.send_get(f"http://localhost:{upstream.port}/secret")
        self.assertEqual(status, 403)
        self.assertIn(MARKER.encode(), data)
        self.assertEqual(upstream.snapshot_requests(), [], "the refused request must not reach the address")
        event = harness.wait_for_event(lambda e: e.get("type") == "address_guard" and e.get("action") == "blocked")
        self.assertEqual((event["phase"], event["address_class"], event["host"]), ("request", "loopback", "localhost"))

    def test_each_denied_class_is_refused_and_named(self):
        samples = {
            "loopback": "127.0.0.2",
            "private": "10.20.30.40",
            "metadata": "169.254.169.254",
            "link_local": "169.254.10.10",
            "unique_local": "fd12:3456::1",
            "shared": "100.64.1.1",
            "unspecified": "0.0.0.0",
            "multicast": "224.0.0.9",
            "reserved": "240.0.0.1",
            "sandbox_network": "198.19.0.7",
        }
        names = {f"{cls.replace('_', '-')}.invalid": address for cls, address in samples.items()}
        harness = self.spawn(names, dns={name: [address] for name, address in names.items()}, sandbox=["198.19.0.0/24"])
        for address_class, address in samples.items():
            name = f"{address_class.replace('_', '-')}.invalid"
            with self.subTest(address_class=address_class):
                status, data = harness.send_get(f"http://{name}/")
                self.assertEqual(status, 403)
                self.assertIn(f"{name} resolves to {address} ({address_class})".encode(), data)
                event = harness.wait_for_event(
                    lambda e, n=name: e.get("type") == "address_guard" and e.get("host") == n
                )
                self.assertEqual(event["address_class"], address_class)

    def test_invariant_refused_connect_gets_403_and_no_packet_reaches_the_address(self):
        """server_connect's error kills the dial before any packet, and the CONNECT 502 can be replaced."""
        counter = ConnectionCounter()
        counter.start()
        self.addCleanup(counter.stop)
        harness = self.spawn(["refused.invalid"], dns={"refused.invalid": ["127.0.0.1"]})
        data = harness.send_connect_full("refused.invalid", counter.port)
        status_line = data.split(b"\r\n", 1)[0]
        self.assertIn(b" 403 ", status_line, f"CONNECT response: {data[:200]!r}")
        self.assertIn(MARKER.encode(), data)
        self.assertEqual(counter.accepted, 0, "the refused address must receive no connection at all")
        event = harness.wait_for_event(lambda e: e.get("type") == "address_guard" and e.get("action") == "blocked")
        self.assertEqual((event["phase"], event["address_class"]), ("connect", "loopback"))

    def test_mixed_answer_is_refused_on_its_denied_half(self):
        upstream = self.plain_upstream()
        harness = self.spawn(
            ["mixed.invalid"],
            dns={"mixed.invalid": ["127.0.0.1", "10.0.0.9"]},
            allow=["127.0.0.1"],
        )
        status, data = harness.send_get(f"http://mixed.invalid:{upstream.port}/")
        self.assertEqual(status, 403)
        self.assertIn(b"resolves to 10.0.0.9 (private)", data)
        self.assertEqual(upstream.snapshot_requests(), [])

    # --- pinning ---------------------------------------------------------

    def test_invariant_https_through_a_tunnel_is_pinned_with_sni_host_and_reuse_intact(self):
        """mitmproxy dials the tunnel by hostname through asyncio, so the staged answer is used.

        The name cannot resolve, so reaching the upstream at all proves the pin. The
        upstream also sees the hostname as SNI and Host, both requests arrive on one
        connection, and the enforcer matched the policy against the hostname.
        """
        tempdir = tempfile.TemporaryDirectory()
        self.addCleanup(tempdir.cleanup)
        ca_path, cert_path, key_path = _write_test_pki(tempdir.name, ["pinned.invalid"])
        upstream = FakeTlsUpstream(cert_path, key_path)
        upstream.start()
        self.addCleanup(upstream.stop)
        harness = self.spawn(
            ["pinned.invalid"],
            dns={"pinned.invalid": ["127.0.0.1"]},
            allow=["127.0.0.1"],
            settings=(f"ssl_verify_upstream_trusted_ca={ca_path}",),
        )
        context = ssl.create_default_context(cafile=str(harness.ca_cert_path))
        connection = http.client.HTTPSConnection("127.0.0.1", harness.proxy_port, context=context, timeout=5)
        connection.set_tunnel("pinned.invalid", upstream.port)
        self.addCleanup(connection.close)
        statuses = []
        for path in ("/one", "/two"):
            connection.request("GET", path)
            response = connection.getresponse()
            response.read()
            statuses.append(response.status)

        self.assertEqual(statuses, [200, 200], f"proxy log: {harness.snapshot_lines()[-15:]}")
        requests = upstream.snapshot_requests()
        self.assertEqual([r["path"] for r in requests], ["/one", "/two"])
        self.assertEqual(upstream.server_names, ["pinned.invalid"], "SNI must stay the hostname")
        self.assertEqual({r["headers"]["Host"] for r in requests}, {f"pinned.invalid:{upstream.port}"})
        self.assertEqual(
            len({r["headers"]["x-test-client-port"] for r in requests}), 1,
            "both requests must share one upstream connection",
        )
        decisions = [e for e in harness.snapshot_events() if e.get("action") == "allowed" and e.get("status") == 200]
        self.assertEqual({e["host"] for e in decisions}, {"pinned.invalid"}, "request.host must stay the hostname")
        self.assertEqual(self.guard_events(harness), [])

    def test_invariant_plain_http_is_pinned(self):
        upstream = self.plain_upstream()
        harness = self.spawn(["pinned.invalid"], dns={"pinned.invalid": ["127.0.0.1"]}, allow=["127.0.0.1"])
        status, _ = harness.send_get(f"http://pinned.invalid:{upstream.port}/plain")
        self.assertEqual(status, 200, f"proxy log: {harness.snapshot_lines()[-15:]}")
        requests = upstream.snapshot_requests()
        self.assertEqual([r["path"] for r in requests], ["/plain"])
        self.assertEqual(requests[0]["headers"]["Host"], f"pinned.invalid:{upstream.port}")

    # --- no change ---------------------------------------------------------

    def test_ip_literal_hosts_are_not_checked(self):
        upstream = self.plain_upstream()
        harness = self.spawn(["127.0.0.1"])
        status, _ = harness.send_get(f"http://127.0.0.1:{upstream.port}/")
        self.assertEqual(status, 200)
        self.assertEqual(self.guard_events(harness), [])

    def test_proxy_bound_to_every_interface_serves_and_still_refuses(self):
        """The image binds every interface; the guard must work the same way there.

        mitmdump binds before the guard installs its wrapper, so this does not exercise
        the bind lookup itself; `test_invariant_binding_every_interface_is_not_checked`
        in the unit tests does.
        """
        upstream = self.plain_upstream()
        harness = self.spawn(["127.0.0.1", "localhost"], listen_host=None)
        status, _ = harness.send_get(f"http://127.0.0.1:{upstream.port}/")
        self.assertEqual(status, 200, f"proxy log: {harness.snapshot_lines()[-15:]}")
        status, data = harness.send_get(f"http://localhost:{upstream.port}/")
        self.assertEqual(status, 403, "the guard must still refuse dials when the proxy binds every interface")
        self.assertIn(MARKER.encode(), data)

    def test_guard_announces_itself_with_pinning_enabled(self):
        harness = self.spawn(["127.0.0.1"])
        event = harness.wait_for_event(lambda e: e.get("type") == "address_guard" and e.get("action") in ("enabled", "pinning_unavailable"))
        self.assertEqual(event["action"], "enabled", f"guard reported: {event}")


if __name__ == "__main__":
    unittest.main()
