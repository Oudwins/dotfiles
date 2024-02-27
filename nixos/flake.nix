{
  description = "System Config";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-23.11";
    home-manager.url = "github:nix-community/home-manager/release-23.11";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
    nixos-hardware.url = "github:NixOS/nixos-hardware/master";
  };

  outputs = { nixpkgs, home-manager, nixos-hardware, ... }: 
  let 
    system = "x86_64-linux";
    # pkgs = import nixpkgs {
    # inherit system;
    # config = {
    # allowUnfree = true;
    # permittedInsecurePackages = [
    #   "electron-25.9.0" # for obsidian
    # ];
    # };
    # # Apply patches, set a pkgs to an older version... (here you can do this)
    # };

    lib = nixpkgs.lib;
  in {
    nixosConfigurations = {
      nixos = lib.nixosSystem {
        inherit system;
        modules = [
        nixos-hardware.nixosModules.lenovo-thinkpad-p14s-amd-gen2
        ./system/configuration.nix
        home-manager.nixosModules.home-manager {
          home-manager.useGlobalPkgs = true;
          home-manager.useUserPackages = true;
          home-manager.users.tmx = {
          imports = [ ./home.nix ];
          };
        }
        ];
      };
    };

  };
}
