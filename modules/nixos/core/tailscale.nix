{
  config,
  pkgs,
  lib,
  configLib,
  ...
}:
let
  cfg = config.my.tailscale;
in
{
  options.my.tailscale = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
    };
    subdomain = lib.mkOption {
      type = lib.types.nonEmptyStr;
      default = config.networking.hostName;
    };
    ssh.enable = lib.mkEnableOption "";
    exitNode.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
    };
    serve = lib.mkOption {
      type = lib.types.nullOr lib.types.nonEmptyStr;
      default = null;
    };
  };

  config = lib.mkIf cfg.enable {
    sops.secrets = lib.optionalAttrs config.my.sops.enable {
      "tailscale/auth_key" = {
        sopsFile = configLib.secretFile "sops/shared/common.yaml";
      };
    };

    services.tailscale = {
      enable = true;
      package = pkgs.unstable.tailscale;
      authKeyFile = config.sops.secrets."tailscale/auth_key".path or "/run/secrets/tailscale-auth-key";
      openFirewall = true;
      useRoutingFeatures = if (cfg.exitNode.enable || (cfg.serve != null)) then "server" else "client";
      extraUpFlags = [ "--reset=true" ];
      extraSetFlags = [
        "--advertise-exit-node=${lib.boolToString cfg.exitNode.enable}"
        # WARNING DO NOT ENABLE THIS. This configures tailscale only ssh. Which has different behaviour to regular ssh, we already harden regular ssh so not needed
        "--ssh=${lib.boolToString cfg.ssh.enable}"
        # "--hostname=${cfg.subdomain}"
      ];
    };

    system.activationScripts.restartTailscaleAutoconnect = lib.mkIf config.my.sops.enable {
      deps = [ "setupSecrets" ];
      text = ''
        tailscale_state="$(${lib.getExe pkgs.tailscale} status --json --peers=false 2>/dev/null | ${lib.getExe pkgs.jq} -r '.BackendState // empty' || true)"

        if [ "$tailscale_state" != "Running" ]; then
          echo "Tailscale state is '$tailscale_state', restarting tailscaled-autoconnect.service"
          ${pkgs.systemd}/bin/systemctl restart tailscaled-autoconnect.service || true
        fi
      '';
    };

    # Not sure what this does:
    # systemd.services.tailscaled-set.after = [ "tailscaled-autoconnect.service" ];
    # systemd.services.tailscaled-serve = lib.mkIf (cfg.serve != null) {
    #   after = [
    #     "tailscaled.service"
    #     "tailscaled-autoconnect.service"
    #   ];
    #   wants = [ "tailscaled.service" ];
    #   wantedBy = [ "multi-user.target" ];
    #   serviceConfig.Type = "oneshot";
    #   script = ''
    #     ${lib.getExe pkgs.tailscale} cert ${cfg.subdomain}.${config.networking.domain}
    #     ${lib.getExe pkgs.tailscale} serve reset
    #     ${lib.getExe pkgs.tailscale} serve --bg ${cfg.serve}
    #   '';
    # };
  };
}
