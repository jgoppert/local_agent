# All values are validated scalars with no newlines; the shell reads data, not code.
let
  cfg = import ./config.nix;
  values = {
    QWEN_CFG_BACKEND = cfg.hardware.backend;
    QWEN_CFG_GPU_LAYERS = if cfg.hardware.backend == "cpu" then 0 else cfg.server.gpu_layers;
    QWEN_CFG_CONTEXT = cfg.server.context;
    QWEN_CFG_THREADS = cfg.server.threads;
    QWEN_CFG_PARALLEL = cfg.server.parallel;
    QWEN_CFG_FLASH_ATTENTION = cfg.server.flash_attention;
    QWEN_CFG_CACHE_TYPE = cfg.server.cache_type;
    QWEN_CFG_REASONING = cfg.server.reasoning;
    QWEN_CFG_SPECULATION = cfg.server.speculation;
    QWEN_CFG_DRAFT_TOKENS = cfg.server.draft_tokens;
    QWEN_CFG_MAX_TOKENS = cfg.server.max_tokens;
    QWEN_CFG_POWER_WATTS = cfg.power.watts;
  };
in
builtins.concatStringsSep "\n" (map (key: "${key}=${toString values.${key}}") (builtins.attrNames values))
