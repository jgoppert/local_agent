#!/usr/bin/env bash
# Keep tools on the caller's machine and forward only model API traffic over SSH.
set -euo pipefail
repo_dir="$(dirname "$(dirname "$(readlink -f "$0")")")"
source "$repo_dir/scripts/compat-env.sh"
host="${1:?Usage: remote-chat.sh USER@HOST [OpenCode args]}"
shift
if [[ "$host" == -* || "$host" == *[[:space:]]* ]]; then
  printf 'Invalid SSH host: %s. Use USER@HOST or an SSH config alias.\n' "$host" >&2
  exit 2
fi
remote_dir="${LOCAL_AGENT_REMOTE_DIR:-}"
remote_port="${PORT:-8080}"
local_port="${LOCAL_AGENT_LOCAL_PORT:-18080}"

# SSH joins remote arguments into shell text; quote every value for that shell.
shell_quote() { local value=${1//\'/\'\\\'\'}; printf "'%s'" "$value"; }
# Leave port, user, identity, and jump host to the normal SSH configuration.
ssh_args=(-o ConnectTimeout=10 -o ServerAliveInterval=15 -o ServerAliveCountMax=3)
remote_control() {
  # A login shell loads the remote user's profile, including Nix's user PATH.
  local command='bash -l -s --' value
  for value in "$remote_dir" "$remote_port" "${CTX:-}" "${REASONING:-}" "${LOCAL_AGENT_MODEL:-}" "$1"; do
    command+=" $(shell_quote "$value")"
  done
  ssh "${ssh_args[@]}" -T -- "$host" "$command" <<'REMOTE'
set -euo pipefail
export PORT="$2" CTX="$3" REASONING="$4" LOCAL_AGENT_MODEL="$5" LOCAL_AGENT_HOST=''
# Support hosts that still expose the previous launcher name and environment.
export QWEN_MODEL="$5" QWEN_HOST=''
repo=$1
if [[ -z "$repo" ]]; then
  if ! agent_command=$(type -P local_agent) && ! agent_command=$(type -P qwen); then
    printf 'local_agent is not on the remote login PATH (nor the legacy qwen command). Run scripts/install-profile.sh on the model host, or pass --remote-dir /path/to/local_agent.\n' >&2
    exit 127
  fi
else
  case "$repo" in
    '~/'*) repo="$HOME/${repo:2}" ;;
    /*) ;;
    *) repo="$HOME/$repo" ;;
  esac
  if [[ ! -x "$repo/chat.sh" ]]; then
    printf 'No local_agent checkout at %s on %s. Clone it there or set --remote-dir.\n' "$repo" "$(hostname)" >&2
    exit 1
  fi
  agent_command="$repo/chat.sh"
fi
if [[ "$6" == chat ]]; then
  "$agent_command" load >&2
  exec "$agent_command" --print-client-config
fi
exec "$agent_command" "$6"
REMOTE
}

case "${1:-}" in
  --list-models) remote_control --list-models; exit ;;
  load|start) remote_control load; exit ;;
  shutdown|stop|unload) remote_control shutdown; exit ;;
esac

# A private control socket owns exactly this session's tunnel. An occupied port
# is an error even if another local model happens to be healthy on that port.
tunnel_dir=$(mktemp -d /tmp/local_agent-ssh.XXXXXXXX)
socket="$tunnel_dir/control"
cleanup() {
  ssh -S "$socket" -O exit -- "$host" >/dev/null 2>&1 || true
  rm -rf -- "$tunnel_dir"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP
printf 'Connecting to local_agent on %s; tools will run in %s on this machine.\n' "$host" "$PWD" >&2
ssh "${ssh_args[@]}" -M -S "$socket" -o ControlPersist=no \
  -o ExitOnForwardFailure=yes -fNT \
  -L "127.0.0.1:$local_port:127.0.0.1:$remote_port" -- "$host"
ssh_args+=(-S "$socket" -o ControlMaster=no)
OPENCODE_CONFIG_CONTENT=$(remote_control chat)
export OPENCODE_CONFIG_CONTENT
if ! curl --silent --show-error --fail --max-time 5 "http://127.0.0.1:$local_port/health" >/dev/null; then
  printf 'The model is not reachable through the SSH tunnel on port %s.\n' "$local_port" >&2
  exit 1
fi
export PORT="$local_port"
# Do not exec: the EXIT trap closes the tunnel after the client exits.
"$repo_dir/.opencode-runtime/bin/opencode" "$@"
