# Home-manager users on this host.
{ ... }:

{
  home-manager.users.tmx =
    { config, pkgs, lib, inputs, ... }@args:
    {
      imports = [
        ../../users/tmx/home.nix
        ../../modules/home/linux
      ];

      # Installed outside Nix; this is the port it listens on.
      my.dashboard.services.t3code = {
        label = "T3 Code";
        description = "Coding agent workspace";
        url = "http://127.0.0.1:3773";
        category = "agents";
        icon = "mdi-code-braces";
      };

      home.packages = with pkgs;
        [
          xclip # clipboard
          # dotool # virtual keyboard for typing anywhere
        ];

      home.sessionVariables = let
        home = config.home.homeDirectory;
        projectParentDirs = [
          "open_source"
          "work"
          "personal"
          "projects"
          ".config"
        ];
        projects = [ "dotfiles" ];
        worktreeParentDirs = [ ".droner/worktrees" ];
        obsidianDirs = [ "notes" ];
      in {
        TERMINAL = "ghostty";
        EDITOR = "nvim";
        CODE_PROJECTS_PARENT_DIRS = builtins.concatStringsSep ":"
          (map (dir: "${home}/${dir}") projectParentDirs);
        CODE_PROJECTS =
          builtins.concatStringsSep ":" (map (dir: "${home}/${dir}") projects);
        CODE_WORKTREES_PARENT_DIRS = builtins.concatStringsSep ":"
          (map (dir: "${home}/${dir}") worktreeParentDirs);
        OBSIDIAN_VAULT_DIRS =
          builtins.concatStringsSep ":" (map (dir: "${home}/${dir}") obsidianDirs);
        LAUNCHER = "rofi -show drun";
        DMENU = "rofi -dmenu";
        SCREENSHOT = "flameshot gui";
        GTK_THEME = "Adwaita:dark";
        QT_STYLE_OVERRIDE = lib.mkForce "Fusion";
        BROWSER = "brave";
        DRONERD_URL = "http://localhost:57876";
      };
    };
}
