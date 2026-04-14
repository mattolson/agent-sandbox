#!/bin/sh

path_prepend() {
  PATH="$1${PATH:+:$PATH}"
}

path_append() {
  PATH="${PATH:+$PATH:}$1"
}

path_dedupe() {
  _agentbox_old_path="$PATH"
  _agentbox_new_path=""

  while [ -n "$_agentbox_old_path" ]; do
    case "$_agentbox_old_path" in
      *:*)
        _agentbox_entry="${_agentbox_old_path%%:*}"
        _agentbox_old_path="${_agentbox_old_path#*:}"
        ;;
      *)
        _agentbox_entry="$_agentbox_old_path"
        _agentbox_old_path=""
        ;;
    esac

    [ -n "$_agentbox_entry" ] || continue
    case ":$_agentbox_new_path:" in
      *":$_agentbox_entry:"*) ;;
      *) _agentbox_new_path="${_agentbox_new_path:+$_agentbox_new_path:}$_agentbox_entry" ;;
    esac
  done

  PATH="$_agentbox_new_path"
  unset _agentbox_old_path _agentbox_new_path _agentbox_entry
}
