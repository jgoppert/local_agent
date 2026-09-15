#!/usr/bin/env bash
# Accept the previous public environment names; an explicitly set new name wins.
local_agent_compat_env() {
  local suffix current legacy
  for suffix in HOST REMOTE_DIR LOCAL_PORT CONFIG MODEL NIX_PROFILE; do
    current="LOCAL_AGENT_$suffix"
    legacy="QWEN_$suffix"
    if [[ ! -v "$current" && -v "$legacy" ]]; then
      export "$current=${!legacy}"
    fi
    # Prevent a later Nix fallback from reviving a value explicitly cleared above.
    unset "$legacy"
  done
}
local_agent_compat_env
unset -f local_agent_compat_env
