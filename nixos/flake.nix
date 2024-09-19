{
  description = "System Config";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-24.05";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    home-manager.url = "github:nix-community/home-manager/release-24.05";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
    nixos-hardware.url = "github:NixOS/nixos-hardware/master";
    # sops-nix = {
    #   url = "github:mic92/sops-nix";
    #   inputs.nixpkgs.follows = "nixpkgs";
    # };
  };

  outputs = { nixpkgs, home-manager, nixos-hardware, ... }@inputs: 
  let 
  
   forAllSystems = lib.genAttrs [
        "x86_64-linux"
        #"aarch64-darwin"
    ];
    system = "x86_64-linux"; # defines the system. Should be replaced with forAllSystems in the future
    lib = nixpkgs.lib;
    # overlay to add unstable to pkgs.unstable
  in {
   ################### DevShell ####################
      #
      # Custom shell for bootstrapping on new hosts, modifying nix-config, and secrets management
       devShells = forAllSystems (
         system:
         let
           pkgs = nixpkgs.legacyPackages.${system};
         in
         {
           default = pkgs.mkShell {
             NIX_CONFIG = "extra-experimental-features = nix-command flakes repl-flake";
             nativeBuildInputs = builtins.attrValues {
               inherit (pkgs)

                 nix
                 home-manager
                 git
                 just

                 age
                 ssh-to-age
                 sops
                 ;
             };
           };
         }
       );

    # SYSTEMS
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
            home-manager.extraSpecialArgs = {
            };
          }
        ];
        # specialArgs = {
        #     inherit overlays; 
        #   };
    };
  };
};
}
