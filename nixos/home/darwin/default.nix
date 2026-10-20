{ config, lib, pkgs, ... }:

let
  executorToken = config.sops.secrets."executor/token".path or "${config.xdg.configHome}/sops-nix/secrets/executor/token";
  exportExecutorToken = pkgs.writeShellScript "export-executor-token" ''
    token="$(${pkgs.coreutils}/bin/cat ${lib.escapeShellArg executorToken})" || exit 1
    [ -n "$token" ] || exit 1
    exec /bin/launchctl setenv EXECUTOR_MCP_TOKEN "$token"
  '';
in
{
  imports = [
    ../common
    ./aerospace
    ./alacritty
    ./packages
    ./shell
  ];

  # GUI apps inherit launchd's environment rather than Home Manager's shell variables.
  launchd.agents.executor-token = {
    enable = true;
    config = {
      ProgramArguments = [ "${exportExecutorToken}" ];
      RunAtLoad = true;
      # Retry if SOPS has not decrypted the secret yet at login.
      KeepAlive.SuccessfulExit = false;
      ThrottleInterval = 5;
      ProcessType = "Background";
    };
  };
}
