{ pkgs, ... }:

{
  nixpkgs.config.allowUnfree = true;

  nix.enable = true;
  nix.settings.experimental-features = "nix-command flakes";

  programs.zsh.enable = true;

  fonts.packages = with pkgs; [
    nerd-fonts.jetbrains-mono
  ];

  system.defaults = {
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
    NSGlobalDomain = {
      ApplePressAndHoldEnabled = false;
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
      AppleICUForce24HourTime = true;
      AppleInterfaceStyle = "Dark";
    };
    loginwindow.LoginwindowText = "tmx";
    loginwindow.GuestEnabled = false;
    screencapture.location = "~/Pictures/screenshots";
    screensaver.askForPasswordDelay = 10;
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
}
