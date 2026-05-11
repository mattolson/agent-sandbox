"""Integration harness for the mitmproxy enforcer addon.

Spawns `mitmdump` as a subprocess against a temporary policy file and captures
its stdout JSON log lines. Each test starts a fresh proxy; SIGHUP scenarios
edit the policy file in place within a single test.

Designed to work with `unittest`, matching the existing proxy test style.
"""

from __future__ import annotations

import http.server
import importlib.util
import json
import os
import shutil
import signal
import socket
import subprocess
import sys
import tempfile
import threading
import time
from importlib.machinery import SourceFileLoader
from pathlib import Path
from urllib.parse import urlsplit


REPO_ROOT = Path(__file__).resolve().parents[4]
ENFORCER_ADDON = REPO_ROOT / "images" / "proxy" / "addons" / "enforcer.py"
RENDER_POLICY_PATH = REPO_ROOT / "images" / "proxy" / "render-policy"
MITMDUMP = shutil.which("mitmdump")


class HarnessTimeoutError(Exception):
    """Raised when the harness times out waiting for a proxy event or signal."""


def mitmdump_available():
    return MITMDUMP is not None


def reserve_tcp_port():
    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    try:
        sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        sock.bind(("127.0.0.1", 0))
        return sock
    except Exception:
        sock.close()
        raise


def wait_for_port(port, timeout=10.0):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        try:
            with socket.create_connection(("127.0.0.1", port), timeout=0.2):
                return True
        except OSError:
            time.sleep(0.05)
    return False


class ProxyHarness:
    """Handle to a running mitmdump subprocess and its captured stdout."""

    def __init__(self, process, proxy_port, policy_path, workdir):
        self._process = process
        self._workdir = workdir
        self._stdout_lines: list[str] = []
        self._stdout_lock = threading.Lock()
        self._reader_thread = threading.Thread(target=self._pump_stdout, daemon=True)
        self.proxy_port = proxy_port
        self.policy_path = policy_path

    def start_reader(self):
        self._reader_thread.start()

    def _pump_stdout(self):
        assert self._process.stdout is not None
        for line in self._process.stdout:
            with self._stdout_lock:
                self._stdout_lines.append(line.rstrip("\n"))

    @property
    def proxy_url(self):
        return f"http://127.0.0.1:{self.proxy_port}"

    def write_policy(self, text):
        self.policy_path.write_text(text)

    def reload(self):
        self._process.send_signal(signal.SIGHUP)

    def snapshot_lines(self):
        with self._stdout_lock:
            return list(self._stdout_lines)

    def snapshot_events(self):
        events = []
        for line in self.snapshot_lines():
            stripped = line.strip()
            if not stripped:
                continue
            try:
                events.append(json.loads(stripped))
            except json.JSONDecodeError:
                # mitmdump's banner and render-policy's stderr are plain text.
                continue
        return events

    def wait_for_event(self, predicate, timeout=3.0):
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            for event in self.snapshot_events():
                if predicate(event):
                    return event
            time.sleep(0.05)
        raise HarnessTimeoutError(
            f"timed out waiting for event; last lines: {self.snapshot_lines()[-20:]}"
        )

    def send_request(self, method, url, timeout=3.0, body=b"", headers=None):
        """Forward an HTTP/1.1 request through the proxy using a raw socket.

        urllib honors `no_proxy` even when a ProxyHandler is explicit, which
        silently bypasses the proxy for loopback targets. Raw socket avoids
        that and gives us the unvarnished status line.
        """
        if isinstance(body, str):
            body = body.encode("utf-8")
        host_header = urlsplit(url).netloc
        extra_headers = ""
        for name, value in (headers or {}).items():
            extra_headers += f"{name}: {value}\r\n"
        headers = (
            f"{method} {url} HTTP/1.1\r\n"
            f"Host: {host_header}\r\n"
            f"{extra_headers}"
            f"Content-Length: {len(body)}\r\n"
            "Connection: close\r\n\r\n"
        )
        data = self._exchange(headers.encode("ascii") + body, timeout=timeout, read_all=True)
        return _parse_status_code(data), data

    def send_get(self, url, timeout=3.0, headers=None):
        return self.send_request("GET", url, timeout=timeout, headers=headers)

    def send_connect(self, host, port=443, timeout=3.0):
        """Send CONNECT and return (status_code, status_line). The proxy's
        CONNECT response arrives in the first chunk before any TLS handshake."""
        message = f"CONNECT {host}:{port} HTTP/1.1\r\nHost: {host}:{port}\r\n\r\n".encode("ascii")
        data = self._exchange(message, timeout=timeout, read_all=False)
        status_line = data.split(b"\r\n", 1)[0].decode("latin-1", errors="replace")
        return _parse_status_code(data), status_line

    def send_connect_and_wait(self, host, port, timeout=3.0):
        """Send CONNECT and read whatever the proxy returns before closing.

        Used when we want to observe that the proxy did not block at CONNECT
        but we cannot complete the TLS handshake (no real HTTPS upstream)."""
        message = f"CONNECT {host}:{port} HTTP/1.1\r\nHost: {host}:{port}\r\n\r\n".encode("ascii")
        return self._exchange(message, timeout=timeout, read_all=False, tolerate_timeout=True)

    def _exchange(self, payload, *, timeout, read_all, tolerate_timeout=False):
        with socket.create_connection(("127.0.0.1", self.proxy_port), timeout=timeout) as sock:
            sock.settimeout(timeout)
            sock.sendall(payload)
            data = b""
            try:
                while True:
                    chunk = sock.recv(4096)
                    if not chunk:
                        break
                    data += chunk
                    if not read_all and b"\r\n\r\n" in data:
                        break
            except socket.timeout:
                if not tolerate_timeout:
                    raise HarnessTimeoutError(
                        f"proxy did not respond within {timeout}s; received: {data!r}"
                    )
        return data

    def terminate(self):
        if self._process.poll() is None:
            self._process.send_signal(signal.SIGTERM)
            try:
                self._process.wait(timeout=5.0)
            except subprocess.TimeoutExpired:
                self._process.kill()
                self._process.wait(timeout=2.0)
        if self._process.stdout is not None:
            self._process.stdout.close()
        self._reader_thread.join(timeout=2.0)
        shutil.rmtree(self._workdir, ignore_errors=True)


def _parse_status_code(data):
    status_line = data.split(b"\r\n", 1)[0].decode("latin-1", errors="replace")
    parts = status_line.split(" ", 2)
    return int(parts[1]) if len(parts) >= 2 and parts[1].isdigit() else 0


def spawn_proxy(policy_text, *, enforce=True, mitmdump_settings=(), env_overrides=None):
    """Start mitmdump with the integration addon and return a ProxyHarness."""
    if MITMDUMP is None:
        raise RuntimeError("mitmdump not on PATH; cannot run integration harness")

    workdir = Path(tempfile.mkdtemp(prefix="agentbox-proxy-it-"))
    policy_path = workdir / "policy.yaml"
    policy_path.write_text(policy_text)
    reserved_port = reserve_tcp_port()
    proxy_port = reserved_port.getsockname()[1]

    env = os.environ.copy()
    env["PROXY_MODE"] = "enforce" if enforce else "log"
    env["PROXY_LOG_LEVEL"] = "normal"
    env["POLICY_PATH"] = str(policy_path)
    env["AGENTBOX_POLICY_SOURCE_PATH"] = str(policy_path)
    env["AGENTBOX_RENDER_POLICY_PATH"] = str(RENDER_POLICY_PATH)
    env.pop("AGENTBOX_ACTIVE_AGENT", None)
    if env_overrides:
        env.update(env_overrides)

    confdir = workdir / "mitmproxy"
    confdir.mkdir(parents=True, exist_ok=True)

    args = [
        MITMDUMP,
        "--set",
        f"confdir={confdir}",
    ]
    for setting in mitmdump_settings:
        args.extend(["--set", setting])
    args.extend(
        [
            "--listen-host",
            "127.0.0.1",
            "--listen-port",
            str(proxy_port),
            "--quiet",
            "-s",
            str(ENFORCER_ADDON),
        ]
    )
    try:
        process = subprocess.Popen(
            args,
            env=env,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            bufsize=1,
        )
    finally:
        reserved_port.close()

    harness = ProxyHarness(process, proxy_port, policy_path, workdir)
    harness.start_reader()

    if not wait_for_port(proxy_port, timeout=10.0):
        harness.terminate()
        raise RuntimeError(
            "mitmdump did not open listen port within 10s; "
            f"captured output: {harness.snapshot_lines()[-20:]}"
        )

    if enforce:
        harness.wait_for_event(
            lambda e: e.get("msg") == "SIGHUP reload handler installed",
            timeout=5.0,
        )

    return harness


class _RecordingHTTPServer(http.server.ThreadingHTTPServer):
    def __init__(self, server_address, handler_class):
        super().__init__(server_address, handler_class)
        self._requests = []
        self._requests_lock = threading.Lock()

    def record_request(self, method, path, body, headers):
        with self._requests_lock:
            self._requests.append({
                "method": method,
                "path": path,
                "body": body,
                "headers": headers,
            })

    def snapshot_requests(self):
        with self._requests_lock:
            return list(self._requests)


class _UpstreamHandler(http.server.BaseHTTPRequestHandler):
    def _respond(self):
        length = int(self.headers.get("Content-Length", "0") or 0)
        body = self.rfile.read(length) if length else b""
        self.server.record_request(self.command, self.path, body, dict(self.headers.items()))
        self.send_response(200)
        self.send_header("Content-Type", "text/plain")
        self.send_header("Content-Length", "2")
        self.end_headers()
        self.wfile.write(b"ok")

    def do_GET(self):  # noqa: N802 - BaseHTTPRequestHandler convention
        self._respond()

    def do_POST(self):  # noqa: N802
        self._respond()

    def log_message(self, format, *args):  # noqa: A002 - silence default logging
        return


class FakeUpstream:
    """Plain-HTTP recording server bound to 127.0.0.1 for proxy integration tests.

    Captures method, path, headers, and body for each request so tests can assert
    on what the proxy actually forwarded after policy match and request mutation.
    """

    def __init__(self):
        self.server = _RecordingHTTPServer(("127.0.0.1", 0), _UpstreamHandler)
        self.port = self.server.server_address[1]
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)

    def start(self):
        self.thread.start()

    def stop(self):
        self.server.shutdown()
        self.server.server_close()
        self.thread.join(timeout=2.0)

    @property
    def url(self):
        return f"http://127.0.0.1:{self.port}/"

    def snapshot_requests(self):
        return self.server.snapshot_requests()


def provision_secret_dir(secrets):
    """Materialize a 0700 directory containing 0600 secret files.

    Returns (TemporaryDirectory, source_url) where source_url is the
    `file:<path>` URL suitable for `AGENTBOX_SECRET_SOURCE`. The caller is
    responsible for cleaning up the directory.
    """
    tempdir = tempfile.TemporaryDirectory(prefix="agentbox-secrets-")
    root = Path(tempdir.name)
    os.chmod(root, 0o700)
    for name, value in secrets.items():
        path = root / name
        path.write_text(value, encoding="utf-8")
        os.chmod(path, 0o600)
    return tempdir, f"file:{root}"


_RENDER_POLICY_MODULE = None


def _load_render_policy_module():
    global _RENDER_POLICY_MODULE
    if _RENDER_POLICY_MODULE is not None:
        return _RENDER_POLICY_MODULE

    proxy_dir = REPO_ROOT / "images" / "proxy"
    added_path = False
    if str(proxy_dir) not in sys.path:
        sys.path.insert(0, str(proxy_dir))
        added_path = True

    try:
        loader = SourceFileLoader("agentbox_harness_render_policy", str(RENDER_POLICY_PATH))
        spec = importlib.util.spec_from_loader(loader.name, loader)
        module = importlib.util.module_from_spec(spec)
        loader.exec_module(module)
    finally:
        if added_path:
            sys.path.remove(str(proxy_dir))

    _RENDER_POLICY_MODULE = module
    return module


def render_authored_policy(source_text):
    """Render an authored policy YAML through the real `render-policy` module.

    Returns the rendered policy dict. Tests can mutate the result (for example,
    to remap host names onto the fake upstream) before serializing it for
    `spawn_proxy`.
    """
    import yaml

    render_policy = _load_render_policy_module()
    with tempfile.TemporaryDirectory(prefix="agentbox-render-") as tempdir:
        source_path = Path(tempdir) / "source.yaml"
        source_path.write_text(source_text, encoding="utf-8")
        old_env = {}
        keys = (
            "AGENTBOX_POLICY_SOURCE_PATH",
            "AGENTBOX_SHARED_POLICY_PATH",
            "AGENTBOX_AGENT_POLICY_PATH",
            "AGENTBOX_DEVCONTAINER_POLICY_PATH",
            "AGENTBOX_ACTIVE_AGENT",
        )
        for key in keys:
            old_env[key] = os.environ.get(key)
        os.environ["AGENTBOX_POLICY_SOURCE_PATH"] = str(source_path)
        os.environ.pop("AGENTBOX_ACTIVE_AGENT", None)
        try:
            return render_policy.render_single_policy()
        finally:
            for key, value in old_env.items():
                if value is None:
                    os.environ.pop(key, None)
                else:
                    os.environ[key] = value


def remap_rendered_host(rendered_policy, host_map):
    """Rewrite host values in a rendered policy's `domains` entries.

    `host_map` is a dict like `{"github.com": "127.0.0.1"}`. Returns a new
    policy dict; the input is left unmodified.
    """
    if "domains" not in rendered_policy:
        return dict(rendered_policy)

    remapped = dict(rendered_policy)
    new_domains = []
    for record in rendered_policy["domains"]:
        new_record = dict(record)
        host = new_record.get("host")
        if host in host_map:
            new_record["host"] = host_map[host]
        new_domains.append(new_record)
    remapped["domains"] = new_domains
    return remapped
