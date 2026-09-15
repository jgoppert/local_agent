#!/usr/bin/env bash
# Source and call this only for leading wrapper options, before client arguments.
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/compat-env.sh"
local_agent_model_option() {
  case "$1" in
    --model|-m)
      if (( $# < 2 )) || [[ -z "$2" || "$2" == -* ]]; then
        printf '%s needs a model name.\n' "$1" >&2; return 2
      fi
      export LOCAL_AGENT_MODEL="$2"
      LOCAL_AGENT_MODEL_SHIFT=2
      ;;
    --model=*)
      export LOCAL_AGENT_MODEL="${1#*=}"
      [[ -n "$LOCAL_AGENT_MODEL" ]] || { printf '%s needs a model name.\n' --model >&2; return 2; }
      LOCAL_AGENT_MODEL_SHIFT=1
      ;;
    --list-models)
      nix eval --impure --raw --file "$(dirname "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")")/nix/model-list.nix"
      exit
      ;;
  esac
}
