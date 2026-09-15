# Model settings are layered over opencode.json via OPENCODE_CONFIG_CONTENT.
# SSH clients obtain this from the host so its catalog and limits are authoritative.
let
  cfg = import ./config.nix;
  model = "local_agent/${cfg.modelId}";
in
builtins.toJSON {
  inherit model;
  small_model = model;
  provider.local_agent.models.${cfg.modelId} = {
    name = cfg.selectedModel.name;
    tool_call = true;
    limit = {
      context = builtins.div cfg.server.context cfg.server.parallel;
      output = cfg.server.max_tokens;
    };
  };
}
