"""Integration harness for the mitmproxy enforcer addon.

Spawns `mitmdump` as a subprocess against a temporary policy file and captures
its stdout JSON log lines. Each test starts a fresh proxy; SIGHUP scenarios
edit the policy file in place within a single test.

Designed to work with `unittest`, matching the existing proxy test style.
"""

from __future__ import annotations

import json
import os
import shutil
import signal
import socket
import subprocess
import tempfile
import threading
import time
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


def pick_free_port():
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
        sock.bind(("127.0.0.1", 0))
        return sock.getsockname()[1]


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

    def send_request(self, method, url, timeout=3.0, body=b""):
        """Forward an HTTP/1.1 request through the proxy using a raw socket.

        urllib honors `no_proxy` even when a ProxyHandler is explicit, which
        silently bypasses the proxy for loopback targets. Raw socket avoids
        that and gives us the unvarnished status line.
        """
        if isinstance(body, str):
            body = body.encode("utf-8")
        host_header = urlsplit(url).netloc
        headers = (
            f"{method} {url} HTTP/1.1\r\n"
            f"Host: {host_header}\r\n"
            f"Content-Length: {len(body)}\r\n"
            "Connection: close\r\n\r\n"
        )
        data = self._exchange(headers.encode("ascii") + body, timeout=timeout, read_all=True)
        return _parse_status_code(data), data

    def send_get(self, url, timeout=3.0):
        return self.send_request("GET", url, timeout=timeout)

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


def spawn_proxy(policy_text, *, enforce=True):
    """Start mitmdump with the integration addon and return a ProxyHarness."""
    if MITMDUMP is None:
        raise RuntimeError("mitmdump not on PATH; cannot run integration harness")

    workdir = Path(tempfile.mkdtemp(prefix="agentbox-proxy-it-"))
    policy_path = workdir / "policy.yaml"
    policy_path.write_text(policy_text)
    proxy_port = pick_free_port()

    env = os.environ.copy()
    env["PROXY_MODE"] = "enforce" if enforce else "log"
    env["PROXY_LOG_LEVEL"] = "normal"
    env["POLICY_PATH"] = str(policy_path)
    env["AGENTBOX_POLICY_SOURCE_PATH"] = str(policy_path)
    env["AGENTBOX_RENDER_POLICY_PATH"] = str(RENDER_POLICY_PATH)
    env.pop("AGENTBOX_ACTIVE_AGENT", None)

    confdir = workdir / "mitmproxy"
    confdir.mkdir(parents=True, exist_ok=True)

    args = [
        MITMDUMP,
        "--set",
        f"confdir={confdir}",
        "--listen-host",
        "127.0.0.1",
        "--listen-port",
        str(proxy_port),
        "--quiet",
        "-s",
        str(ENFORCER_ADDON),
    ]
    process = subprocess.Popen(
        args,
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        bufsize=1,
    )

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
