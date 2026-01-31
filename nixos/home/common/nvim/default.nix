{ config, pkgs, lib, ... }@args:

let
  isLinux = pkgs.stdenv.isLinux;
  isDarwin = pkgs.stdenv.isDarwin;
  # On NixOS we use unstable overlay, on Darwin pkgs is already unstable
  neovimPkg = if pkgs ? unstable then pkgs.unstable.neovim else pkgs.neovim;
in {
  home.packages = with pkgs;
    [
      # nvim
      neovimPkg
      git
      fd
      unzip
      ripgrep
      gnumake
      # marksman lsp requires this
      icu

      # compilers
      gcc
      # Dev
      go
      gotools
      gopls
      nodejs
      # Note: corepack is included in nodejs
      bun
      python3
      typescript
      markdownlint-cli
      nixd
      vtsls # typescript vscode server wrapper
    ] ++ lib.optionals isLinux [ xclip ];

  programs.neovim.extraPackages = [
    "gcc"
    "git"
    "make"
    "gnumake"
    "unzip"
    "ripgrep"
    "fd"
    "python3"
    "typescript"
    "markdownlint-cli"
    "icu"
    "nixd"
    "vtsls"
  ] ++ lib.optionals isLinux [ "xclip" ];

  home.sessionVariables = lib.mkMerge [
    { CODE_EDITOR = "alacritty -e nvim"; }
    (lib.mkIf isLinux {
      # this is needed for marksman to find the lib on Linux
      LD_LIBRARY_PATH = "${pkgs.icu}/lib:$LD_LIBRARY_PATH";
    })
  ];
}
