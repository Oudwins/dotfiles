# Custom packages, that can be defined similarly to ones from nixpkgs
# You can build them using 'nix build .#example'
pkgs: {
  # example = pkgs.callPackage ./example { };
  beads = pkgs.callPackage ./beads/package.nix { };
  btca = pkgs.callPackage ./btca/package.nix { };
  executor = pkgs.callPackage ./executor/package.nix { };
  jsonc2json = pkgs.callPackage ./jsonc2json/package.nix { };
}
