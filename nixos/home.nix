{ config, pkgs, ... }@args:
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
    xfce.xfconf # required for thunar to work
    xfce.thunar # file manager
    arandr # gui for screen control
    flameshot # screenshots 
    gparted # drive partition management TODO -> DOESNT WORK
    cinnamon.warpinator # share files pc-phone
    mpv # media player
    geeqie # img viewer
    onlyoffice-bin
    obs-studio # screen recorder
    libsForQt5.ark # Ark, zips, archive
    unstable.qbittorrent
    gimp
    # books
    calibre
    # browsers
    librewolf
    brave
    google-chrome
    freetube
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
    unstable.neovim
    vscode-fhs
    unstable.code-cursor
    bruno # postman alternative
    git
    git-crypt
    gnupg
    jetbrains.idea-community # Intellij
    jetbrains.goland # golang IDE
    awscli2 # aws cli
    beekeeper-studio # sql gui & database gui
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
  ];
  # BASH
  programs.bash = {
    enable = true;
    bashrcExtra = ''
      ## set bash to vi mode
      set -o vi 
      ## ensure ctl + l is bound to clear screen
      bind '"\C-l": clear-screen'
    '';
  };
  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
  };
  programs.starship = {
    enable = true;
  };
  programs.neovim.extraPackages = ["gcc"];
  # LAUNCHER
  programs.rofi = {
    enable = true;
    theme = config.home.homeDirectory + "/dotfiles/tmx/.config/rofi/themes/erebus.rasi";
    plugins = [pkgs.rofi-calc pkgs.rofi-emoji];
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
        package = pkgs.gnome.gnome-themes-extra;
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
      extraOptions = ["--home=/home/tmx/.config/syncthing" "--no-default-folder"];
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
home.sessionVariables = let
  home = config.home.homeDirectory;
  projectDirs = [
    "open_source"
    "work"
    "personal"
    "projects"
  ];
  obsidianDirs = [ "notes" ];
in {
  TERMINAL = "alacritty";
  EDITOR = "nvim";
  CODE_EDITOR = "cursor";
  # this creates a string of "/home/tmx/projects:/home/tmx/{other_project_dir}"
  # This is used by a rofi script to open the code editor in that project
  CODE_PROJECT_DIRS = builtins.concatStringsSep ":" (map (dir: "${home}/${dir}") projectDirs);
  OBSIDIAN_VAULT_DIRS = builtins.concatStringsSep ":" (map (dir: "${home}/${dir}") obsidianDirs);
  LAUNCHER = "rofi -show drun";
  DMENU = "rofi -dmenu";
  SCREENSHOT = "flameshot gui";
  GTK_THEME = "Adwaita:dark";
};

  # Let Home Manager install and manage itself.
  programs.home-manager.enable = true;
}
