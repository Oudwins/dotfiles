{
  description = "System Config";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-24.11";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    home-manager.url = "github:nix-community/home-manager/release-24.11";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
    nixos-hardware.url = "github:NixOS/nixos-hardware/master";

    # CUSTOM STUFF
    # xremap
    xremap-flake.url = "github:xremap/nix-flake";
    sops-nix = {
      url = "github:mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, home-manager, nixos-hardware, ... }@inputs: 
  let 
   # allow self referencing. outputs here references the result of calling the "output's" function above (i.e the attribute set built inside the in block)
   inherit (self) outputs;
   # lib used to build stuff
   inherit (nixpkgs) lib;
    # Supported systems for your flake packages, shell, etc.
    systems = [
      "x86_64-linux"
      #"aarch64-linux"
      #"i686-linux"
      #"aarch64-darwin"
      #"x86_64-darwin"
    ];

    # This is a function that generates an attribute by calling a function you
    # pass to it, with each system as an argument
    forAllSystems = lib.genAttrs systems;

    specialArgs = {
      inherit inputs;
      inherit outputs;
    };
  in {
    # Your custom packages
    # Accessible through 'nix build', 'nix shell', etc
    packages = forAllSystems (system: import ./pkgs nixpkgs.legacyPackages.${system});
    # Formatter for your nix files, available through 'nix fmt'
    # Other options beside 'alejandra' include 'nixpkgs-fmt'
    formatter = forAllSystems (system: nixpkgs.legacyPackages.${system}.alejandra);

    # Your custom packages and modifications, exported as overlays
    overlays = import ./overlays {inherit inputs; inherit outputs;};

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
          modules = [
          nixos-hardware.nixosModules.lenovo-thinkpad-p14s-amd-gen2
          ./system/configuration.nix
          home-manager.nixosModules.home-manager {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.users.tmx = {
            imports = [ ./home.nix ];
            };
            home-manager.extraSpecialArgs = specialArgs;
          }
        ];
        specialArgs = specialArgs;
    };
  };
};
}
