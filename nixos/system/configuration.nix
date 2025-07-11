# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).

{ config, pkgs, ... }@args:

{
  imports = [
    # Include the results of the hardware scan.
    ./hardware-configuration.nix
    # VM
    ./vm.nix
    # tutorial -> https://www.youtube.com/watch?v=UPWkQ3LUDOU
    args.inputs.xremap-flake.nixosModules.default # makes remap service available
    args.inputs.sops-nix.nixosModules.sops
    ./../flatpak.nix
  ];

  # SECERTS
  sops = {
    defaultSopsFile = "${../secrets/secrets.yaml}";
    validateSopsFiles = false;
    age = {
      # automatically use ssh key to gen private age key
      sshKeyPaths = [ "/etc/ssh/ssh_master_key" ];
      # location of key
      #keyFile = "/var/lib/sops-nix/key.txt";
      # generate key if it doesn't exist
      generateKey = true;
    };
  };

  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  nixpkgs = {
    overlays = builtins.attrValues args.outputs.overlays;
    config = {
      allowUnfree = true;
    };
    config.permittedInsecurePackages = [
      "beekeeper-studio-5.1.5"
    ];
    # permittedInsecurePackages = [
    #   "electron-25.9.0" # for obsidian
    # ];
  };
  # Bootloader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  # IDK WHAT THIS DOES, FOR WORK PROGRAM TO CONNECT TO COMMAND LINE
  boot.kernelParams = [
    "console=ttyS0,115200"
    "console=tty1"
  ];

  networking.hostName = "nixos"; # Define your hostname.
  networking.extraHosts = ''
    ${builtins.readFile ./../hosts-file}
  '';
  # networking.wireless.enable = true;  # Enables wireless support via wpa_supplicant.

  # Configure network proxy if necessary
  # networking.proxy.default = "http://user:password@proxy:port/";
  # networking.proxy.noProxy = "127.0.0.1,localhost,internal.domain";

  # Enable networking
  networking.networkmanager.enable = true;

  # Set your time zone.
  time.timeZone = "Europe/Madrid";

  # Select internationalisation properties.
  i18n.defaultLocale = "en_US.UTF-8";

  i18n.extraLocaleSettings = {
    LC_ADDRESS = "es_ES.UTF-8";
    LC_IDENTIFICATION = "es_ES.UTF-8";
    LC_MEASUREMENT = "es_ES.UTF-8";
    LC_MONETARY = "es_ES.UTF-8";
    LC_NAME = "es_ES.UTF-8";
    LC_NUMERIC = "es_ES.UTF-8";
    LC_PAPER = "es_ES.UTF-8";
    LC_TELEPHONE = "es_ES.UTF-8";
    LC_TIME = "es_ES.UTF-8";
  };

  # Key remapping. Only available because of xremap import above (see imports)
  services.xremap = {
    withX11 = true;
    watch = true; # watches for new devices that connect
    userName = "tmx";
    yamlConfig = ''
      modmap:
        - name: CapsLock to Esc
          remap:
            CapsLock: Esc
      keymap:
        - name: Control-y to tab for cursor
          remap:
            C-y: Tab
    '';
  };

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

  # Autorandr. Switch display profiles when plugging & unplugging hdmi
  services.autorandr.enable = true;
  # make gtk (themes & colors) work on home manager:
  programs.dconf.enable = true;

  # enable light to control screen brightness
  programs.light.enable = true;

  # FILE MANGEMENT
  # required by udiskie to automount usbs
  services.udisks2.enable = true;
  # required for phone to work auto mount
  services.gvfs.enable = true;
  # required to mount nextcloud client. Mounting
  services.davfs2.enable = true;

  sops.secrets."nextcloud/autofs_secrets_file" = {
    mode = "600";
    # owner = "tmx";
    path = "/etc/davfs2/secrets";
  };
  # Ensure the mount point directory exists
  systemd.tmpfiles.rules = [
    "d /mnt/nextcloud 0777 tmx users"
    # "d /home/tmx/.davfs2/ 0777 tmx tmx"
  ];
  fileSystems."/mnt/nextcloud" = {
    device = "https://cloud.tristanmayo.com/remote.php/webdav/";
    fsType = "davfs";
    options = [
      "user"
      "rw"
      # "auto" # auto mount on login
      "noauto" # Don't mount during boot
      # "x-systemd.automout" # auto mount on use. mounts as root unfortunatly
      "_netdev" # Indicates network dependency
      # "uid=${toString config.users.users.tmx.uid}"
      # "gid=${toString config.users.groups.users.gid}"  # Add group ID
      # grant read/write access
      "mode=0777"
      # Add if you want to store credentials in secrets file
      #"conf=/etc/davfs2/davfs2.conf"
    ];
  };

  # service to run on startup, hopefully not block and mount the nextcloud instance
  # If you change the config this may cause nix to fail switching. You may have to comment this entire code out, switch and then change the code and switch again
  systemd.services."mount-nextcloud" = {
    description = "Mount Nextcloud WebDAV filesystem";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "/run/current-system/sw/bin/mount -o uid=${toString config.users.users.tmx.uid},gid=${toString config.users.groups.users.gid} /mnt/nextcloud";
      ExecStop = "/run/current-system/sw/bin/umount /mnt/nextcloud";
      RemainAfterExit = true; # forces systemd to keep this service as "active" after exit. That way you can unmount by stoping the service
      User = "root";
      Group = "root";
      IgnoreSIGPIPE = "no";
      FailureAction = "ignore";
    };
  };

  security.sudo.extraRules = [
    {
      users = [ "tmx" ];
      commands = [
        {
          command = "/run/current-system/sw/bin/mount";
          options = [ "NOPASSWD" ];
        }
      ];
    }
  ];

  # TEAMVIEWER REMOVE THIS EVENTUALLY
  services.teamviewer.enable = true;

  # Flatpak
  services.flatpak.enable = true;
  # Required for flatpak
  xdg.portal = {
    enable = true;
    extraPortals = [ pkgs.xdg-desktop-portal-gtk ];
    config.common.default = "*";
  };
  # Enable CUPS to print documents.
  services.printing.enable = true;
  services.avahi = {
    enable = true;
    nssmdns4 = true;
    openFirewall = true;
  };
  services.printing.drivers = [
    pkgs.gutenprint
    pkgs.cnijfilter2
  ];
  # hardware.printers = {
  #   ensurePrinters = [
  #     {
  #       name = "bjc-PIXMA-MX475";
  #       location = "Home";
  #       deviceUri = "http://192.168.178.2:631/printers/Dell_1250c";
  #       model = "drv:///sample.drv/generic.ppd";
  #       ppdOptions = {
  #         PageSize = "A4";
  #       };
  #     }
  #   ];
  #   ensureDefaultPrinter = "Dell_1250c";
  # };

  # Enable sound with pipewire.
  services.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    # If you want to use JACK applications, uncomment this
    #jack.enable = true;

    # use the example session manager (no others are packaged yet so this is enabled by default,
    # no need to redefine it in your config for now)
    #media-session.enable = true;
  };

  # Enable touchpad support (enabled default in most desktopManager).
  # services.xserver.libinput.enable = true;

  # Define a user account. Don't forget to set a password with ‘passwd’.
  users.groups.tmx = { };
  users.groups.users = { };
  users.users.tmx = {
    isNormalUser = true;
    group = "tmx";
    description = "tmx";
    initialPassword = "pass";
    extraGroups = [
      "tmx"
      "users"
      "networkmanager"
      "wheel"
      "libvirtd"
      "docker"
      "video"
      "davfs2"
    ]; # libvirtd = vm, video = light (screen brightness)
    packages = with pkgs; [
      nitrogen # wallpaper
      pkgs.nixfmt-rfc-style # nix formatter
    ];
  };

  # List packages installed in system profile. To search, run:
  # $ nix search wget
  environment.systemPackages = with pkgs; [
    vim # Do not forget to add an editor to edit configuration.nix! The Nano editor is also installed by default.
    wget
    awesome # window manager
    # autorandr # automatically turn screens on & off. It sets up profiles
    # where-is-my-sddm-theme # lock screen theme (pure black) -> https://github.com/stepanzubkov/where-is-my-sddm-theme
    # VMS
    virt-manager
    virt-viewer
    spice
    spice-gtk
    spice-protocol
    win-virtio
    win-spice
    adwaita-icon-theme
    qemu
    # VPN
    unstable.tailscale
    # Printing Drivers
    gutenprint
    cnijfilter2
    # control audio
    alsa-utils
    # control brightness
    light
    # logitech mouse
    piper
  ];
  # logitech mouse
  services.ratbagd.enable = true;

  # Virtualization
  virtualisation = {
    spiceUSBRedirection.enable = true;
    # if this is removed, switch won't work
    libvirtd = {
      enable = true;
      qemu = {
        swtpm.enable = true;
        ovmf.enable = true;
        ovmf.packages = [ pkgs.OVMFFull.fd ];
      };
    };
    # Docker
    docker = {
      enable = true;
      rootless = {
        enable = true;
        setSocketVariable = true;
      };
    };
  };
  #

  programs.thunar.enable = true;
  programs.thunar.plugins = [ pkgs.xfce.thunar-archive-plugin ];
  programs.xfconf.enable = true; # required for thunar

  #
  services.spice-vdagentd.enable = true; # allows sharing files between host & guest
  programs.virt-manager.enable = true; # enable virt manager

  # VPN -> enable the tailscale service
  services.tailscale = {
    enable = true;
    package = pkgs.unstable.tailscale;
  };

  console = {
    packages = [ pkgs.terminus_font ];
    font = "${pkgs.terminus_font}/share/consolefonts/ter-i22b.psf.gz";
    useXkbConfig = true;
  };

  fonts = {
    packages = with pkgs; [
      noto-fonts
      noto-fonts-cjk-sans
      noto-fonts-emoji
      font-awesome
      source-han-sans
      source-han-sans-japanese
      source-han-serif-japanese
      nerd-fonts.meslo-lg
    ];
    fontconfig = {
      enable = true;
      defaultFonts = {
        monospace = [ "Meslo LG M regular Nerd Font Complete Mono" ];
        serif = [
          "noto Serif"
          "Source Han Serif"
        ];
        sansSerif = [
          "Noto Sans"
          "Source Han Sans"
        ];
      };

    };
  };

  # Some programs need SUID wrappers, can be configured further or are
  # started in user sessions.
  # programs.mtr.enable = true;
  # programs.gnupg.agent = {
  #   enable = true;
  #   enableSSHSupport = true;
  # };

  # List services that you want to enable:

  # Enable the OpenSSH daemon.
  # services.openssh.enable = true;

  # Open ports in the firewall.
  networking.firewall = {
    # allowedTCPPorts = [
    #   42000
    #   42001
    # ];
    # allowedUDPPorts = [
    #   5353
    # ];
  };
  #networking.firewall.allowedTCPPorts = [ ... ];
  # networking.firewall.allowedUDPPorts = [ ... ];
  # Or disable the firewall altogether.
  # networking.firewall.enable = false;

  # Stop journald from using too much disk space. Also because some services read entire logs on startup which slows down startup time
  services.journald.extraConfig = "SystemMaxUse=1G";
  # ! OPTIMIZE NIX. GC
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than +5";
    randomizedDelaySec = "10min"; # this is to avoid all the services starting at the same time. Helps improve startup time
  };
  # optimize store in every build
  nix.settings.auto-optimise-store = true;

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It‘s perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "23.11"; # Did you read the comment?

}
