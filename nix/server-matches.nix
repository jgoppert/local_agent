# Accept the catalog alias and the filename used by pre-selection launchers.
let
  cfg = import ./config.nix;
  data = (builtins.fromJSON (builtins.getEnv "LOCAL_AGENT_SERVER_MODELS")).data or [ ];
in
builtins.any (model: builtins.elem (model.id or "") [
  cfg.modelId "models/${cfg.selectedModel.file}"
]) data
