# All values are validated scalars with no newlines; the shell reads data, not code.
let
  cfg = import ./config.nix;
  values = {
    LOCAL_AGENT_CFG_MODEL_ID = cfg.modelId;
    LOCAL_AGENT_CFG_MODEL_NAME = cfg.selectedModel.name;
    LOCAL_AGENT_CFG_MODEL_FILE = "models/${cfg.selectedModel.file}";
    LOCAL_AGENT_CFG_MODEL_URL = cfg.selectedModel.url;
    LOCAL_AGENT_CFG_MODEL_SIZE = cfg.selectedModel.size;
    LOCAL_AGENT_CFG_BACKEND = cfg.hardware.backend;
    LOCAL_AGENT_CFG_GPU_LAYERS = if cfg.hardware.backend == "cpu" then 0 else cfg.server.gpu_layers;
    LOCAL_AGENT_CFG_CONTEXT = cfg.server.context;
    LOCAL_AGENT_CFG_THREADS = cfg.server.threads;
    LOCAL_AGENT_CFG_PARALLEL = cfg.server.parallel;
    LOCAL_AGENT_CFG_FLASH_ATTENTION = cfg.server.flash_attention;
    LOCAL_AGENT_CFG_CACHE_TYPE = cfg.server.cache_type;
    LOCAL_AGENT_CFG_REASONING = cfg.server.reasoning;
    LOCAL_AGENT_CFG_SPECULATION = cfg.server.speculation;
    LOCAL_AGENT_CFG_DRAFT_TOKENS = cfg.server.draft_tokens;
    LOCAL_AGENT_CFG_MAX_TOKENS = cfg.server.max_tokens;
    LOCAL_AGENT_CFG_POWER_WATTS = cfg.power.watts;
  };
in
builtins.concatStringsSep "\n" (map (key: "${key}=${toString values.${key}}") (builtins.attrNames values))
