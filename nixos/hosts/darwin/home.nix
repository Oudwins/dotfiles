{
  config,
  pkgs,
  lib,
  ...
}@args:
{
  home.username = "tmx";
  home.homeDirectory = "/Users/tmx";

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
    (nerdfonts.override { fonts = [ "JetBrainsMono" ]; })
  ];
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
  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
  };
  programs.starship = {
    enable = true;
  };
  # programs.neovim.extraPackages = [ "gcc" ];
  # LAUNCHER

  # home.sessionVariables =
  #   let
  #     home = config.home.homeDirectory;
  #     projectDirs = [
  #       "open_source"
  #       "work"
  #       "personal"
  #       "projects"
  #     ];
  #     obsidianDirs = [ "notes" ];
  #   in
  #   {
  #     TERMINAL = "alacritty";
  #     EDITOR = "nvim";
  #     CODE_EDITOR = "cursor";
  #     # this creates a string of "/home/tmx/projects:/home/tmx/{other_project_dir}"
  #     # This is used by a rofi script to open the code editor in that project
  #     CODE_PROJECT_DIRS = builtins.concatStringsSep ":" (map (dir: "${home}/${dir}") projectDirs);
  #     OBSIDIAN_VAULT_DIRS = builtins.concatStringsSep ":" (map (dir: "${home}/${dir}") obsidianDirs);
  #     LAUNCHER = "rofi -show drun";
  #     DMENU = "rofi -dmenu";
  #     SCREENSHOT = "flameshot gui";
  #     GTK_THEME = "Adwaita:dark";
  #     # temporary fix for qbittorrent
  #     QT_STYLE_OVERRIDE = lib.mkForce "Fusion";
  #   };

  # Let Home Manager install and manage itself.
  programs.home-manager.enable = true;
}
