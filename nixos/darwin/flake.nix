{
  description = "Macos Config";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    darwin = {
      url = "github:LnL7/nix-darwin/master";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nix-homebrew = {
      url = "github:zhaofengli-wip/nix-homebrew";
    };

    homebrew-bundle = {
      url = "github:homebrew/homebrew-bundle";
      flake = false;
    };
    homebrew-core = {
      url = "github:homebrew/homebrew-core";
      flake = false;
    };
    homebrew-cask = {
      url = "github:homebrew/homebrew-cask";
      flake = false;
    };
    homebrew-typesense = {
      url = "github:typesense/homebrew-tap";
      flake = false;
    };
    homebrew-ngrok = {
      url = "github:ngrok/homebrew-ngrok";
      flake = false;
    };
    homebrew-mongodb = {
      url = "github:mongodb/homebrew-brew";
      flake = false;
    };
    
  };

  outputs =
    {
      self,
      darwin,
      nix-homebrew,
      homebrew-bundle,
      homebrew-core,
      homebrew-cask,
      home-manager,
      homebrew-typesense,
      homebrew-ngrok,
      homebrew-mongodb,
      nixpkgs,
    }@inputs:
    let
      # allow self referencing. outputs here references the result of calling the "output's" function above (i.e the attribute set built inside the in block)
      inherit (self) outputs;
      # lib used to build stuff
      inherit (nixpkgs) lib;
      user = "tmx";

      darwinSystems = [
        "aarch64-darwin"
        "x86_64-darwin"
      ];
      # Supported systems for your flake packages, shell, etc.
      systems = [
        "aarch64-darwin"
        "x86_64-darwin"
        # "x86_64-linux"
        #"aarch64-linux"
        #"i686-linux"
        # "aarch64-darwin"
      ];

      # This is a function that generates an attribute by calling a function you
      # pass to it, with each system as an argument
      forAllSystems = lib.genAttrs systems;

      specialArgs = {
        inherit inputs;
        inherit outputs;
      };
    in
    {
      # Your custom packages
      # Accessible through 'nix build', 'nix shell', etc
      packages = forAllSystems (system: import ./../pkgs nixpkgs.legacyPackages.${system});
      # Formatter for your nix files, available through 'nix fmt'
      # Other options beside 'alejandra' include 'nixpkgs-fmt'
      formatter = forAllSystems (system: nixpkgs.legacyPackages.${system}.alejandra);

      # Your custom packages and modifications, exported as overlays
      overlays = import ./../overlays {
        inherit inputs;
        inherit outputs;
      };

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

      # darwinConfigurations = nixpkgs.lib.genAttrs darwinSystems (
      #   system:
      #   darwin.lib.darwinSystem {
      #     inherit system;
      #     specialArgs = specialArgs;
      #     modules = [
      #       home-manager.darwinModules.home-manager
      #       nix-homebrew.darwinModules.nix-homebrew
      #       {
      #         nix-homebrew = {
      #           inherit user;
      #           enable = true;
      #           enableRosetta = true;
      #           taps = {
      #             "homebrew/homebrew-core" = homebrew-core;
      #             "homebrew/homebrew-cask" = homebrew-cask;
      #             "homebrew/homebrew-bundle" = homebrew-bundle;
      #           };
      #           mutableTaps = false;
      #           autoMigrate = true;
      #         };
      #       }
      #       ./hosts/darwin
      #     ];
      #   }
      # );

      darwinConfigurations = {
        macos = darwin.lib.darwinSystem {
          # inherit system;
          system = "aarch64-darwin";
          specialArgs = specialArgs;
          modules = [
            ./../hosts/darwin
            home-manager.darwinModules.home-manager
            {
              home-manager.useGlobalPkgs = true;
              home-manager.useUserPackages = true;
              home-manager.extraSpecialArgs = specialArgs;
              home-manager.users.${user} = import ./../hosts/darwin/home.nix;
            }
            nix-homebrew.darwinModules.nix-homebrew
            {
              nix-homebrew = {
                inherit user;
                enable = true;
                enableRosetta = true;
                taps = {
                  "homebrew/homebrew-core" = homebrew-core;
                  "homebrew/homebrew-cask" = homebrew-cask;
                  "homebrew/homebrew-bundle" = homebrew-bundle;
                  "typesense/homebrew-tap" = homebrew-typesense;
                  "ngrok/homebrew-ngrok" = homebrew-ngrok;
                  "mongodb/homebrew-brew" = homebrew-mongodb;
                };
                mutableTaps = true;
                autoMigrate = true;
              };
            }
          ];
        };
      };
    };
}
