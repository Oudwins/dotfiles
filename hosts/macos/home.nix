# Home-manager users on this host.
{ ... }:

{
  home-manager.users.tmx =
    { config, pkgs, lib, ... }@args:
    {
      imports = [
        ../../users/tmx/home.nix
        ../../modules/home/darwin
      ];

      # This value determines the Home Manager release that your configuration is
      # compatible with. This helps avoid breakage when a new Home Manager release
      # introduces backwards incompatible changes.
      #
      # You should not change this value, even if you update Home Manager. If you do
      # want to update the value, then make sure to first check the Home Manager
      # release notes.

      home.file.".docker/config.json".text = builtins.toJSON {
        auths = { };
        cliPluginsExtraDirs = [ "/opt/homebrew/lib/docker/cli-plugins" ];
        credHelpers = {
          "us-central1-docker.pkg.dev" = "gcloud";
        };
        currentContext = "colima";
      };

      home.sessionVariables = let
        home = config.home.homeDirectory;
        projectDirs = [ "Documents" "Documents2" ];
        projects = [ "dotfiles" ];
        worktreeParentDirs = [ ".droner/worktrees" ];
      in {
        OPENCODE_CONFIG = "${home}/.config/opencode/opencode.jsonc";
        OPENCODE_CONFIG_DIR = "${home}/.config/opencode";
        DOCKER_CLI_PLUGIN_EXTRA_DIRS = "/opt/homebrew/lib/docker/cli-plugins";
        GOOGLE_CLOUD_PROJECT = "xi-playground";
        CLOUD_ML_REGION = "us-east5";
        TERMINAL = "ghostty";
        EDITOR = "nvim";
        # this creates a string of "/home/tmx/projects:/home/tmx/{other_project_dir}"
        # This is used by a rofi script to open the code editor in that project
        CODE_PROJECTS_PARENT_DIRS =
          builtins.concatStringsSep ":" (map (dir: "${home}/${dir}") projectDirs);
        CODE_PROJECTS =
          builtins.concatStringsSep ":" (map (dir: "${home}/${dir}") projects);
        CODE_WORKTREES_PARENT_DIRS = builtins.concatStringsSep ":"
          (map (dir: "${home}/${dir}") worktreeParentDirs);
      };

      # Preserve JSON quotes instead of nesting them in sessionVariables' double quotes.
      home.sessionVariablesExtra = ''
        export OPENCODE_CONFIG_CONTENT=${lib.escapeShellArg (builtins.toJSON {
          agent.ui-developer.model = "cc-proxy/claude-opus-5-5";
        })}
      '';

      # Let Home Manager install and manage itself.
      programs.home-manager.enable = true;
    };
}
