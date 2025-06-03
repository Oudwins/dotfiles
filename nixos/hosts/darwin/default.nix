{ config, pkgs, ... }@args:
{
  imports = [
    # ./config-files/aerospace.nix
  ];
  # services.aerospace.enable = false;

  nixpkgs.config.allowUnfree = true;

  # List packages installed in system profile. To search by name, run:
  # $ nix-env -qaP | grep wget
  environment.systemPackages = with pkgs; [
    vim
    neovim
    direnv
    sshs
    carapace # shell completion
    firefox
    google-chrome
    # ghostty
    alacritty
    stow
    colima
    bun
  ];
  nix.enable = true;
  nix.settings.experimental-features = "nix-command flakes";

  programs.zsh.enable = true; # default shell on catalina

  users.users.tmx.home = "/Users/tmx";
  home-manager.backupFileExtension = "backup";
  system.stateVersion = 6;
  fonts.packages = with pkgs; [
    nerd-fonts.jetbrains-mono
  ];
  system.defaults = {
    # Dock
    dock = {
      autohide = true;
      mru-spaces = false;
      autohide-time-modifier = 0.0;
      expose-animation-duration = 0.0;
      launchanim = false;
      persistent-apps = [
        {
          app = "${pkgs.alacritty}/Applications/Alacritty.app";
        }
        {
          app = "${pkgs.google-chrome}/Applications/Google Chrome.app";
        }
        {
          app = "${pkgs.firefox}/Applications/Firefox.app";
        }
        {
          app = "/Applications/cursor.app";
        }
        {
          app = "/Applications/Visual Studio Code.app";
        }
        {
          app = "/Applications/Telegram.app";
        }
        {
          app = "/Applications/Zen.app";
        }
      ];
    };
    # finder
    NSGlobalDomain = {
      # inputs
      KeyRepeat = 2;
      "com.apple.swipescrolldirection" = false;
      NSAutomaticCapitalizationEnabled = false;
      NSAutomaticDashSubstitutionEnabled = false;
      NSAutomaticInlinePredictionEnabled = true;
      NSAutomaticPeriodSubstitutionEnabled = false;
      NSAutomaticQuoteSubstitutionEnabled = false;
      NSAutomaticSpellingCorrectionEnabled = false;
      NSAutomaticWindowAnimationsEnabled = false;
      NSScrollAnimationEnabled = false;
      NSUseAnimatedFocusRing = false;
      NSWindowResizeTime = 0.0;
      # Cosmetics
      AppleICUForce24HourTime = true;
      AppleInterfaceStyle = "Dark";
    };
    # trackpad = {

    # };
    # login
    loginwindow.LoginwindowText = "tmx";
    loginwindow.GuestEnabled = false;

    # screencapture
    screencapture.location = "~/Pictures/screenshots";
    screensaver.askForPasswordDelay = 10;

    # finder
    finder = {
      _FXShowPosixPathInTitle = true;
      AppleShowAllExtensions = true; 
      FXPreferredViewStyle = "clmv";
      AppleShowAllFiles = true;
      FXDefaultSearchScope = "SCcf";
      NewWindowTarget = "Home";
      ShowPathbar = true;
    };
  };

  # Homebrew needs to be installed on its own!
  homebrew.enable = true;
  homebrew.onActivation = {
    cleanup = "zap"; # remove unused packages
    autoUpdate = true;
    upgrade = true;
  };
  homebrew.casks = [
    "zen-browser"
    "cursor"
    "visual-studio-code"
    "telegram"
    "beekeeper-studio"
    "mongodb-compass"
  ];

  homebrew.brews = [
    "docker"
    "docker-compose"
  ];


    launchd.agents."colima.default" = {
    command = "${pkgs.colima}/bin/colima start --foreground";
    serviceConfig = {
      Label = "com.colima.default";
      RunAtLoad = true;
      KeepAlive = true;

      # not sure where to put these paths and not reference a hard-coded `$HOME`; `/var/log`?
      # StandardOutPath = "/Users/tmx/.colima/default/daemon/launchd.stdout.log";
      # StandardErrorPath = "/Users/tmx/.colima/default/daemon/launchd.stderr.log";
      StandardOutPath = "/tmp/colima.default.stdout.log";
      StandardErrorPath = "/tmp/colima.default.stderr.log";

      # not using launchd.agents.<name>.path because colima needs the system ones as well
      EnvironmentVariables = {
        PATH = "${pkgs.colima}/bin:${pkgs.docker}/bin:/usr/bin:/bin:/usr/sbin:/sbin";
      };
    };
  };
}
