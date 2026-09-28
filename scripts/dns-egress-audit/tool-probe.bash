#!/usr/bin/env bash
# Which network tools go through the proxy, and which resolve names themselves?
# Runs inside an agent container. Part of the m18 tool inventory.
#
# Each tool fetches https://example.com, a host no policy allows. A tool that
# honours HTTPS_PROXY reaches the proxy and gets its 403. A tool that resolves
# the name itself asks the DNS sinkhole and fails with NXDOMAIN, which the tool
# reports as a DNS error. Neither outcome needs the host to be allowed, so the
# result does not depend on the project's policy.
#
# Tools that are not installed are reported as absent. Run it in each image
# whose tools you want measured:
#   docker exec -i <agent container> bash -s < scripts/dns-egress-audit/tool-probe.bash
#
# Output: one TSV line per tool: tool, version, result, detail.
#   proxied     the tool went through the proxy (a proxy 403 or another HTTP answer)
#   direct-dns  the tool resolved the name itself and got the sinkhole's NXDOMAIN
#   absent      the tool is not installed
#   unknown     neither pattern matched; read the detail
# The first row is a control: curl with the proxy switched off must read direct-dns.
set -u

URL=https://example.com/
HOST=example.com
TIMEOUT=15
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# classify OUTPUT: map a tool's combined output to a result word
classify() {
  case $1 in
    *"Blocked by proxy policy"*|*"403"*|*"Forbidden"*|*"CONNECT tunnel failed"*|*"unsuccessful tunnel"*|\
    *"Proxy response"*) echo proxied ;;
    *ENOTFOUND*|*EAI_AGAIN*|*EAI_NONAME*|*"Could not resolve"*|*"could not resolve"*|*"failed to lookup address"*|\
    *"dns error"*|*"Name or service not known"*|*"Temporary failure in name resolution"*|*"nodename nor servname"*|\
    *"no such host"*|*"getaddrinfo"*|*"NameResolutionError"*|*"Failed to resolve"*) echo direct-dns ;;
    *) echo unknown ;;
  esac
}

emit() { # TOOL VERSION RESULT DETAIL
  # The end of the output carries the reason; tools print warnings and context first.
  printf '%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$(printf '%s' "$4" | tr '\t\n' '  ' | tr -s ' ' | tail -c 240)"
}

probe() { # TOOL VERSION_CMD PROBE_CMD
  local tool=$1 version out
  if ! command -v "${tool%% *}" >/dev/null 2>&1; then
    emit "$tool" - absent ""
    return
  fi
  version=$(bash -c "$2" 2>&1 | head -n1 | cut -c1-40)
  out=$(cd "$WORK" && timeout "$TIMEOUT" bash -c "$3" 2>&1)
  emit "$tool" "$version" "$(classify "$out")" "$out"
}

# `docker exec ... bash -s` is not a login shell, so stacks that put their tools on PATH through /etc/profile.d
# (rust, go) would read as absent. An agent's own shell loads these files; load them here too.
set +u
for profile in /etc/profile.d/*.sh; do
  [ -r "$profile" ] && . "$profile"
done
set -u

printf 'HTTPS_PROXY=%s NO_PROXY=%s\n' "${HTTPS_PROXY:-unset}" "${NO_PROXY:-unset}" >&2

# Control: curl with the proxy switched off resolves the name itself, so it must read direct-dns.
# If it does not, the classification cannot be trusted for the rows below.
probe "curl --noproxy (control)" "curl --version" "curl -sS --noproxy '*' -o /dev/null $URL"
probe curl "curl --version" "curl -sS -o /dev/null -w '%{http_code} %{http_connect}' $URL"
probe git "git --version" "git ls-remote https://$HOST/x.git"
probe python3 "python3 --version" "python3 -c 'import urllib.request; urllib.request.urlopen(\"$URL\", timeout=10)'"
probe pip "pip --version" "pip download --no-deps --no-cache-dir -d . --index-url https://$HOST/simple requests"
probe node "node --version" "node -e 'fetch(\"$URL\").then(r => console.log(\"status\", r.status)).catch(e => console.log(\"error\", e.message, e.cause ? \"cause: \" + (e.cause.code || \"\") + \" \" + e.cause.message : \"\"))'"
# NODE_USE_ENV_PROXY makes Node's built-in fetch honour HTTPS_PROXY on Node versions that support it.
probe "node NODE_USE_ENV_PROXY=1" "node --version" "NODE_USE_ENV_PROXY=1 node -e 'fetch(\"$URL\").then(r => console.log(\"status\", r.status)).catch(e => console.log(\"error\", e.message, e.cause ? \"cause: \" + (e.cause.code || \"\") + \" \" + e.cause.message : \"\"))'"
probe npm "npm --version" "npm view --registry https://$HOST/ left-pad version"
probe uv "uv --version" "printf 'requests\n' | uv pip compile --no-cache --index-url https://$HOST/simple -"
probe cargo "cargo --version" "CARGO_HOME=\$PWD/cargo-home cargo search --limit 1 --index sparse+https://$HOST/ serde"
probe rustup "rustup --version" "RUSTUP_DIST_SERVER=https://$HOST rustup check"
probe go "go version" "GOFLAGS=-mod=mod GOPROXY=https://$HOST GONOSUMDB=* GOSUMDB=off go list -m golang.org/x/text@latest"
