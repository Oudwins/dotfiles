{
  config,
  pkgs,
  lib,
  ...
}@args:
{
  # No longer needed bc its used as module now
  # nixpkgs.config = {
  #   allowUnfree = true;
  #   permittedInsecurePackages = [
  #     "electron-25.9.0" # for obsidian
  #   ];
  # };
  # Home Manager needs a bit of information about you and the paths it should
  # manage.
  home.username = "tmx";
  home.homeDirectory = "/home/tmx";

  # This value determines the Home Manager release that your configuration is
  # compatible with. This helps avoid breakage when a new Home Manager release
  # introduces backwards incompatible changes.
  #
  # You should not change this value, even if you update Home Manager. If you do
  # want to update the value, then make sure to first check the Home Manager
  # release notes.
  home.stateVersion = "23.11"; # Please read the comment before changing.

  # The home.packages option allows you to install Nix packages into your
  # environment.
  home.packages = with pkgs; [
    # # It is sometimes useful to fine-tune packages, for example, by applying
    # # overrides. You can do that directly here, just don't forget the
    # # parentheses. Maybe you want to install Nerd Fonts with a limited number of
    # # fonts?
    # (pkgs.nerdfonts.override { fonts = [ "FantasqueSansMono" ]; })

    # # You can also create simple shell scripts directly inside your
    # # configuration. For example, this adds a command 'my-hello' to your
    # # environment:
    # (pkgs.writeShellScriptBin "my-hello" ''
    #   echo "Hello, ${config.home.username}!"
    # '')
    # visual/themes
    adwaita-qt # theme for qt
    gnome-themes-extra # adwaita theme for gtk
    adwaita-icon-theme
    gtk3
    # theme switchers
    # lxappearance
    # libsForQt5.qt5ct

    # Basics
    xclip # access clipboard from terminal
    tesseract4 # OCR for images
    udiskie # auto mount usbs daemon
    alacritty # terminal
    arandr # gui for screen control
    flameshot # screenshots
    gparted # drive partition management TODO -> DOESNT WORK UNLESS RAN AS ADMIN. MEANING I NEED TO FIX rofi to run as admin this
    geeqie # img viewer
    onlyoffice-desktopeditors
    obs-studio # screen recorder
    kdePackages.ark # zip manager
    unstable.qbittorrent
    gimp
    kdePackages.okular # PDF viewer
    # remote desktop
    rustdesk
    # books
    calibre
    # browsers
    librewolf
    # brave - defined elsewhere
    google-chrome
    # coms
    telegram-desktop
    # files
    syncthing
    obsidian
    # WM
    networkmanagerapplet # wifi widget
    # Dev
    stow # manager dotfiles
    gnumake # use makefiles
    fzf # fuzzy finding
    bc # basic calculator (used for bash scripts)
    vscode-fhs
    unstable.code-cursor
    bruno # postman alternative
    #git
    #git-crypt
    gnupg
    jetbrains.idea-community # Intellij
    jetbrains.goland # golang IDE
    awscli2 # aws cli
    beekeeper-studio # sql gui & database gui
    tldr
    cheat
    # languages
    go
    gotools
    gopls
    nodejs
    corepack # pnpm
    # jdk11
    jdk21
    maven
    # IaC
    terraform
    terraformer
    # compilers
    gcc

    # video
    mpv-unwrapped

    unstable.neovim
    fd
    # TODO REMOVE THIS. TEMPORARY FOR OPEN CODE
    unzip
    typescript-language-server
    ripgrep
    bun
  ];
  # Brave
  programs.brave = {
    enable = true;
    commandLineArgs = [ "--password-store=basic" ]; # used to avoid it trying to contact kde wallet
  };
  # mpv
  programs.mpv = {
    enable = true;
    package = pkgs.mpv-unwrapped; # we use this pkg bc it has better compatibility with thunar
  };
  # tells nixos to use mpv as the default video player for matroska files
  xdg.mimeApps.defaultApplications = {
    "video/x-matroska" = [ "mpv.desktop" ];
    # Set Brave as default browser
    # if this doesn't work do `xdg-settings set default-web-browser brave-browser.desktop`
    # test with -> xdg-open https://example.com
    "text/html" = [ "brave-browser.desktop" ];
    "x-scheme-handler/http" = [ "brave-browser.desktop" ];
    "x-scheme-handler/https" = [ "brave-browser.desktop" ];
  };
  # git
  programs.git = {
    enable = true;
    userName = "tristan";
    userEmail = "tm@tristanmayo.com";
    extraConfig = {
      push = {
        autoSetupRemote = true;
      };
      pack = {
        windowMemory = "256m";
        packSizeLimit = "256m";
      };
    };
  };
  # BASH
  programs.bash = {
    enable = true;
    bashrcExtra = ''
      ## set bash to vi mode
      set -o vi 
      ## ensure ctl + l is bound to clear screen
      bind '"\C-l": clear-screen'
      # TODO REMOVE THIS. TEMPORARY FOR OPEN CODE
      # Adds go to path
      export PATH="$PATH:${config.home.homeDirectory}/go/bin:${config.home.homeDirectory}/.npm/bin"

      # This allows tldr to load from nvim always
      tldrv() {
        # if nvim isn't available fall back to the real tldr output
        if ! command -v nvim >/dev/null 2>&1; then
          command tldr "$@"
          return
        fi

        # Use the real tldr (avoid recursion), pipe into nvim reading stdin
        command tldr "$@" | nvim -R -c 'set ft=markdown' -
      }
    '';
  };
  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
  };
  programs.starship = {
    enable = true;
  };
  programs.neovim.extraPackages = [
    "gcc"
    "git"
    "make"
    "unzip"
    "ripgrep"
    "fd"
    "xclip"
  ];
  # LAUNCHER
  programs.rofi = {
    enable = true;
    theme = config.home.homeDirectory + "/dotfiles/tmx/.config/rofi/themes/erebus.rasi";
    plugins = [
      pkgs.rofi-calc
      pkgs.rofi-emoji
    ];
    # to find keybindings use `rofi -show keys`
    # Options -> https://davatorium.github.io/rofi/1.7.3/rofi-keys.5/#kb-mode-complete
    extraConfig = {
      kb-clear-line = "Control+c,Control+u"; # like i do in the terminal
      kb-row-up = "Up,Control+k,Shift+Tab";
      kb-row-down = "Down,Control+j,Tab";
      kb-accept-entry = "Return,KP_Enter,Control+y";
      # kb-accept-custom = "Return"; # -> conflicts with accept key

      # don't use this and they conflict
      kb-element-next = "";
      kb-remove-to-sol = "";
      kb-remove-to-eol = "";
      # I have keybingings for the modes I want to use so disable all this
      kb-mode-previous = "";
      kb-mode-next = "";
      kb-mode-complete = "";
      # This conflicts with Control + c by default
      kb-secondary-copy = "";
    };
  };
  # couldn't get this to work, need to rethink it
  # home.activationScripts = {
  #   setUpSymlinks = {
  #     description = "Use stow to set up .dotfiles symlinks";
  #     script = ''
  #         ${PROJECT_DIR}/../updateSymlinks.sh
  #     '';
  #   };
  #
  # };
  # files
  # Home Manager is pretty good at managing dotfiles. The primary way to manage
  # plain files is through 'home.file'.
  home.file = {
    # # Building this configuration will create a copy of 'dotfiles/screenrc' in
    # # the Nix store. Activating the configuration will then make '~/.screenrc' a
    # # symlink to the Nix store copy.
    # ".screenrc".source = dotfiles/screenrc;
    #".gitconfig".source = ./.gitconfig;
    # ".testing" = {
    #   source=./.testing;
    #   recursive=true;
    # };
    # ".config/nvim" = {
    #   source=../tmx/.config/nvim;
    #   recursive=true;
    # };
    # ".config/Code/User" = {
    #   source=../tmx/.config/Code/User;
    #   recursive=true;
    # };
    # ".config/awesome" = {
    #   source=../tmx/.config/awesome;
    #   recursive=true;
    # };
    # ".config/rofi" = {
    #   source=../tmx/.config/rofi;
    #   recursive=true;
    # };
    # # You can also set the file content immediately.
    # ".gradle/gradle.properties".text = ''
    #   org.gradle.console=verbose
    #   org.gradle.daemon.idletimeout=3600000
    # '';
  };

  # THEMES
  dconf.settings = {
    "org/gnome/desktop/background" = {
      picture-uri-dark = "file://${pkgs.nixos-artwork.wallpapers.nineish-dark-gray.src}";
    };
    "org/gnome/desktop/interface" = {
      color-scheme = "prefer-dark";
    };
  };
  gtk = {
    enable = true;
    theme = {
      name = "Adwaita-dark";
      package = pkgs.gnome-themes-extra;
    };
  };

  qt.enable = true;
  qt.platformTheme.name = "gtk";
  qt.style.name = "adwaita-dark";
  qt.style.package = pkgs.adwaita-qt;

  # SERVICES
  # systemd.user.startServices = true;
  services = {
    syncthing = {
      enable = true;
      extraOptions = [
        "--home=/home/tmx/.config/syncthing"
        "--no-default-folder"
      ];
    };
    redshift = {
      enable = true;
      temperature = {
        day = 5700;
        night = 3500;
      };
      tray = true;
      dawnTime = "05:00";
      duskTime = "21:00";
    };
    # auto mount disks
    udiskie = {
      enable = true;
      notify = false;
      tray = "never";
    };
    flameshot = {
      enable = true;
      settings = {
        General = {
          disabledTrayIcon = true;
          showStartupLaunchMessage = false;
          savePath = config.home.homeDirectory + "/Downloads/";
          saveAsFileExtension = ".jpg";
          showHelp = false;
        };
      };
    };
    espanso = {
      enable = true;
      waylandSupport = false;
      x11Support = true;
      configs = {
        default = {
          search_shortcut = "off";
          search_trigger = ":search";
          show_notifications = false;
        };
      };
    };
  };

  # Home Manager can also manage your environment variables through
  # 'home.sessionVariables'. If you don't want to manage your shell through Home
  # Manager then you have to manually source 'hm-session-vars.sh' located at
  # either
  #
  #  ~/.nix-profile/etc/profile.d/hm-session-vars.sh
  #
  # or
  #
  #  /etc/profiles/per-user/tmx/etc/profile.d/hm-session-vars.sh
  #
  # home.sessionVariables = {
  #   TERMINAL = "alacritty";
  #   EDITOR = "nvim";
  #   CODE_EDITOR = "cursor";
  #   CODE_PROJECT_DIRS="${config.home.homeDirectory}/open_source:${config.home.homeDirectory}/work:${config.home.homeDirectory}/personal:${config.home.homeDirectory}/projects";
  #   LAUNCHER = "rofi -show drun";
  #   DMENU = "rofi -dmenu";
  #   SCREENSHOT = "flameshot gui";
  #   GTK_THEME= "Adwaita:dark";
  # };
  home.sessionVariables =
    let
      home = config.home.homeDirectory;
      #
      projectParentDirs = [
        "open_source"
        "work"
        "personal"
        "projects"
      ];
      projects = [
        "dotfiles"
      ];
      obsidianDirs = [ "notes" ];
    in
    {
      TERMINAL = "alacritty";
      EDITOR = "nvim";
      CODE_EDITOR = "cursor";
      # this creates a string of "/home/tmx/projects:/home/tmx/{other_project_dir}"
      # This is used by a rofi script to open the code editor in that project
      CODE_PROJECTS_PARENT_DIRS = builtins.concatStringsSep ":" (
        map (dir: "${home}/${dir}") projectParentDirs
      );
      CODE_PROJECTS = builtins.concatStringsSep ":" (map (dir: "${home}/${dir}") projects);
      OBSIDIAN_VAULT_DIRS = builtins.concatStringsSep ":" (map (dir: "${home}/${dir}") obsidianDirs);
      LAUNCHER = "rofi -show drun";
      DMENU = "rofi -dmenu";
      SCREENSHOT = "flameshot gui";
      GTK_THEME = "Adwaita:dark";
      # temporary fix for qbittorrent
      QT_STYLE_OVERRIDE = lib.mkForce "Fusion";
      BROWSER = "brave";
    };

  # Let Home Manager install and manage itself.
  programs.home-manager.enable = true;
}
