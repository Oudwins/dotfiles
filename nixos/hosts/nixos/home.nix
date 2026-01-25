{ config, pkgs, lib, ... }@args:

{
  imports = [ ../../home/nixos ];

  home.username = "tmx";
  home.homeDirectory = "/home/tmx";
  home.stateVersion = "23.11"; # Please read the comment before changing.

  # home.file = {
  # };

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
}
