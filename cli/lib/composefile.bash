#!/usr/bin/env bash

# shellcheck source=require.bash
source "$AGB_LIBDIR/require.bash"
# shellcheck source=select.bash
source "$AGB_LIBDIR/select.bash"

# Customizes a Docker Compose file with policy and optional user configurations.
# Prompts the user to optionally mount host Claude config, shell customizations, and dotfiles.
# Args:
#   $1 - The agent name (e.g., "claude")
#   $2 - Path to the policy file to mount
#   $3 - Path to the Docker Compose file to modify
#
# TODO: images and image tags
#
customize_compose_file(){
  local agent=$1
  local policy_file=$2
  local compose_file=$3

  require yq

  # FIXME $policy_file is an absolute path, should be $HOME so that the file can be shared
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
    # FIXME $AGB_HOME is an absolute path, should be $HOME so that the file can be shared

    # shellcheck disable=SC2016
    yq -i \
      '.services.agent.volumes += [
        env(AGB_HOME) + "/shell.d:/home/dev/.config/agent-sandbox/shell.d:ro"
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
