#!/usr/bin/env bash
# Source this helper to load validated LOCAL_AGENT_CFG_* settings without evaluating shell code.
local_agent_read_config() {
  local root settings key value
  root="$(dirname "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")")"
  source "$root/scripts/compat-env.sh"
  settings=$(nix eval --impure --raw --file "$root/nix/runtime-config.nix") || return
  while IFS='=' read -r key value; do
    [[ "$key" == LOCAL_AGENT_CFG_* ]] || { printf 'Invalid config output.\n' >&2; return 1; }
    printf -v "$key" '%s' "$value"
  done <<< "$settings"
}
local_agent_read_config
unset -f local_agent_read_config
