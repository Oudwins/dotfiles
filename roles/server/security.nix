{ config, lib, ... }:
let
  cfg = config.my.server.security;
  isManaged = cfg.level != "none";
  sshPort = if cfg.level == "public" then 2525 else 22;
in {
  options.my.server.security.level = lib.mkOption {
    type = lib.types.enum [ "none" "intranet" "public" ];
    default = "none";
    description = "Server security profile to apply.";
  };

  config = lib.mkMerge [
    {
      security.sudo = {
        enable = lib.mkDefault true;
        wheelNeedsPassword = lib.mkDefault true;
      };
    }

    (lib.mkIf isManaged {
      services.openssh = {
        enable = lib.mkOverride 900 true;
        openFirewall = lib.mkOverride 900 true;
        ports = lib.mkOverride 900 [ sshPort ];
        settings = {
          PermitRootLogin = lib.mkOverride 900
            (if cfg.level == "intranet" then "prohibit-password" else "no");
          PasswordAuthentication = lib.mkOverride 900 false;
          # Disables password/otp auth over ssh
          KbdInteractiveAuthentication = lib.mkOverride 900 false;
        };
        # Note sure what each of these options do or if we should add them for sure
        # extraConfig = ''
        #   AllowTcpForwarding yes
        #   X11Forwarding no
        #   AllowAgentForwarding no
        #   AllowStreamLocalForwarding no
        #   AuthenticationMethods publickey
        # '';
      };

      networking.firewall.enable = lib.mkOverride 900 true;
      networking.firewall.allowPing =
        lib.mkOverride 900 (cfg.level == "intranet");

      services.fail2ban.enable = lib.mkOverride 900 (cfg.level == "public");

      # only wheel can use the nix pkg manager
      nix.allowedUsers = [ "@wheel" ];

      # This tracks all stuff executed in server. But not sure I need it
      # security.auditd.enable = true;
      # security.audit.enable = true;
      # security.audit.rules = [
      #   "-a exit,always -F arch=b64 -S execve"
      # ];
    })

    (lib.mkIf (!isManaged) {
      services.openssh = {
        enable = lib.mkDefault true;
        settings = {
          PermitRootLogin = lib.mkDefault "yes";
          PasswordAuthentication = lib.mkDefault true;
        };
      };
    })
  ];
}
