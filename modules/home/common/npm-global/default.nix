# Installs global npm packages that are missing from ~/.npm on activation.
# Versions are not tracked: update manually with `npm update -g`.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.programs.npm-global;
in
{
  options.programs.npm-global.packages = lib.mkOption {
    default = { };
    example = {
      "@openai/codex" = { };
      "@earendil-works/pi-coding-agent".flags = [ "--ignore-scripts" ];
    };
    description = "Global npm packages to install at @latest when missing.";
    type = lib.types.attrsOf (
      lib.types.submodule {
        options.flags = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          description = "Extra flags passed to `npm install` for this package.";
        };
      }
    );
  };

  config = lib.mkIf (cfg.packages != { }) {
    home.activation.npmGlobal = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      export PATH="${
        lib.makeBinPath [
          pkgs.nodejs
          pkgs.git
        ]
      }:$PATH"
      ${lib.concatStrings (
        lib.mapAttrsToList (name: package: ''
          if [ ! -e "$HOME/.npm/lib/node_modules/${name}/package.json" ]; then
            run npm install --global --prefix "$HOME/.npm" ${lib.escapeShellArgs package.flags} ${lib.escapeShellArg "${name}@latest"} \
              || warnEcho "Failed to install npm package ${name}; retrying on next activation."
          fi
        '') cfg.packages
      )}
    '';
  };
}
