# Migrating an existing installation

The public command is `local_agent`, which launches OpenCode:

```bash
local_agent                  # OpenCode
```

Run `scripts/install-profile.sh` from the current checkout to refresh the
commands on PATH. It replaces previous profile entries with `local_agent-tools`.
The `qwen` command remains a compatibility alias. Earlier Codex launchers have
been removed; refreshing the profile removes their installed commands.

Use `LOCAL_AGENT_HOST`, `LOCAL_AGENT_MODEL`, `LOCAL_AGENT_CONFIG`,
`LOCAL_AGENT_REMOTE_DIR`, `LOCAL_AGENT_LOCAL_PORT`, and `LOCAL_AGENT_NIX_PROFILE`
for environment settings. Their `QWEN_*` equivalents remain accepted; the new
names take precedence. SSH discovery prefers `local_agent` and falls back to
`qwen` on hosts whose command installation has not yet been refreshed.

New model starts use `local_agent-model.service`. An existing
`qwen-model.service` can keep running; `local_agent shutdown` handles both
names. The default model ID and weight filenames are unchanged.

The installed commands point to the checkout. After moving it, rerun setup or
`scripts/install-profile.sh` from the new location.
