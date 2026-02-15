{ config, pkgs, lib, inputs, ... }@args:

{
  imports = [ ../../home/nixos inputs.voxtype.homeManagerModules.default ];

  home.username = "tmx";
  home.homeDirectory = "/home/tmx";
  home.stateVersion = "23.11"; # Please read the comment before changing.

  home.packages = with pkgs;
    [
      xclip # clipboard
      # dotool # virtual keyboard for typing anywhere
    ];

  home.sessionVariables = let
    home = config.home.homeDirectory;
    projectParentDirs =
      [ "open_source" "work" "personal" "projects" ".config" "Documents" ];
    projects = [ "dotfiles" ];
    obsidianDirs = [ "notes" ];
  in {
    TERMINAL = "alacritty";
    EDITOR = "nvim";
    CODE_EDITOR = lib.mkDefault "cursor .";
    CODE_PROJECTS_PARENT_DIRS = builtins.concatStringsSep ":"
      (map (dir: "${home}/${dir}") projectParentDirs);
    CODE_PROJECTS =
      builtins.concatStringsSep ":" (map (dir: "${home}/${dir}") projects);
    OBSIDIAN_VAULT_DIRS =
      builtins.concatStringsSep ":" (map (dir: "${home}/${dir}") obsidianDirs);
    LAUNCHER = "rofi -show drun";
    DMENU = "rofi -dmenu";
    SCREENSHOT = "flameshot gui";
    GTK_THEME = "Adwaita:dark";
    QT_STYLE_OVERRIDE = lib.mkForce "Fusion";
    BROWSER = "brave";
  };

  programs.voxtype = {
    enable = true;
    package = inputs.voxtype.packages.${pkgs.system}.default;
    model.name = "base.en";
    service.enable = true;
    settings = {
      hotkey = { key = "SCROLLLOCK"; };
      audio = {
        # device = "alsa_input.pci-0000_07_00.6.HiFi__Mic1__source";
        device = "default";
        sample_rate = 16000;
        max_duration_secs = 120;
      };
      output = { mode = "paste"; };
    };
  };

  systemd.user.services.voxtype.Service.Environment =
    [ "YDOTOOL_SOCKET=/run/ydotoold/socket" ];
}
