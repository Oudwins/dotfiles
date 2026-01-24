{ ... }@args:

{
  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  nixpkgs = {
    overlays = builtins.attrValues args.outputs.overlays;
    config.allowUnfree = true;
  };
}
