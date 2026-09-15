# Parse and validate data with Nix's TOML parser; no extra runtime dependency.
let
  defaults = builtins.fromTOML (builtins.readFile ../config.toml);
  catalog = builtins.fromTOML (builtins.readFile ../models.toml);
  # Also support direct nix eval/build calls using the previous environment names.
  env = name: let value = builtins.getEnv "LOCAL_AGENT_${name}";
    in if value != "" then value else builtins.getEnv "QWEN_${name}";
  selected = env "CONFIG";
  overridePath =
    if selected != "" then
      if builtins.substring 0 1 selected == "/" then selected
      else throw "LOCAL_AGENT_CONFIG must be an absolute path"
    else ../config.local.toml;
  overrides =
    if builtins.pathExists overridePath then builtins.fromTOML (builtins.readFile overridePath)
    else if selected != "" then throw "LOCAL_AGENT_CONFIG does not exist: ${selected}"
    else { };
  sections = [ "model" "hardware" "server" "power" ];
  localModels = overrides.models or { };
  modelIds = builtins.attrNames (catalog // localModels);
  models = builtins.listToAttrs (map (name: {
    inherit name;
    value = (catalog.${name} or { }) // (localModels.${name} or { }) // {
      server = (catalog.${name}.server or { }) // (localModels.${name}.server or { });
    };
  }) modelIds);
  settings = builtins.listToAttrs (map (name: {
    inherit name;
    value = defaults.${name} // (overrides.${name} or { });
  }) sections);
  requested = env "MODEL";
  modelId = if requested != "" then requested else settings.model.default;
  model = models.${modelId} or (throw "local_agent config: unknown model '${modelId}'. Available models: ${builtins.concatStringsSep ", " modelIds}");
  context = builtins.getEnv "CTX";
  reasoning = builtins.getEnv "REASONING";
  cfg = settings // {
    inherit models modelId;
    selectedModel = model;
    server = defaults.server // model.server // (overrides.server or { })
      // (if context == "" then { } else {
        context = if builtins.match "[1-9][0-9]*" context != null then builtins.fromJSON context
          else throw "local_agent config: CTX must be a positive integer";
      })
      // (if reasoning == "" then { } else { inherit reasoning; });
  };
  check = condition: message: if condition then true else throw "local_agent config: ${message}";
  positive = value: builtins.isInt value && value > 0;
  knownKeys = source: builtins.all (section: if section == "models" then builtins.isAttrs source.models else
    builtins.elem section sections && builtins.isAttrs source.${section}
    && builtins.all (key: builtins.hasAttr key defaults.${section}) (builtins.attrNames source.${section})
  ) (builtins.attrNames source);
  line = value: builtins.isString value && value != "" && builtins.match "[^[:cntrl:]]+" value != null;
  validModel = id: let m = models.${id}; in
    builtins.match "[a-zA-Z0-9][a-zA-Z0-9._-]*" id != null
    && builtins.isAttrs m
    && builtins.all (key: builtins.elem key [ "name" "file" "url" "size" "server" ]) (builtins.attrNames m)
    && line (m.name or null)
    && builtins.isString (m.file or null) && builtins.match "[a-zA-Z0-9][a-zA-Z0-9._+-]*[.]gguf" m.file != null
    && builtins.isString (m.url or null) && builtins.match "https?://[^[:space:][:cntrl:]]+" m.url != null
    && positive (m.size or null)
    && builtins.isAttrs m.server
    && builtins.all (key: builtins.hasAttr key defaults.server) (builtins.attrNames m.server);
  checks = [
    (check (knownKeys overrides) "unknown section/key or invalid table")
    (check (builtins.all (id: builtins.isAttrs (catalog.${id} or { }) && builtins.isAttrs (localModels.${id} or { })) modelIds)
      "model entries must be tables")
    (check (builtins.all validModel modelIds) "invalid model entry: use a simple ID, name, GGUF filename, HTTP(S) URL, positive byte size, and known server keys")
    (check (builtins.isString settings.model.default && builtins.hasAttr settings.model.default models) "model.default must name a model in the catalog")
    (check (builtins.length (builtins.attrNames (builtins.listToAttrs (map (id: { name = models.${id}.file; value = true; }) modelIds))) == builtins.length modelIds)
      "model filenames must be unique")
    (check (builtins.elem cfg.hardware.backend [ "cuda" "vulkan" "cpu" ]) "hardware.backend must be cuda, vulkan, or cpu")
    (check (builtins.isList cfg.hardware.cuda_capabilities && cfg.hardware.cuda_capabilities != [ ]
      && builtins.all (cap: builtins.isString cap && builtins.match "[0-9]+[.][0-9]+" cap != null) cfg.hardware.cuda_capabilities)
      "hardware.cuda_capabilities must be a nonempty list of strings, e.g. [\"8.6\"]")
    (check ((builtins.isInt cfg.server.gpu_layers && cfg.server.gpu_layers >= 0)
      || builtins.elem cfg.server.gpu_layers [ "all" "auto" ]) "server.gpu_layers must be all, auto, or a nonnegative integer")
    (check (builtins.all (key: positive cfg.server.${key}) [ "context" "threads" "parallel" "draft_tokens" "max_tokens" ])
      "server context, threads, parallel, draft_tokens, and max_tokens must be positive integers")
    (check (cfg.server.context >= cfg.server.parallel) "server.context must provide at least one token per parallel slot")
    (check (builtins.elem cfg.server.flash_attention [ "on" "off" "auto" ]) "server.flash_attention must be on, off, or auto")
    (check (builtins.elem cfg.server.cache_type [ "f32" "f16" "bf16" "q8_0" "q4_0" "q4_1" "iq4_nl" "q5_0" "q5_1" ]) "unsupported server.cache_type")
    (check (builtins.elem cfg.server.reasoning [ "none" "low" "medium" "high" ]) "unsupported server.reasoning")
    (check (builtins.elem cfg.server.speculation [ "none" "draft-mtp" ]) "server.speculation must be none or draft-mtp")
    (check (builtins.isInt cfg.power.watts && cfg.power.watts >= 0) "power.watts must be a nonnegative integer")
  ];
in
builtins.deepSeq checks cfg
