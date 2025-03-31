{ config, pkgs, ... }@args:

{
  imports = [
  ];

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
  ];
  nix.enable = true;
  nix.settings.experimental-features = "nix-command flakes";

  programs.zsh.enable = true; # default shell on catalina

  users.users.tmx.home = "/Users/tmx";
  home-manager.backupFileExtension = "backup";
  system.stateVersion = 6;
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
          app = "/Applications/Zen Browser.app";
        }
      ];
    };
    # finder
    finder.AppleShowAllExtensions = true;
    finder.FXPreferredViewStyle = "clmv";
    # inputs
    NSGlobalDomain.KeyRepeat = 2;
    # Cosmetics
    NSGlobalDomain = {
      AppleICUForce24HourTime = true;
      AppleInterfaceStyle = "Dark";
      "com.apple.swipescrolldirection" = false;
    };
    # login
    loginwindow.LoginwindowText = "tmx";
    loginwindow.GuestEnabled = false;

    # screencapture
    screencapture.location = "~/Pictures/screenshots";
    screensaver.askForPasswordDelay = 10;
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
  ];
  # homebrew.brews = [
  #   "imagemagick"
  # ];
}
