#!/usr/bin/env bash
# Isolated integration checks: no GPU, network, real services, or model download.
set -euo pipefail
source_dir="$(dirname "$(dirname "$(readlink -f "$0")")")"
test_dir=$(mktemp -d)
trap 'rm -rf -- "$test_dir"' EXIT
export CASE_DIR="$test_dir"
mkdir -p "$test_dir/repo" "$test_dir/bin" "$test_dir/remote-bin" "$test_dir/project"
# Remote discovery must never fall through to commands installed on the test host.
ln -s "$(command -v bash)" "$test_dir/remote-bin/bash"
ln -s "$(command -v hostname)" "$test_dir/remote-bin/hostname"
cp -r "$source_dir/scripts" "$source_dir/nix" "$test_dir/repo/"
cp "$source_dir/chat.sh" "$source_dir/opencode.json" "$source_dir/config.toml" "$source_dir/models.toml" "$source_dir/.gitignore" "$test_dir/repo/"
LOCAL_AGENT_TEST_NIX=$(command -v nix)
export LOCAL_AGENT_TEST_NIX
export PATH="$test_dir/bin:$PATH"
unset LOCAL_AGENT_HOST LOCAL_AGENT_REMOTE_DIR LOCAL_AGENT_LOCAL_PORT LOCAL_AGENT_NIX_PROFILE LOCAL_AGENT_CONFIG LOCAL_AGENT_MODEL CTX REASONING PORT
unset QWEN_HOST QWEN_REMOTE_DIR QWEN_LOCAL_PORT QWEN_NIX_PROFILE QWEN_CONFIG QWEN_MODEL

cat >"$test_dir/bin/nix" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"$CASE_DIR/nix.log"
if [[ "$1" == eval ]]; then
  if [[ "$*" == *llama-cpp.nix* ]]; then
    printf '%s\n' "${MOCK_SERVER_PATH:-$PWD/llama-cpp}"
  else
    # Use the real TOML parser/validation; these expressions do not access the network.
    exec "$LOCAL_AGENT_TEST_NIX" "$@"
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
      printf 'Name: local_agent-tools\n' >"$CASE_DIR/profile.list"
      ;;
    *) exit 98 ;;
  esac
  exit 0
fi
while [[ "$1" != --out-link ]]; do shift; done
mkdir -p "$2/bin"
if [[ "$2" == .profile-runtime ]]; then
  cp "$CASE_DIR/bin/client" "$2/bin/local_agent"
  cp "$CASE_DIR/bin/client" "$2/bin/qwen"
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
printf '%s\n' "${OPENCODE_CONFIG_CONTENT:-}" >"$CASE_DIR/client-config.json"
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
if [[ "${*: -1}" == */v1/models ]]; then
  model="${MOCK_ACTIVE_MODEL:-models/Qwen3.8-27B-UD-Q4_K_M.gguf}"
  if [[ -z "${MOCK_ACTIVE_MODEL:-}" && -f "$CASE_DIR/active-model" ]]; then model=$(cat "$CASE_DIR/active-model"); fi
  printf '{"data":[{"id":"%s"}]}\n' "$model"
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
truncate -s "${MOCK_MODEL_SIZE:-16464440224}" "$2"
MOCK
cat >"$test_dir/bin/systemctl" <<'MOCK'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$CASE_DIR/systemctl.log"
service=''
for arg in "$@"; do case "$arg" in *.service) service="$arg" ;; esac; done
active() { [[ -f "$CASE_DIR/healthy" && -f "$CASE_DIR/active-service" && $(cat "$CASE_DIR/active-service") == "$service" ]]; }
case "$2" in
  show) if active; then echo loaded; else echo not-found; fi; exit ;;
  stop) if active; then rm -f "$CASE_DIR/healthy" "$CASE_DIR/active-model" "$CASE_DIR/active-service"; fi; exit ;;
esac
active
MOCK
cat >"$test_dir/bin/systemd-run" <<'MOCK'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$CASE_DIR/service.log"
for arg in "$@"; do
  case "$arg" in
    --setenv=LOCAL_AGENT_MODEL=*) printf '%s\n' "${arg#--setenv=LOCAL_AGENT_MODEL=}" >"$CASE_DIR/active-model" ;;
    --unit=*) printf '%s.service\n' "${arg#--unit=}" >"$CASE_DIR/active-service" ;;
  esac
done
touch "$CASE_DIR/healthy"
MOCK
cat >"$test_dir/bin/pgrep" <<'MOCK'
#!/usr/bin/env bash
exit 1
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
      printf 'export PATH=%q\n' "${MOCK_REMOTE_PATH:-$CASE_DIR/remote-bin}"
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
expect_failure 2 "$chat" --model
expect_failure 2 "$chat" --model=
expect_failure 2 "$chat" --model --host gpu-box
expect_failure 2 "$chat" --client
expect_failure 2 "$chat" --client=
expect_failure 2 "$chat" --client codex
contains "$test_dir/failure.log" '--client is no longer supported'
[[ ! -f "$test_dir/nix.log" && ! -f "$test_dir/ssh.log" ]] || fail 'Validation started a runtime or SSH connection'
"$chat" --list-models >"$test_dir/models.log"
contains "$test_dir/models.log" 'qwen3.8-27b (default)'
[[ ! -d "$test_dir/repo/models" && ! -d "$test_dir/repo/.opencode-runtime" ]] || fail 'Listing models installed weights or client'
expect_failure 1 "$chat" --model missing load
contains "$test_dir/failure.log" "unknown model 'missing'"
[[ ! -d "$test_dir/repo/llama-cpp" ]] || fail 'Unknown model installed server'

# Client-only setup installs commands on PATH without CUDA or model weights.
printf 'Name: qwen-tools\nName: codex-local_agent\nName: codex-qwen\n' >"$test_dir/profile.list"
"$test_dir/repo/scripts/setup.sh" --client >/dev/null
contains "$test_dir/nix.log" 'profile remove qwen-tools'
contains "$test_dir/nix.log" 'codex-local_agent codex-qwen'
contains "$test_dir/nix.log" opencode.nix
contains "$test_dir/nix.log" profile.nix
contains "$test_dir/nix.log" "profile add $test_dir/repo/.profile-runtime"
[[ ! -d "$test_dir/repo/models" && ! -d "$test_dir/repo/llama-cpp" ]] || fail 'Client installed a model'
"$test_dir/repo/scripts/setup.sh" --client >/dev/null
contains "$test_dir/nix.log" 'profile remove local_agent-tools'
[[ $(rg -c '^Name: local_agent-tools$' "$test_dir/profile.list") == 1 ]] || fail 'Repeated setup duplicated profile commands'
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
contains "$test_dir/client-config.json" '"model":"local_agent/qwen3.8-27b"'
contains "$test_dir/service.log" '--setenv=LOCAL_AGENT_MODEL=qwen3.8-27b'
contains "$test_dir/service.log" '--unit=local_agent-model'

# Runtime defaults preserve the 3090 preset; TOML overrides work without a GPU.
arg_value() { awk -v flag="$1" '$0 == flag {getline; print; exit}' "$test_dir/client.log"; }
"$test_dir/repo/scripts/run.sh"
[[ $(arg_value -ngl) == all && $(arg_value -c) == 32768 && $(arg_value --threads) == 8 && $(arg_value --spec-type) == draft-mtp ]] || fail 'Changed default hardware preset'
[[ $(arg_value --alias) == qwen3.8-27b ]] || fail 'Server is missing model alias'
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
env LOCAL_AGENT_CONFIG="$test_dir/override.toml" "$test_dir/repo/scripts/run.sh"
[[ $(arg_value -ngl) == 12 && $(arg_value -c) == 32768 ]] || fail 'Explicit config did not replace local overrides'
env QWEN_CONFIG="$test_dir/override.toml" "$test_dir/repo/scripts/run.sh"
[[ $(arg_value -ngl) == 12 ]] || fail 'Legacy config environment was lost'
env QWEN_CONFIG="$test_dir/missing.toml" LOCAL_AGENT_CONFIG="$test_dir/override.toml" "$test_dir/repo/scripts/run.sh"
[[ $(arg_value -ngl) == 12 ]] || fail 'New config environment did not take precedence'
builds=$(rg -c '^build .*llama-cpp.nix' "$test_dir/nix.log")
env MOCK_SERVER_PATH=/different-runtime "$test_dir/repo/scripts/ensure-runtime.sh" server
[[ $(rg -c '^build .*llama-cpp.nix' "$test_dir/nix.log") == $((builds + 1)) ]] || fail 'Changed server build reused a stale runtime'
printf '[hardware]\nbackend = "invalid"\n' >"$test_dir/repo/config.local.toml"
expect_failure 1 "$test_dir/repo/scripts/run.sh"
contains "$test_dir/failure.log" 'hardware.backend must be'
printf '[server]\nthreadz = 2\n' >"$test_dir/repo/config.local.toml"
expect_failure 1 "$test_dir/repo/scripts/run.sh"
contains "$test_dir/failure.log" 'unknown section/key'
expect_failure 1 env LOCAL_AGENT_CONFIG="$test_dir/missing.toml" "$test_dir/repo/scripts/run.sh"
contains "$test_dir/failure.log" 'LOCAL_AGENT_CONFIG does not exist'
printf '[power]\nwatts = 0\n' >"$test_dir/repo/config.local.toml"
"$test_dir/repo/scripts/powercap.sh" >"$test_dir/power.log"
contains "$test_dir/power.log" 'no GPU settings changed'
rm "$test_dir/repo/config.local.toml"

# Add a second model using data only; exercise selection through every local path.
cat >>"$test_dir/repo/models.toml" <<'CONFIG'

[tiny-test]
name = "Tiny test model"
file = "tiny-test.gguf"
url = "https://example.invalid/tiny-test.gguf"
size = 64
[tiny-test.server]
context = 8192
max_tokens = 1024
parallel = 2
CONFIG
"$chat" --list-models >"$test_dir/models.log"
contains "$test_dir/models.log" tiny-test
expect_failure 1 "$chat" --model tiny-test load
contains "$test_dir/failure.log" 'not serving tiny-test'
[[ ! -e "$test_dir/repo/models/tiny-test.gguf" ]] || fail 'Model mismatch downloaded weights'
"$chat" shutdown >/dev/null
env MOCK_MODEL_SIZE=64 LOCAL_AGENT_MODEL=qwen3.8-27b "$chat" --model=tiny-test load
contains "$test_dir/service.log" '--setenv=LOCAL_AGENT_MODEL=tiny-test'
[[ $(stat -c %s "$test_dir/repo/models/tiny-test.gguf") == 64 ]] || fail 'Wrong selected download size'
contains "$test_dir/curl.log" 'https://example.invalid/tiny-test.gguf'
"$chat" -m tiny-test run 'selected model task'
contains "$test_dir/client-config.json" '"model":"local_agent/tiny-test"'
contains "$test_dir/client-config.json" '"small_model":"local_agent/tiny-test"'
contains "$test_dir/client-config.json" '"context":4096,"output":1024'
"$test_dir/repo/scripts/run.sh" --model tiny-test -- --verbose
[[ $(arg_value -m) == models/tiny-test.gguf && $(arg_value --alias) == tiny-test && $(arg_value -c) == 8192 && $(arg_value --spec-type) == none ]] || fail 'Selected model did not reach server, or inherited Qwen MTP'
contains "$test_dir/client.log" --verbose
env LOCAL_AGENT_MODEL=tiny-test "$chat" run 'env-selected task'
contains "$test_dir/client-config.json" '"model":"local_agent/tiny-test"'
expect_failure 7 env MOCK_CLIENT_EXIT=7 "$chat" --model tiny-test run 'failing client'
env QWEN_MODEL=tiny-test "$chat" run 'legacy model environment'
contains "$test_dir/client-config.json" '"model":"local_agent/tiny-test"'
env QWEN_MODEL=missing LOCAL_AGENT_MODEL=tiny-test "$chat" --print-client-config >"$test_dir/config.json"
contains "$test_dir/config.json" '"model":"local_agent/tiny-test"'
env QWEN_CONFIG="$test_dir/missing.toml" LOCAL_AGENT_CONFIG='' "$chat" --print-client-config >"$test_dir/config.json"
contains "$test_dir/config.json" '"model":"local_agent/qwen3.8-27b"'

# Local model additions/defaults and inference overrides update the client.
cat >"$test_dir/repo/config.local.toml" <<'CONFIG'
[model]
default = "private-test"
[server]
context = 4096
[models.private-test]
name = "Private test"
file = "private.gguf"
url = "https://example.invalid/private.gguf?download=true&version=1"
size = 32
[models.private-test.server]
context = 16384
max_tokens = 512
CONFIG
"$chat" --list-models >"$test_dir/models.log"
contains "$test_dir/models.log" 'private-test (default)'
"$chat" --print-client-config >"$test_dir/config.json"
contains "$test_dir/config.json" '"model":"local_agent/private-test"'
contains "$test_dir/config.json" '"context":4096,"output":512'
env CTX=2048 "$chat" --print-client-config >"$test_dir/config.json"
contains "$test_dir/config.json" '"context":2048,"output":512'
"$chat" --model tiny-test --print-client-config >"$test_dir/config.json"
contains "$test_dir/config.json" '"model":"local_agent/tiny-test"'
printf '[models.tiny-test]\nfile = "../escape.gguf"\n' >"$test_dir/repo/config.local.toml"
expect_failure 1 "$test_dir/repo/scripts/download-model.sh" --model tiny-test
contains "$test_dir/failure.log" 'invalid model entry'
printf '[models.tiny-test]\nsize = 0\n' >"$test_dir/repo/config.local.toml"
expect_failure 1 "$test_dir/repo/scripts/run.sh" --model tiny-test
contains "$test_dir/failure.log" 'invalid model entry'
rm "$test_dir/repo/config.local.toml"
"$chat" shutdown >/dev/null
"$chat" load >/dev/null
# Rename migration reuses and shuts down a service started under the old name.
printf 'qwen-model.service\n' >"$test_dir/active-service"
starts=$(wc -l <"$test_dir/service.log")
"$chat" load >/dev/null
[[ $(wc -l <"$test_dir/service.log") == "$starts" ]] || fail 'Rename started a second model service'
"$chat" shutdown >/dev/null
contains "$test_dir/systemctl.log" 'stop qwen-model.service'
[[ ! -f "$test_dir/healthy" ]] || fail 'Legacy service survived shutdown'
"$chat" load >/dev/null

# Execute the actual remote bootstrap body against a fixture with shell metacharacters.
# If quoting fails this creates an INJECTED file, which is checked below.
remote="$test_dir/remote ' \$(touch INJECTED)"
mkdir -p "$remote"
cat >"$remote/chat.sh" <<'MOCK'
#!/usr/bin/env bash
if [[ "$1" == --print-client-config ]]; then
  printf '{"model":"local_agent/%s","small_model":"local_agent/%s"}\n' "${LOCAL_AGENT_MODEL:-remote-default}" "${LOCAL_AGENT_MODEL:-remote-default}"
  exit
fi
if [[ "$1" == --list-models ]]; then
  printf 'remote-only\tRemote model\n'
  exit
fi
printf '%s\n' "$1" "$PORT" "$CTX" "$REASONING" "$LOCAL_AGENT_HOST" "${LOCAL_AGENT_MODEL:-}" >"$CASE_DIR/remote.log"
printf '%s\n' "$0" >"$CASE_DIR/remote-source.log"
exit "${MOCK_REMOTE_EXIT:-0}"
MOCK
chmod +x "$remote/chat.sh"
rm -rf "$test_dir/repo/models" "$test_dir/repo/llama-cpp"
export LOCAL_AGENT_REMOTE_DIR="$remote"
"$chat" --host gpu-box --local-port 18081 run 'read local files'
contains "$test_dir/ssh.log" '127.0.0.1:18081:127.0.0.1:8080'
contains "$test_dir/ssh.log" 'ExitOnForwardFailure=yes'
[[ -f "$test_dir/closed" && ! -e INJECTED ]] || fail 'Tunnel cleanup or shell quoting failed'
mapfile -t client <"$test_dir/client.log"
[[ "${client[0]}" == "$PWD" && "${client[1]}" == 18081 && "${client[4]}" == 'read local files' ]] || fail 'Remote mode lost local cwd, forwarded port, or arguments'
[[ ! -d "$test_dir/repo/models" && ! -d "$test_dir/repo/llama-cpp" ]] || fail 'SSH client installed a model'
mapfile -t remote_args <"$test_dir/remote.log"
[[ "${remote_args[0]}" == load && "${remote_args[1]}" == 8080 && -z "${remote_args[2]}" && -z "${remote_args[3]}" && -z "${remote_args[4]}" ]] || fail 'Remote load overrode host config defaults'
contains "$test_dir/client-config.json" '"model":"local_agent/remote-default"'
"$chat" --model remote-only --host gpu-box run 'remote model task'
mapfile -t remote_args <"$test_dir/remote.log"
[[ "${remote_args[5]}" == remote-only ]] || fail 'SSH lost selected model'
contains "$test_dir/client-config.json" '"model":"local_agent/remote-only"'
contains "$test_dir/client.log" 'remote model task'
"$chat" --list-models --host gpu-box >"$test_dir/models.log"
contains "$test_dir/models.log" remote-only
# Model names are data even when the host will reject them as unknown.
"$chat" --host gpu-box --model "bad '\$(touch INJECTED)" load
[[ ! -e INJECTED ]] || fail 'Model name executed shell code over SSH'

# Default discovery uses remote PATH; explicit checkout overrides take priority.
cp "$remote/chat.sh" "$test_dir/remote-bin/qwen"
env LOCAL_AGENT_REMOTE_DIR='' "$chat" --host gpu-box load
[[ $(cat "$test_dir/remote-source.log") == "$test_dir/remote-bin/qwen" ]] || fail 'Legacy SSH command discovery failed'
cp "$remote/chat.sh" "$test_dir/remote-bin/local_agent"
env LOCAL_AGENT_REMOTE_DIR='' "$chat" --host gpu-box run 'use the PATH command'
[[ $(cat "$test_dir/remote-source.log") == "$test_dir/remote-bin/local_agent" ]] || fail 'Did not discover local_agent on PATH'
contains "$test_dir/client.log" 'use the PATH command'
env LOCAL_AGENT_REMOTE_DIR='' PORT=8089 CTX=16384 REASONING=high "$chat" --host gpu-box load
mapfile -t remote_args <"$test_dir/remote.log"
[[ "${remote_args[0]}" == load && "${remote_args[1]}" == 8089 && "${remote_args[2]}" == 16384 && "${remote_args[3]}" == high && -z "${remote_args[4]}" ]] || fail 'PATH launch lost server settings'
env LOCAL_AGENT_REMOTE_DIR='' "$chat" --host gpu-box shutdown
contains "$test_dir/remote.log" shutdown
"$chat" --host gpu-box --remote-dir "$remote" load
[[ $(cat "$test_dir/remote-source.log") == "$remote/chat.sh" ]] || fail 'Explicit checkout did not override PATH'
mkdir "$test_dir/no-local_agent"
expect_failure 127 env LOCAL_AGENT_REMOTE_DIR='' MOCK_REMOTE_PATH="$test_dir/no-local_agent" "$chat" --host gpu-box load
contains "$test_dir/failure.log" 'local_agent is not on the remote login PATH'
expect_failure 1 "$chat" --host gpu-box --remote-dir "$test_dir/missing" load
contains "$test_dir/failure.log" 'No local_agent checkout'

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
env LOCAL_AGENT_HOST=gpu-box "$chat" shutdown
contains "$test_dir/remote.log" shutdown
env QWEN_HOST=gpu-box "$chat" shutdown
contains "$test_dir/remote.log" shutdown
[[ ! -d "$test_dir/repo/.opencode-runtime" ]] || fail 'Remote shutdown installed client'
expect_failure 2 "$chat" --host '-oProxyCommand=bad'

# Git's actual ignore machinery must exclude weights while keeping source files.
git -C "$test_dir/repo" init -q
git -C "$test_dir/repo" check-ignore models/test.gguf weights.gguf weights.gguf.part weights.safetensors result-2 config.local.toml >/dev/null
if git -C "$test_dir/repo" check-ignore chat.sh opencode.json >/dev/null; then fail 'Ignored source'; fi
printf 'All launcher integration checks passed.\n'
