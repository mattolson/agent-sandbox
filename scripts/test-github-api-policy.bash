#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  scripts/test-github-api-policy.bash --allowed OWNER/REPO [--blocked OWNER/REPO]

Validates repo-scoped GitHub API policy through the configured HTTP proxy.

Options:
  --allowed OWNER/REPO       Repo that should be allowed by policy. Defaults to
                             GITHUB_ALLOWED_REPO or the current origin remote.
  --blocked OWNER/REPO       Repo that should be blocked by policy. Defaults to
                             GITHUB_BLOCKED_REPO or octocat/Hello-World.
  --expect-write MODE        skip, allowed, or blocked. Defaults to
                             EXPECT_API_WRITE or skip. Uses an intentionally
                             invalid issue-create request so GitHub sees the
                             method without creating anything.
  --proxy URL                Proxy URL. Defaults to HTTPS_PROXY or HTTP_PROXY.
  --api-base URL             GitHub API base. Defaults to https://api.github.com.
  -h, --help                 Show this help.

Environment:
  GITHUB_TOKEN               Optional token for private repos or higher rate
                             limits. The token is never printed.
USAGE
}

die() {
  printf 'error: %s\n' "$*" >&2
  exit 2
}

infer_repo_from_origin() {
  local remote candidate
  remote="$(git config --get remote.origin.url 2>/dev/null || true)"
  [ -n "$remote" ] || return 1

  case "$remote" in
    https://github.com/*)
      candidate="${remote#https://github.com/}"
      ;;
    git@github.com:*)
      candidate="${remote#git@github.com:}"
      ;;
    ssh://git@github.com/*)
      candidate="${remote#ssh://git@github.com/}"
      ;;
    *)
      return 1
      ;;
  esac

  candidate="${candidate%.git}"
  case "$candidate" in
    */*) printf '%s\n' "$candidate" ;;
    *) return 1 ;;
  esac
}

validate_repo() {
  local label="$1"
  local repo="$2"
  if [[ ! "$repo" =~ ^[^[:space:]/]+/[^[:space:]/]+$ ]]; then
    die "$label must be in OWNER/REPO form, got: $repo"
  fi
}

print_snippet() {
  local file="$1"
  if [ -f "$file" ]; then
    sed -n '1,12p' "$file" | sed 's/^/  /'
  else
    printf '  <no response body captured>\n'
  fi
}

allowed_repo="${GITHUB_ALLOWED_REPO:-}"
blocked_repo="${GITHUB_BLOCKED_REPO:-octocat/Hello-World}"
expect_write="${EXPECT_API_WRITE:-skip}"
api_base="${GITHUB_API_BASE:-https://api.github.com}"
proxy_url="${HTTPS_PROXY:-${HTTP_PROXY:-}}"

while [ "$#" -gt 0 ]; do
  case "$1" in
    --allowed)
      [ "$#" -ge 2 ] || die "--allowed requires OWNER/REPO"
      allowed_repo="$2"
      shift 2
      ;;
    --blocked)
      [ "$#" -ge 2 ] || die "--blocked requires OWNER/REPO"
      blocked_repo="$2"
      shift 2
      ;;
    --expect-write)
      [ "$#" -ge 2 ] || die "--expect-write requires skip, allowed, or blocked"
      expect_write="$2"
      shift 2
      ;;
    --proxy)
      [ "$#" -ge 2 ] || die "--proxy requires a URL"
      proxy_url="$2"
      shift 2
      ;;
    --api-base)
      [ "$#" -ge 2 ] || die "--api-base requires a URL"
      api_base="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "unknown argument: $1"
      ;;
  esac
done

if [ -z "$allowed_repo" ]; then
  allowed_repo="$(infer_repo_from_origin || true)"
fi

[ -n "$allowed_repo" ] || die "set --allowed OWNER/REPO or GITHUB_ALLOWED_REPO"
validate_repo "allowed repo" "$allowed_repo"
validate_repo "blocked repo" "$blocked_repo"

if [ "$allowed_repo" = "$blocked_repo" ]; then
  die "allowed and blocked repos must be different"
fi

case "$expect_write" in
  skip|allowed|blocked) ;;
  *) die "--expect-write must be skip, allowed, or blocked" ;;
esac

command -v curl >/dev/null || die "curl is required"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

last_headers=""
last_body=""
last_status=""
last_curl_exit=0

run_request() {
  local method="$1"
  local path="$2"
  local data="${3:-}"
  local name_safe
  name_safe="$(printf '%s_%s' "$method" "$path" | tr -c 'A-Za-z0-9_' '_')"
  last_headers="$tmpdir/$name_safe.headers"
  last_body="$tmpdir/$name_safe.body"

  local curl_args=(
    --silent
    --show-error
    --connect-timeout 10
    --max-time 30
    --request "$method"
    --dump-header "$last_headers"
    --output "$last_body"
    --write-out "%{http_code}"
    --header "Accept: application/vnd.github+json"
    --header "X-GitHub-Api-Version: 2022-11-28"
  )

  if [ -n "${GITHUB_TOKEN:-}" ]; then
    curl_args+=(--header "Authorization: Bearer ${GITHUB_TOKEN}")
  fi

  if [ -n "$proxy_url" ]; then
    curl_args+=(--proxy "$proxy_url")
  fi

  if [ -n "$data" ]; then
    curl_args+=(--header "Content-Type: application/json" --data "$data")
  fi

  set +e
  last_status="$(curl "${curl_args[@]}" "${api_base}${path}")"
  last_curl_exit=$?
  set -e
}

is_proxy_block() {
  grep -qi 'Blocked by proxy policy:' "$last_body"
}

is_github_response() {
  grep -qi '^x-github-request-id:' "$last_headers" \
    || grep -qi '^server: GitHub\.com' "$last_headers"
}

pass() {
  printf 'ok: %s\n' "$*"
}

fail_current() {
  local message="$1"
  printf 'FAIL: %s\n' "$message" >&2
  printf '  curl_exit=%s http_status=%s\n' "$last_curl_exit" "$last_status" >&2
  printf '  response body:\n' >&2
  print_snippet "$last_body" >&2
  exit 1
}

expect_github_passthrough() {
  local label="$1"
  local method="$2"
  local path="$3"
  local data="${4:-}"

  run_request "$method" "$path" "$data"
  if [ "$last_curl_exit" -ne 0 ]; then
    fail_current "$label: curl failed"
  fi
  if is_proxy_block; then
    fail_current "$label: expected GitHub passthrough, got proxy block"
  fi
  if ! is_github_response; then
    fail_current "$label: expected GitHub response headers, got unknown response"
  fi
  pass "$label passed through to GitHub (HTTP $last_status)"
}

expect_proxy_block() {
  local label="$1"
  local method="$2"
  local path="$3"
  local data="${4:-}"

  run_request "$method" "$path" "$data"
  if [ "$last_curl_exit" -ne 0 ]; then
    fail_current "$label: curl failed"
  fi
  if ! is_proxy_block; then
    fail_current "$label: expected proxy block"
  fi
  pass "$label was blocked by proxy (HTTP $last_status)"
}

printf 'Testing GitHub API policy\n'
printf '  allowed repo: %s\n' "$allowed_repo"
printf '  blocked repo: %s\n' "$blocked_repo"
printf '  api base:     %s\n' "$api_base"
if [ -n "$proxy_url" ]; then
  printf '  proxy:        %s\n' "$proxy_url"
else
  printf '  proxy:        none from environment or flags\n'
fi
printf '\n'

expect_github_passthrough \
  "allowed repo root" \
  GET \
  "/repos/${allowed_repo}"

expect_github_passthrough \
  "allowed repo subtree" \
  GET \
  "/repos/${allowed_repo}/issues?per_page=1"

expect_proxy_block \
  "blocked repo root" \
  GET \
  "/repos/${blocked_repo}"

expect_proxy_block \
  "blocked repo subtree" \
  GET \
  "/repos/${blocked_repo}/issues?per_page=1"

expect_proxy_block \
  "non-repo GitHub API endpoint" \
  GET \
  "/user"

case "$expect_write" in
  allowed)
    expect_github_passthrough \
      "allowed repo write method" \
      POST \
      "/repos/${allowed_repo}/issues" \
      '{}'
    ;;
  blocked)
    expect_proxy_block \
      "allowed repo write method" \
      POST \
      "/repos/${allowed_repo}/issues" \
      '{}'
    ;;
  skip)
    pass "write-method check skipped"
    ;;
esac

printf '\nPASS: GitHub API policy behaved as expected\n'
