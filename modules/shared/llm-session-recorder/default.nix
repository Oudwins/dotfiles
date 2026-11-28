# Records everything this machine's CLIProxyAPI serves into an llm-sessions
# ClickHouse (modules/nixos/services/llm-sessions), local or on another host.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.cli-proxy-api.sessionRecorder;
in
{
  options.services.cli-proxy-api.sessionRecorder = {
    url = lib.mkOption {
      type = lib.types.str;
      example = "https://llm-sessions.<location>.<domain>";
      description = "ClickHouse HTTP endpoint of the llm-sessions database.";
    };
    user = lib.mkOption {
      type = lib.types.str;
      default = "recorder";
      description = "ClickHouse user with INSERT on the database.";
    };
    passwordFile = lib.mkOption {
      type = lib.types.str;
      description = "File with the user's password, readable by the proxy's service account.";
    };
  };

  config.services.cli-proxy-api.plugins.session-recorder = {
    package = pkgs.cpa-session-recorder;
    settings = {
      inherit (cfg) url user;
      database = "llm";
      password-file = cfg.passwordFile;
    };
  };
}
