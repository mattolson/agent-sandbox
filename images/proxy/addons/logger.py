"""
JSON logging addon for mitmproxy.

Logs all HTTP requests and HTTPS CONNECT tunnels to stdout in JSON format.
Discovery mode: logs everything, blocks nothing.
"""

import json
import sys
from datetime import datetime, timezone

from mitmproxy import http

class JsonLogger:
    def http_connect(self, flow: http.HTTPFlow):
        """Log HTTPS CONNECT tunnels (we only see host:port)."""
        log_entry = {
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "type": "connect",
            "host": flow.request.host,
            "port": flow.request.port,
        }
        print(json.dumps(log_entry), file=sys.stdout, flush=True)

    def response(self, flow: http.HTTPFlow):
        """Log completed HTTP requests (plain HTTP only, HTTPS is tunneled)."""
        if flow.request.scheme == "http":
            log_entry = {
                "timestamp": datetime.now(timezone.utc).isoformat(),
                "type": "http",
                "method": flow.request.method,
                "host": flow.request.host,
                "port": flow.request.port,
                "path": flow.request.path,
                "status": flow.response.status_code if flow.response else None,
            }
            print(json.dumps(log_entry), file=sys.stdout, flush=True)

    def error(self, flow: http.HTTPFlow):
        """Log connection errors."""
        log_entry = {
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "type": "error",
            "host": flow.request.host,
            "port": flow.request.port,
            "error": str(flow.error) if flow.error else "unknown",
        }
        print(json.dumps(log_entry), file=sys.stdout, flush=True)


addons = [JsonLogger()]
