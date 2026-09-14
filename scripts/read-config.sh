#!/usr/bin/env bash
# Source this helper to load validated QWEN_CFG_* settings without evaluating shell code.
qwen_read_config() {
  local root settings key value
  root="$(dirname "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")")"
  settings=$(nix eval --impure --raw --file "$root/nix/runtime-config.nix") || return
  while IFS='=' read -r key value; do
    [[ "$key" == QWEN_CFG_* ]] || { printf 'Invalid config output.\n' >&2; return 1; }
    printf -v "$key" '%s' "$value"
  done <<< "$settings"
}
qwen_read_config
unset -f qwen_read_config
