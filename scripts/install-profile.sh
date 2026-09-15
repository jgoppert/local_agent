#!/usr/bin/env bash
# Install local_agent and compatibility aliases (also called by setup).
set -euo pipefail
cd "$(dirname "$(dirname "$(readlink -f "$0")")")"
source ./scripts/compat-env.sh

# Build first so a build failure leaves the existing installation usable.
nix build --impure --file ./nix/profile.nix --out-link .profile-runtime

# LOCAL_AGENT_NIX_PROFILE can select a separate profile, e.g. for testing installation.
profile_args=()
if [[ -n "${LOCAL_AGENT_NIX_PROFILE:-}" ]]; then
  profile_args=(--profile "$LOCAL_AGENT_NIX_PROFILE")
fi
profiles=$(nix profile list "${profile_args[@]}")
# Remove standalone entries from older installations as well as the current bundle.
mapfile -t existing < <(
  printf '%s\n' "$profiles" |
    sed 's/\x1b\[[0-9;]*m//g' |
    awk '$1 == "Name:" && $2 ~ /^(local_agent|codex-local_agent|local_agent-tools|qwen|codex-qwen|qwen-tools)(-[0-9]+)?$/ {print $2}'
)
if (( ${#existing[@]} )); then
  nix profile remove "${profile_args[@]}" "${existing[@]}"
fi
nix profile add "${profile_args[@]}" "$(readlink -f .profile-runtime)"
printf '\nInstalled local_agent. Run it from your project directory to open OpenCode.\n'
