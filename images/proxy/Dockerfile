FROM mitmproxy/mitmproxy:latest

# nc used for docker compose health check
RUN apt-get update && apt-get install -y --no-install-recommends \
  netcat-traditional \
  && apt-get clean && rm -rf /var/lib/apt/lists/*

COPY addons/ /home/mitmproxy/addons/
COPY entrypoint.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/entrypoint.sh

# mitmdump for headless operation with JSON logging addon
# --set stream_large_bodies=1 prevents buffering large responses
ENTRYPOINT ["/usr/local/bin/entrypoint.sh", "-s", "/home/mitmproxy/addons/logger.py", "--set", "stream_large_bodies=1"]
