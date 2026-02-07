FROM mitmproxy/mitmproxy:latest

# nc used for docker compose health check
RUN apt-get update && apt-get install -y --no-install-recommends \
  netcat-traditional \
  && apt-get clean && rm -rf /var/lib/apt/lists/*

# Optional extra packages
ARG EXTRA_PACKAGES=""
RUN if [ -n "$EXTRA_PACKAGES" ]; then \
      printf '%s' "$EXTRA_PACKAGES" | grep -qE '^[a-zA-Z0-9][a-zA-Z0-9.+\- :]*$' \
        || { echo "ERROR: EXTRA_PACKAGES contains invalid characters: $EXTRA_PACKAGES" >&2; exit 1; }; \
      apt-get update && apt-get install -y --no-install-recommends $EXTRA_PACKAGES \
      && apt-get clean && rm -rf /var/lib/apt/lists/*; \
    fi

RUN pip install --no-cache-dir PyYAML

COPY policy.yaml /etc/mitmproxy/policy.yaml
COPY addons/ /home/mitmproxy/addons/
COPY entrypoint.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/entrypoint.sh

# mitmdump for headless operation with policy enforcement addon
# --set stream_large_bodies=1 prevents buffering large responses
# --set http2=false avoids HTTP/2 header validation issues (e.g., gh CLI trailing whitespace)
ENTRYPOINT ["/usr/local/bin/entrypoint.sh", "-s", "/home/mitmproxy/addons/enforcer.py", "--set", "stream_large_bodies=1", "--set", "http2=false"]
