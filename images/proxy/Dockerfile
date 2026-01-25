FROM mitmproxy/mitmproxy:latest

# nc used for docker compose health check
RUN apt-get update && apt-get install -y --no-install-recommends \
  netcat-traditional \
  && apt-get clean && rm -rf /var/lib/apt/lists/*

RUN pip install --no-cache-dir PyYAML

COPY policy.yaml /etc/mitmproxy/policy.yaml
COPY addons/ /home/mitmproxy/addons/
COPY entrypoint.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/entrypoint.sh

# mitmdump for headless operation with policy enforcement addon
# --set stream_large_bodies=1 prevents buffering large responses
ENTRYPOINT ["/usr/local/bin/entrypoint.sh", "-s", "/home/mitmproxy/addons/enforcer.py", "--set", "stream_large_bodies=1"]
