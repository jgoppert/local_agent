#!/usr/bin/env bash
# Expose this checkout's launchers as qwen and codex-qwen (also called by setup).
set -euo pipefail
cd "$(dirname "$(dirname "$(readlink -f "$0")")")"

# Build first so a build failure leaves the existing installation usable.
nix build --impure --file ./nix/profile.nix --out-link .profile-runtime

# QWEN_NIX_PROFILE can select a separate profile, e.g. for testing installation.
profile_args=()
if [[ -n "${QWEN_NIX_PROFILE:-}" ]]; then
  profile_args=(--profile "$QWEN_NIX_PROFILE")
fi
profiles=$(nix profile list "${profile_args[@]}")
mapfile -t existing < <(
  printf '%s\n' "$profiles" |
    sed 's/\x1b\[[0-9;]*m//g' |
    awk '$1 == "Name:" && $2 ~ /^(qwen|codex-qwen|qwen-tools)(-[0-9]+)?$/ {print $2}'
)
if (( ${#existing[@]} )); then
  nix profile remove "${profile_args[@]}" "${existing[@]}"
fi
nix profile add "${profile_args[@]}" "$(readlink -f .profile-runtime)"
printf '\nInstalled qwen and codex-qwen. Run either from your project directory.\n'
