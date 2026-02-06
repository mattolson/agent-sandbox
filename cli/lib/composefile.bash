#!/usr/bin/env bash

# shellcheck source=require.bash
source "$AGB_LIBDIR/require.bash"
# shellcheck source=select.bash
source "$AGB_LIBDIR/select.bash"
# shellcheck source=path.bash
source "$AGB_LIBDIR/path.bash"
# shellcheck source=logging.bash
source "$AGB_LIBDIR/logging.bash"

# Customizes a Docker Compose file with policy and optional user configurations.
# Prompts the user for:
#   - Docker images for proxy and agent (pulls and pins to digest)
#   - Optional host Claude config mount
#   - Optional shell customizations and dotfiles
# Args:
#   $1 - The agent name (e.g., "claude")
#   $2 - Path to the policy file to mount, relative to the Docker Compose file directory
#   $3 - Path to the Docker Compose file to modify
#
customize_compose_file(){
  require yq

  local agent=$1
  local policy_file=$2
  local compose_file=$3

  local default_proxy_image="ghcr.io/mattolson/agent-sandbox-proxy:latest"
  local default_agent_image="ghcr.io/mattolson/agent-sandbox-$agent:latest"

  local compose_dir
  compose_dir=$(dirname "$compose_file")

  verify_relative_path "$compose_dir" "$policy_file"

  local proxy_image_input
  proxy_image_input=$(read_line "Proxy image [$default_proxy_image]:")

  local proxy_image
  proxy_image=$(pull_and_pin_image "${proxy_image_input:-$default_proxy_image}")
  proxy_image="$proxy_image" yq -i \
  	'.services.proxy.image = env(proxy_image)' "$compose_file"

  local agent_image_input
  agent_image_input=$(read_line "Agent image [$default_agent_image]:")

  local agent_image
  agent_image=$(pull_and_pin_image "${agent_image_input:-$default_agent_image}")
  agent_image="$agent_image" yq -i \
  	'.services.agent.image = env(agent_image)' "$compose_file"

  policy_file="$policy_file" yq -i \
    '.services.proxy.volumes += [env(policy_file) + ":/etc/mitmproxy/policy.yaml:ro"]' "$compose_file"

  if [[ $agent == "claude" ]]
  then
    if select_yes_no "Mount host Claude config (~/.claude)?"
    then
      # shellcheck disable=SC2016
      yq -i \
        '.services.agent.volumes += [
          "${HOME}/.claude/CLAUDE.md:/home/dev/.claude/CLAUDE.md:ro",
          "${HOME}/.claude/settings.json:/home/dev/.claude/settings.json:ro"
        ]' "$compose_file"
    fi
  fi

  if select_yes_no "Enable shell customizations?"
  then
    yq -i \
      '.services.agent.volumes += [
        env(AGB_HOME_PATTERN) + "/shell.d:/home/dev/.config/agent-sandbox/shell.d:ro"
      ]' "$compose_file"

    if select_yes_no "Enable dotfiles?"
    then
      # shellcheck disable=SC2016
      yq -i \
        '.services.agent.volumes += [
          "${HOME}/.dotfiles:/home/dev/.dotfiles:ro"
        ]' "$compose_file"
    fi
  fi
}

pull_and_pin_image() {
  local image=$1

  if [[ $image == *:local ]] || [[ $image != */* ]]; then
    echo "$image"
    return 0
  fi

  require docker

  # Pull remote image
  docker pull "$image" >&2

  # Get the digest
  local digest
  digest=$(docker inspect --format='{{index .RepoDigests 0}}' "$image")

  echo "$digest"
}
