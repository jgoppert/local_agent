#!/usr/bin/env bash
# Isolated integration checks: no GPU, network, real services, or model download.
set -euo pipefail
source_dir="$(dirname "$(dirname "$(readlink -f "$0")")")"
test_dir=$(mktemp -d)
trap 'rm -rf -- "$test_dir"' EXIT
export CASE_DIR="$test_dir"
mkdir -p "$test_dir/repo" "$test_dir/bin" "$test_dir/project"
cp -r "$source_dir/scripts" "$source_dir/nix" "$test_dir/repo/"
cp "$source_dir/chat.sh" "$source_dir/opencode.json" "$source_dir/config.toml" "$source_dir/.gitignore" "$test_dir/repo/"
QWEN_TEST_NIX=$(command -v nix)
export QWEN_TEST_NIX
export PATH="$test_dir/bin:$PATH"
unset QWEN_HOST QWEN_REMOTE_DIR QWEN_LOCAL_PORT QWEN_NIX_PROFILE QWEN_CONFIG CTX REASONING PORT

cat >"$test_dir/bin/nix" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"$CASE_DIR/nix.log"
if [[ "$1" == eval ]]; then
  if [[ "$*" == *llama-cpp.nix* ]]; then
    printf '%s\n' "${MOCK_SERVER_PATH:-$PWD/llama-cpp}"
  else
    # Use the real TOML parser/validation; these expressions do not access the network.
    exec "$QWEN_TEST_NIX" "$@"
  fi
  exit 0
fi
if [[ "$1" == profile ]]; then
  case "$2" in
    list)
      if [[ -f "$CASE_DIR/profile.list" ]]; then cat "$CASE_DIR/profile.list"; fi
      ;;
    remove) rm -f "$CASE_DIR/profile.list" ;;
    add)
      [[ "${MOCK_PROFILE_EXIT:-0}" == 0 ]] || exit "$MOCK_PROFILE_EXIT"
      printf 'Name: qwen-tools\n' >"$CASE_DIR/profile.list"
      ;;
    *) exit 98 ;;
  esac
  exit 0
fi
while [[ "$1" != --out-link ]]; do shift; done
mkdir -p "$2/bin"
if [[ "$2" == .profile-runtime ]]; then
  cp "$CASE_DIR/bin/client" "$2/bin/qwen"
  cp "$CASE_DIR/bin/client" "$2/bin/codex-qwen"
elif [[ "$2" == .opencode-runtime ]]; then
  cp "$CASE_DIR/bin/client" "$2/bin/opencode"
else
  cp "$CASE_DIR/bin/client" "$2/bin/llama-server"
fi
MOCK
cat >"$test_dir/bin/client" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$PWD" "${PORT:-}" "${OPENCODE_CONFIG:-}" "$@" >"$CASE_DIR/client.log"
exit "${MOCK_CLIENT_EXIT:-0}"
MOCK
cat >"$test_dir/bin/curl" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"$CASE_DIR/curl.log"
if [[ "${*: -1}" == */health ]]; then
  [[ -f "$CASE_DIR/healthy" ]]
  exit
fi
[[ "$*" == *'--fail --location --continue-at -'* ]]
while [[ "$1" != --output ]]; do shift; done
if [[ "${MOCK_DOWNLOAD:-}" == fail ]]; then
  printf 'partial' >"$2"
  exit 22
fi
if [[ "${MOCK_DOWNLOAD:-}" == short ]]; then
  printf 'short' >"$2"
  exit 0
fi
[[ ! -f "$2" ]] || printf 'resumed\n' >>"$CASE_DIR/resume.log"
truncate -s 16464440224 "$2"
MOCK
cat >"$test_dir/bin/systemctl" <<'MOCK'
#!/usr/bin/env bash
[[ -f "$CASE_DIR/healthy" ]]
MOCK
cat >"$test_dir/bin/systemd-run" <<'MOCK'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$CASE_DIR/service.log"
touch "$CASE_DIR/healthy"
MOCK
cat >"$test_dir/bin/ssh" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"$CASE_DIR/ssh.log"
case " $* " in
  *' -O exit '*) touch "$CASE_DIR/closed"; exit 0 ;;
  *' -fNT '*) exit "${MOCK_FORWARD_EXIT:-0}" ;;
  *' -T '*)
    remote_command="${*: -1}"
    [[ "$remote_command" == 'bash -l -s -- '* ]]
    # Simulate the login PATH without sourcing the test runner's real profiles.
    remote_body=$(cat)
    {
      printf 'export PATH=%q\n' "${MOCK_REMOTE_PATH:-$PATH}"
      printf '%s\n' "$remote_body"
    } | bash -c "${remote_command/#bash -l -s --/bash -s --}"
    ;;
  *) exit 98 ;;
esac
MOCK
chmod +x "$test_dir/bin/"*
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
contains() { rg -q -F -- "$2" "$1" || fail "$1 missing: $2"; }
expect_failure() {
  local status=0 expected=$1
  shift
  "$@" >"$test_dir/failure.log" 2>&1 || status=$?
  [[ "$status" == "$expected" ]] || fail "Expected exit $expected, got $status: $*"
}

cd "$test_dir/project"
chat="$test_dir/repo/chat.sh"
"$chat" --help >/dev/null
[[ ! -f "$test_dir/nix.log" ]] || fail 'Help installed a runtime'
expect_failure 2 "$chat" --host
expect_failure 2 "$chat" --local-port 0

# Client-only setup installs commands on PATH without CUDA or model weights.
"$test_dir/repo/scripts/setup.sh" --client >/dev/null
contains "$test_dir/nix.log" opencode.nix
contains "$test_dir/nix.log" profile.nix
contains "$test_dir/nix.log" "profile add $test_dir/repo/.profile-runtime"
[[ ! -d "$test_dir/repo/models" && ! -d "$test_dir/repo/llama-cpp" ]] || fail 'Client installed a model'
"$test_dir/repo/scripts/setup.sh" --client >/dev/null
contains "$test_dir/nix.log" 'profile remove qwen-tools'
[[ $(rg -c '^Name: qwen-tools$' "$test_dir/profile.list") == 1 ]] || fail 'Repeated setup duplicated profile commands'
expect_failure 23 env MOCK_PROFILE_EXIT=23 "$test_dir/repo/scripts/setup.sh" --client
if rg -q 'Client ready' "$test_dir/failure.log"; then fail 'Setup claimed success after profile installation failed'; fi

# HTTP errors and truncated files never become usable model files. Retry resumes.
expect_failure 22 env MOCK_DOWNLOAD=fail "$test_dir/repo/scripts/download-model.sh"
[[ -f "$test_dir/repo/models/Qwen3.8-27B-UD-Q4_K_M.gguf.part" ]] || fail 'Lost partial download'
[[ ! -f "$test_dir/repo/models/Qwen3.8-27B-UD-Q4_K_M.gguf" ]] || fail 'Published failed download'
expect_failure 1 env MOCK_DOWNLOAD=short "$test_dir/repo/scripts/download-model.sh"
contains "$test_dir/failure.log" 'size mismatch'
"$test_dir/repo/scripts/download-model.sh"
[[ -f "$test_dir/resume.log" ]] || fail 'Did not resume partial download'
[[ ! -f "$test_dir/repo/models/Qwen3.8-27B-UD-Q4_K_M.gguf.part" ]] || fail 'Partial not renamed'
calls=$(wc -l <"$test_dir/curl.log")
"$test_dir/repo/scripts/download-model.sh"
[[ $(wc -l <"$test_dir/curl.log") == "$calls" ]] || fail 'Redownloaded complete model'

# A fresh local launch bootstraps both runtimes and weights without changing cwd.
rm -rf "$test_dir/repo/.opencode-runtime" "$test_dir/repo/models"
"$chat" run 'read a file with spaces'
contains "$test_dir/nix.log" llama-cpp.nix
contains "$test_dir/service.log" "WorkingDirectory=$test_dir/repo"
mapfile -t client <"$test_dir/client.log"
[[ "${client[0]}" == "$PWD" && "${client[1]}" == 8080 && "${client[3]}" == run && "${client[4]}" == 'read a file with spaces' ]] || fail 'Lost cwd, port, or arguments'

# Runtime defaults preserve the 3090 preset; TOML overrides work without a GPU.
arg_value() { awk -v flag="$1" '$0 == flag {getline; print; exit}' "$test_dir/client.log"; }
"$test_dir/repo/scripts/run.sh"
[[ $(arg_value -ngl) == all && $(arg_value -c) == 32768 && $(arg_value --threads) == 8 && $(arg_value --spec-type) == draft-mtp ]] || fail 'Changed default hardware preset'
cat >"$test_dir/repo/config.local.toml" <<'CONFIG'
[hardware]
backend = "cpu"
[server]
context = 8192
threads = 4
flash_attention = "auto"
cache_type = "f16"
speculation = "none"
CONFIG
"$test_dir/repo/scripts/run.sh"
[[ $(arg_value -ngl) == 0 && $(arg_value -c) == 8192 && $(arg_value --threads) == 4 && $(arg_value -ctv) == f16 && $(arg_value --spec-type) == none ]] || fail 'CPU config did not reach the server'
env CTX=4096 REASONING=high "$test_dir/repo/scripts/run.sh"
[[ $(arg_value -c) == 4096 && $(arg_value --reasoning-effort) == high ]] || fail 'Environment no longer overrides TOML'
expect_failure 1 "$test_dir/repo/scripts/powercap.sh"
contains "$test_dir/failure.log" 'only to the CUDA/NVIDIA backend'
cat >"$test_dir/override.toml" <<'CONFIG'
[hardware]
backend = "vulkan"
[server]
gpu_layers = 12
CONFIG
env QWEN_CONFIG="$test_dir/override.toml" "$test_dir/repo/scripts/run.sh"
[[ $(arg_value -ngl) == 12 && $(arg_value -c) == 32768 ]] || fail 'Explicit config did not replace local overrides'
builds=$(rg -c '^build .*llama-cpp.nix' "$test_dir/nix.log")
env MOCK_SERVER_PATH=/different-runtime "$test_dir/repo/scripts/ensure-runtime.sh" server
[[ $(rg -c '^build .*llama-cpp.nix' "$test_dir/nix.log") == $((builds + 1)) ]] || fail 'Changed server build reused a stale runtime'
printf '[hardware]\nbackend = "invalid"\n' >"$test_dir/repo/config.local.toml"
expect_failure 1 "$test_dir/repo/scripts/run.sh"
contains "$test_dir/failure.log" 'hardware.backend must be'
printf '[server]\nthreadz = 2\n' >"$test_dir/repo/config.local.toml"
expect_failure 1 "$test_dir/repo/scripts/run.sh"
contains "$test_dir/failure.log" 'unknown section/key'
expect_failure 1 env QWEN_CONFIG="$test_dir/missing.toml" "$test_dir/repo/scripts/run.sh"
contains "$test_dir/failure.log" 'QWEN_CONFIG does not exist'
printf '[power]\nwatts = 0\n' >"$test_dir/repo/config.local.toml"
"$test_dir/repo/scripts/powercap.sh" >"$test_dir/power.log"
contains "$test_dir/power.log" 'no GPU settings changed'
rm "$test_dir/repo/config.local.toml"

# Execute the actual remote bootstrap body against a fixture with shell metacharacters.
# If quoting fails this creates an INJECTED file, which is checked below.
remote="$test_dir/remote ' \$(touch INJECTED)"
mkdir -p "$remote"
cat >"$remote/chat.sh" <<'MOCK'
#!/usr/bin/env bash
printf '%s\n' "$1" "$PORT" "$CTX" "$REASONING" "$QWEN_HOST" >"$CASE_DIR/remote.log"
printf '%s\n' "$0" >"$CASE_DIR/remote-source.log"
exit "${MOCK_REMOTE_EXIT:-0}"
MOCK
chmod +x "$remote/chat.sh"
rm -rf "$test_dir/repo/models" "$test_dir/repo/llama-cpp"
export QWEN_REMOTE_DIR="$remote"
"$chat" --host gpu-box --local-port 18081 run 'read local files'
contains "$test_dir/ssh.log" '127.0.0.1:18081:127.0.0.1:8080'
contains "$test_dir/ssh.log" 'ExitOnForwardFailure=yes'
[[ -f "$test_dir/closed" && ! -e INJECTED ]] || fail 'Tunnel cleanup or shell quoting failed'
mapfile -t client <"$test_dir/client.log"
[[ "${client[0]}" == "$PWD" && "${client[1]}" == 18081 && "${client[4]}" == 'read local files' ]] || fail 'Remote mode lost local cwd, forwarded port, or arguments'
[[ ! -d "$test_dir/repo/models" && ! -d "$test_dir/repo/llama-cpp" ]] || fail 'SSH client installed a model'
mapfile -t remote_args <"$test_dir/remote.log"
[[ "${remote_args[0]}" == load && "${remote_args[1]}" == 8080 && -z "${remote_args[2]}" && -z "${remote_args[3]}" && -z "${remote_args[4]}" ]] || fail 'Remote load overrode host config defaults'

# Default discovery uses remote PATH; explicit checkout overrides take priority.
cp "$remote/chat.sh" "$test_dir/bin/qwen"
env QWEN_REMOTE_DIR='' "$chat" --host gpu-box run 'use the PATH command'
[[ $(cat "$test_dir/remote-source.log") == "$test_dir/bin/qwen" ]] || fail 'Did not discover qwen on PATH'
contains "$test_dir/client.log" 'use the PATH command'
env QWEN_REMOTE_DIR='' PORT=8089 CTX=16384 REASONING=high "$chat" --host gpu-box load
mapfile -t remote_args <"$test_dir/remote.log"
[[ "${remote_args[0]}" == load && "${remote_args[1]}" == 8089 && "${remote_args[2]}" == 16384 && "${remote_args[3]}" == high && -z "${remote_args[4]}" ]] || fail 'PATH launch lost server settings'
env QWEN_REMOTE_DIR='' "$chat" --host gpu-box shutdown
contains "$test_dir/remote.log" shutdown
"$chat" --host gpu-box --remote-dir "$remote" load
[[ $(cat "$test_dir/remote-source.log") == "$remote/chat.sh" ]] || fail 'Explicit checkout did not override PATH'
mkdir "$test_dir/no-qwen"
expect_failure 127 env QWEN_REMOTE_DIR='' MOCK_REMOTE_PATH="$test_dir/no-qwen" "$chat" --host gpu-box load
contains "$test_dir/failure.log" 'qwen is not on the remote login PATH'
expect_failure 1 "$chat" --host gpu-box --remote-dir "$test_dir/missing" load
contains "$test_dir/failure.log" 'No Qwen checkout'

rm "$test_dir/closed"
expect_failure 7 env MOCK_CLIENT_EXIT=7 "$chat" --host gpu-box run test
[[ -f "$test_dir/closed" ]] || fail 'Client failure leaked tunnel'
rm "$test_dir/closed" "$test_dir/client.log"
expect_failure 255 env MOCK_FORWARD_EXIT=255 "$chat" --host gpu-box
[[ -f "$test_dir/closed" && ! -f "$test_dir/client.log" ]] || fail 'Forward failure launched client or leaked tunnel'
rm "$test_dir/closed"
expect_failure 9 env MOCK_REMOTE_EXIT=9 "$chat" --host gpu-box
[[ -f "$test_dir/closed" && ! -f "$test_dir/client.log" ]] || fail 'Remote failure launched client or leaked tunnel'
rm "$test_dir/healthy" "$test_dir/closed"
expect_failure 1 "$chat" --host gpu-box
[[ -f "$test_dir/closed" && ! -f "$test_dir/client.log" ]] || fail 'Unhealthy tunnel launched client or leaked tunnel'

# Model controls need no client runtime or tunnel; environment defaults work too.
rm -rf "$test_dir/repo/.opencode-runtime"
env QWEN_HOST=gpu-box "$chat" shutdown
contains "$test_dir/remote.log" shutdown
[[ ! -d "$test_dir/repo/.opencode-runtime" ]] || fail 'Remote shutdown installed client'
expect_failure 2 "$chat" --host '-oProxyCommand=bad'

# Git's actual ignore machinery must exclude weights while keeping source files.
git -C "$test_dir/repo" init -q
git -C "$test_dir/repo" check-ignore models/test.gguf weights.gguf weights.gguf.part weights.safetensors result-2 config.local.toml >/dev/null
if git -C "$test_dir/repo" check-ignore chat.sh opencode.json >/dev/null; then fail 'Ignored source'; fi
printf 'All launcher integration checks passed.\n'
