# Builders for every machine. Each host lives in hosts/<name>/default.nix.
{ inputs, outputs, configLib }:
let
  inherit (inputs.nixpkgs) lib;

  # isDarwin lets a module pick platform-specific imports (see agents/).
  specialArgs = { inherit inputs outputs configLib; };

  common = name: [
    ../modules/shared/my.nix
    (import ./soft.nix {
      inherit lib name;
      inherit (inputs.secrets.soft) values;
    })
    { nixpkgs.overlays = builtins.attrValues outputs.overlays; }
    ../hosts/${name}
  ];
in
{
  inherit specialArgs;

  # channel: "stable" (nixos-26.05) or "unstable" (nixos-unstable)
  mkHost =
    { name, channel ? "stable" }:
    let
      nixpkgs = if channel == "unstable" then inputs.nixos-unstable else inputs.nixpkgs;
    in
    nixpkgs.lib.nixosSystem {
      specialArgs = specialArgs // { isDarwin = false; };
      modules = common name;
    };

  mkDarwinHost =
    { name, system ? "aarch64-darwin" }:
    inputs.darwin.lib.darwinSystem {
      inherit system;
      specialArgs = specialArgs // { isDarwin = true; };
      modules = common name;
    };
}
