{
  config,
  pkgs,
  lib,
  ...
}@args:
{
  home.packages = with pkgs; [
    # nvim
    unstable.neovim
    git
    fd
    unzip
    ripgrep
    gnumake
    xclip
    # marksman lsp requires this
    icu

    # compilers
    gcc
    # Dev
    go
    gotools
    gopls
    nodejs
    corepack # pnpm
    bun
    python315
    typescript
    markdownlint-cli
    nixd
    # Opencode
    typescript-language-server
  ];
  programs.neovim.extraPackages = [
    "gcc"
    "git"
    "make"
    "gnumake"
    "unzip"
    "ripgrep"
    "fd"
    "xclip"
    "python315"
    "typescript"
    "markdownlint-cli"
    "icu"
    "nixd"
  ];


  home.sessionVariables =
    {
      CODE_EDITOR = "alacritty -e nvim";
      # this is needed for marksman to find the lib
      LD_LIBRARY_PATH = "${pkgs.icu}/lib:$LD_LIBRARY_PATH";
    };

  # Let Home Manager install and manage itself.
  programs.home-manager.enable = true;
}
