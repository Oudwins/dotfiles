{
  description = "System Config";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-24.05";
    home-manager.url = "github:nix-community/home-manager/release-24.05";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
    nixos-hardware.url = "github:NixOS/nixos-hardware/master";
    unstable = {
      url = "github:NixOS/nixpkgs/nixpkgs-unstable";
      flake = false;
    };
    # sops-nix = {
    #   url = "github:mic92/sops-nix";
    #   inputs.nixpkgs.follows = "nixpkgs";
    # };
  };

  outputs = { nixpkgs, home-manager, nixos-hardware, unstable, ... }: 
  let 
  #  forAllSystems = lib.genAttrs [
  #       "x86_64-linux"
  #       #"aarch64-darwin"
  #   ];
    system = "x86_64-linux";
    overlay_freetube = final: prev: {
      # Override a specific package, e.g., "example-package"
      freetube = unstable.lib.freetube;
    };
    overlay_golang = final: prev: {
      go = unstable.lib.go;
    };
    overlays = [overlay_golang overlay_freetube];
    inherit unstable;
    # pkgs = import nixpkgs {
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
   ################### DevShell ####################
      #
      # Custom shell for bootstrapping on new hosts, modifying nix-config, and secrets management

      # devShells = forAllSystems (
      #   system:
      #   let
      #     pkgs = nixpkgs.legacyPackages.${system};
      #   in
      #   {
      #     default = pkgs.mkShell {
      #       NIX_CONFIG = "extra-experimental-features = nix-command flakes repl-flake";

      #       inherit (self.checks.${system}.pre-commit-check) shellHook;
      #       buildInputs = self.checks.${system}.pre-commit-check.enabledPackages;

      #       nativeBuildInputs = builtins.attrValues {
      #         inherit (pkgs)

      #           nix
      #           home-manager
      #           git
      #           just

      #           age
      #           ssh-to-age
      #           sops
      #           ;
      #       };
      #     };
      #   }
      # );

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
              inherit unstable;
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
