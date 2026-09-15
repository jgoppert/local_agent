let
  cfg = import ./config.nix;
in
builtins.concatStringsSep "\n" (map (id:
  "${id}${if id == cfg.model.default then " (default)" else ""}\t${cfg.models.${id}.name}"
) (builtins.attrNames cfg.models)) + "\n"
