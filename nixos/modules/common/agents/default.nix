{ pkgs, ... }@args:
let isDarwin = pkgs.stdenv.isDarwin;
in {
  # TODO remove this. This is Temporary for Open Code in linux
  programs.nix-ld.enable = !isDarwin;
}
