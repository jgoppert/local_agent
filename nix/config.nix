# Parse and validate data with Nix's TOML parser; no extra runtime dependency.
let
  defaults = builtins.fromTOML (builtins.readFile ../config.toml);
  selected = builtins.getEnv "QWEN_CONFIG";
  overridePath =
    if selected != "" then
      if builtins.substring 0 1 selected == "/" then selected
      else throw "QWEN_CONFIG must be an absolute path"
    else ../config.local.toml;
  overrides =
    if builtins.pathExists overridePath then builtins.fromTOML (builtins.readFile overridePath)
    else if selected != "" then throw "QWEN_CONFIG does not exist: ${selected}"
    else { };
  sections = [ "hardware" "server" "power" ];
  cfg = builtins.listToAttrs (map (name: {
    inherit name;
    value = defaults.${name} // (overrides.${name} or { });
  }) sections);
  check = condition: message: if condition then true else throw "Qwen config: ${message}";
  positive = value: builtins.isInt value && value > 0;
  knownKeys = source: builtins.all (section:
    builtins.elem section sections && builtins.isAttrs source.${section}
    && builtins.all (key: builtins.hasAttr key defaults.${section}) (builtins.attrNames source.${section})
  ) (builtins.attrNames source);
  checks = [
    (check (knownKeys overrides) "unknown section/key or invalid table")
    (check (builtins.elem cfg.hardware.backend [ "cuda" "vulkan" "cpu" ]) "hardware.backend must be cuda, vulkan, or cpu")
    (check (builtins.isList cfg.hardware.cuda_capabilities && cfg.hardware.cuda_capabilities != [ ]
      && builtins.all (cap: builtins.isString cap && builtins.match "[0-9]+[.][0-9]+" cap != null) cfg.hardware.cuda_capabilities)
      "hardware.cuda_capabilities must be a nonempty list of strings, e.g. [\"8.6\"]")
    (check ((builtins.isInt cfg.server.gpu_layers && cfg.server.gpu_layers >= 0)
      || builtins.elem cfg.server.gpu_layers [ "all" "auto" ]) "server.gpu_layers must be all, auto, or a nonnegative integer")
    (check (builtins.all (key: positive cfg.server.${key}) [ "context" "threads" "parallel" "draft_tokens" "max_tokens" ])
      "server context, threads, parallel, draft_tokens, and max_tokens must be positive integers")
    (check (builtins.elem cfg.server.flash_attention [ "on" "off" "auto" ]) "server.flash_attention must be on, off, or auto")
    (check (builtins.elem cfg.server.cache_type [ "f32" "f16" "bf16" "q8_0" "q4_0" "q4_1" "iq4_nl" "q5_0" "q5_1" ]) "unsupported server.cache_type")
    (check (builtins.elem cfg.server.reasoning [ "none" "low" "medium" "high" ]) "unsupported server.reasoning")
    (check (builtins.elem cfg.server.speculation [ "none" "draft-mtp" ]) "server.speculation must be none or draft-mtp")
    (check (builtins.isInt cfg.power.watts && cfg.power.watts >= 0) "power.watts must be a nonnegative integer")
  ];
in
builtins.deepSeq checks cfg
