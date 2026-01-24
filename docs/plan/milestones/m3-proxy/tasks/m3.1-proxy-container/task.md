# m3.1-proxy-container

Create the mitmproxy container and compose service with structured logging.

## Goal

A working proxy container that:
- Runs mitmproxy on port 8080
- Logs all requests as structured JSON
- Integrates into docker-compose.yml

## Implementation

### Files to create

```
images/
  proxy/
    Dockerfile
    addons/
      logger.py      # JSON logging addon
```

### Dockerfile

Based on official `mitmproxy/mitmproxy` image. The official image runs as root by default and includes mitmdump (headless), mitmproxy (console), and mitmweb (web UI).

```dockerfile
FROM mitmproxy/mitmproxy:latest

COPY addons/ /home/mitmproxy/addons/

# Use mitmdump for headless operation with our logging addon
ENTRYPOINT ["mitmdump", "-s", "/home/mitmproxy/addons/logger.py"]
```

We use `mitmdump` (not `mitmproxy` or `mitmweb`) because:
- Headless, no UI needed
- Lower resource usage
- Designed for scripting/automation

### Logging addon (logger.py)

mitmproxy addons are Python classes with hook methods. Key hooks:

- `http_connect(flow)`: Called for CONNECT requests (HTTPS tunneling)
- `request(flow)`: Called for HTTP requests
- `response(flow)`: Called when response is received
- `error(flow)`: Called on connection errors

For discovery mode, we want to log:
- All CONNECT requests (shows HTTPS destinations)
- All HTTP requests (shows full URL for plain HTTP)

```python
import json
import sys
from datetime import datetime, timezone
from mitmproxy import http

class JsonLogger:
    def http_connect(self, flow: http.HTTPFlow):
        """Log HTTPS CONNECT tunnels (we only see host:port)"""
        log_entry = {
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "type": "connect",
            "host": flow.request.host,
            "port": flow.request.port,
        }
        print(json.dumps(log_entry), file=sys.stdout, flush=True)

    def response(self, flow: http.HTTPFlow):
        """Log completed HTTP requests (plain HTTP only, HTTPS is tunneled)"""
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
        """Log connection errors"""
        log_entry = {
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "type": "error",
            "host": flow.request.host,
            "port": flow.request.port,
            "error": str(flow.error) if flow.error else "unknown",
        }
        print(json.dumps(log_entry), file=sys.stdout, flush=True)

addons = [JsonLogger()]
```

Logs go to stdout, which Docker captures. Can view with `docker compose logs proxy`.

### Compose service

Add to docker-compose.yml:

```yaml
services:
  proxy:
    build: ./images/proxy
    container_name: agent-sandbox-proxy
    ports:
      - "8080:8080"  # Optional: expose for debugging
    healthcheck:
      test: ["CMD", "nc", "-z", "localhost", "8080"]
      interval: 5s
      timeout: 3s
      retries: 3

  agent:
    # ... existing config ...
    depends_on:
      proxy:
        condition: service_healthy
    environment:
      - HTTP_PROXY=http://proxy:8080
      - HTTPS_PROXY=http://proxy:8080
      # ... existing env vars ...
```

### Health check

mitmproxy doesn't have a built-in health endpoint. Options:
1. `nc -z localhost 8080` - check port is listening
2. Hit mitmproxy's web interface if using mitmweb
3. Custom health endpoint via addon

Option 1 is simplest and sufficient.

## Testing

1. Build and start: `docker compose up -d`
2. Exec into agent: `docker compose exec agent zsh`
3. Make requests: `curl https://api.github.com/zen`
4. Check logs: `docker compose logs proxy`
5. Verify JSON output with host/port info

## Open questions

1. **Log persistence**: Stdout logs are ephemeral. Should we also write to a file volume? Defer to m3.3.
2. **mitmproxy version pinning**: Use `latest` for now, pin after we verify it works.
3. **NO_PROXY**: Some internal traffic (localhost, proxy container itself) should bypass. Handle in m3.2.

## Definition of done

- [ ] `images/proxy/Dockerfile` exists and builds
- [ ] `images/proxy/addons/logger.py` outputs JSON on requests
- [ ] Compose service defined with health check
- [ ] Can see JSON logs via `docker compose logs proxy`
