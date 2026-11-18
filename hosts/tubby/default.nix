{ config, pkgs, configLib, lib, inputs, ... }@args:
let
  wifiControlSecret = {
    sopsFile = configLib.secretFile "sops/shared/wifi-control.yaml";
    restartUnits = [ "wifi-control.service" ];
  };
in
{

  imports = [
    # Include the results of the hardware scan.
    ./hardware-configuration.nix
    ./hardware-acceleration.nix
    ./root-ssh-key.nix
    (configLib.relativeToRoot "modules/nixos/core/server-base")
    (configLib.relativeToRoot "roles/server")
    (configLib.relativeToRoot "users/tmx/server.nix")

    # Secrets
    (configLib.relativeToRoot "modules/nixos/core/sops")

    # Disk
    inputs.disko.nixosModules.disko
    (configLib.relativeToRoot "modules/nixos/hardware/disko/simpleDisko.nix")
    {
      _module.args = {
        disk = "/dev/sda";
        inherit lib;
        specialArgs = args;
      };
    }

    # USERS
    (configLib.relativeToRoot "users/tmx/server.nix")

    # Services
    (configLib.relativeToRoot "modules/nixos/core/restic-backup.nix")
    (configLib.relativeToRoot "modules/nixos/core/tailscale.nix")

    (configLib.relativeToRoot "modules/nixos/services/ssl/cloudflare")

    (configLib.relativeToRoot "modules/nixos/services/nextcloud")
    (configLib.relativeToRoot
      "modules/nixos/services/nextcloud/topleveldomain.nix") # ensures that I can access this nextcloud instance from nextcloud.domain.com

    (configLib.relativeToRoot "modules/nixos/services/transmission")
    (configLib.relativeToRoot "modules/nixos/services/syncthing")
    (configLib.relativeToRoot "modules/nixos/services/paperless")
    (configLib.relativeToRoot "modules/nixos/services/metrics") # cpu, memory etc metrics
    (configLib.relativeToRoot "modules/nixos/services/shiori") # bookmarks manager
    (configLib.relativeToRoot "modules/nixos/services/freshRSS") # full text rss
    (configLib.relativeToRoot "modules/nixos/services/vaultwarden")
    (configLib.relativeToRoot "modules/nixos/services/dashboard")
    (configLib.relativeToRoot "modules/nixos/services/wifi-control")
    (configLib.relativeToRoot "modules/nixos/services/timetracking/solidtime")
    (configLib.relativeToRoot "modules/nixos/services/media-server")
    (configLib.relativeToRoot "modules/nixos/services/gitea")
    (configLib.relativeToRoot "modules/nixos/services/accounting")
    (configLib.relativeToRoot "modules/nixos/services/couchdb")
    (configLib.relativeToRoot "modules/nixos/services/mealie")
    (configLib.relativeToRoot "modules/nixos/services/memos")
    (configLib.relativeToRoot "modules/nixos/services/immich")
    (configLib.relativeToRoot "modules/nixos/services/memos")

  ];

  sops.defaultSopsFile = configLib.secretFile "sops/hosts/tubby.yaml";

  # Database passwords and app keys for the containers, as env files.
  sops.secrets."memos/env_file" = { };
  sops.secrets."solidtime/env_file" = { };
  sops.secrets."solidtime/db_env_file" = { };
  sops.secrets."shiori/env_file" = { };
  my.memos.environmentFile = config.sops.secrets."memos/env_file".path;
  my.solidtime.environmentFile = config.sops.secrets."solidtime/env_file".path;
  my.solidtime.dbEnvironmentFile = config.sops.secrets."solidtime/db_env_file".path;
  services.shiori.environmentFile = config.sops.secrets."shiori/env_file".path;

  # SMTP login for service emails (no-reply account on iss's mailserver).
  sops.secrets."mail/passwords/${config.my.smtp.from}".sopsFile =
    configLib.secretFile "sops/shared/mail.yaml";
  my.smtp.passwordFile = config.sops.secrets."mail/passwords/${config.my.smtp.from}".path;

  # SERVER OPTIONS
  my.server.location = "t";

  sops.secrets."wifi-control/digi/username" = wifiControlSecret;
  sops.secrets."wifi-control/digi/password" = wifiControlSecret;
  sops.secrets."wifi-control/openwrt/username" = wifiControlSecret;
  sops.secrets."wifi-control/openwrt/password" = wifiControlSecret;

  my.wifiControl = {
    enable = true;
    routers = {
      digi = {
        name = "DIGI";
        connectionType = "zte-http";
        url = "https://192.168.1.1";
        certificateSHA256 = "4caa880f5db7a65cb4554b8a07d7d178f4bc8076fa18a83a980e805e18998532";
        credentials = {
          username = config.sops.secrets."wifi-control/digi/username".path;
          password = config.sops.secrets."wifi-control/digi/password".path;
        };
      };
      openwrt = {
        name = "OpenWrt";
        connectionType = "openwrt-ubus";
        url = "https://192.168.1.11/ubus";
        certificateSHA256 = "7a723b9b86e9d51fc2bec5990cd83dc21838b7912bc8d9095a0ebef4102ae472";
        credentials = {
          username = config.sops.secrets."wifi-control/openwrt/username".path;
          password = config.sops.secrets."wifi-control/openwrt/password".path;
        };
      };
    };
  };

  # boot kernel params to turn off screen. Doesn't work
  boot.kernelParams =
    [ "video=card0:D" "video=card0-Unknown-1:D" "consoleblank=10" ];

  # Run startup, turn off screen. This can fail with "(code=exited, status=203/EXEC)"
  # doesn't work
  # systemd.services.turn-off-screen = {
  #   description = "Turn off screen";
  #   # Run on system startup
  #   wantedBy = [ "multi-user.target" ];

  #   serviceConfig = {
  #     # Run as a specific user - replace with your desired user
  #     User = "root";
  #     # Run only once
  #     Type = "oneshot";
  #     RemainAfterExit = "yes";
  #     # Your command goes here
  #     # ExecStart = "echo '0' > /sys/class/backlight/intel_backlight/brightness";
  #     # Restart policy
  #     Restart = "no";
  #     # Security hardening
  #     ProtectSystem = "full";
  #     ProtectHome = true;
  #     NoNewPrivileges = true;
  #     PrivateTmp = true;
  #   };
  # };

  # Bootloader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # boot.loader = {
  #   efi = {
  #     canTouchEfiVariables = true;
  #     efiSysMountPoint = "/boot/efi"; # Use your EFI system partition mount point
  #   };
  #   grub = {
  #     enable = true;
  #     device = "nodev"; # Install GRUB for EFI
  #     efiSupport = true;
  #     configurationLimit = 10; # Keep only last 10 generations
  #     # Uncomment and modify for custom theme
  #     # theme = pkgs.nixos-grub2-theme;

  #     # Optional: Custom GRUB menu settings
  #     extraEntries = ''
  #       # Add custom menu entries here if needed
  #       # menuentry "Custom OS" {
  #       #   set root=(hd0,1)
  #       #   chainloader +1
  #       # }
  #     '';
  #   };
  # };

  networking.hostName = "tubby"; # Define your hostname.

  # Set your time zone.
  time.timeZone = "Europe/Madrid";

  # services.xserver.enable = false;
  # Enable the X11 windowing system.
  services.displayManager = {
    sddm.enable = true;
    # Enable awesome wm
    defaultSession = "none+awesome";
  };
  services.xserver = {
    enable = true;
    windowManager.awesome = {
      enable = true;
      luaModules = with pkgs.luaPackages; [
        luarocks # is the package manager for Lua modules
        luadbi-mysql # Database abstraction layer
      ];
    };
    # Configure keymap in X11
    xkb = {
      layout = "us,es";
      variant = "";
    };
  };

  # Enable networking // wifi // nmcli
  networking.networkmanager.enable = true;
  sops.secrets."wifi/nifilheim" = {
    restartUnits = [ "NetworkManager.service" ];
    mode = "0600";
    owner = "root";
    path = "/etc/NetworkManager/system-connections/nifilheim.nmconnection";
  };

  # Disable power management features
  services.logind = {
    lidSwitch = "ignore"; # Keep running when lid is closed
    settings = {
      Login = {
        IdleAction = "ignore"; # Don't suspend on idle
      };
    };
  };

  # SET UP SSH
  services.openssh = {
    enable = true;
    settings = {
      # TODO REMOVE THIS for security
      PermitRootLogin = "yes";
      #PasswordAuthentication = true;
      # Harden
      # PasswordAuthentication = false;
      # PermitRootLogin = "no";
      # # Automatically remove stale sockets
      # StreamLocalBindUnlink = "yes";
      # # Allow forwarding ports to everywhere
      # GatewayPorts = "clientspecified";
    };
  };

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It‘s perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "24.05"; # Did you read the comment?
}
