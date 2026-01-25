{
  description = "System Config";

  inputs = {
    # NixOS uses stable
    nixpkgs.url = "github:nixos/nixpkgs/nixos-25.11";
    # Darwin uses unstable
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    # Home manager for NixOS (follows stable)
    home-manager.url = "github:nix-community/home-manager/release-25.11";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";

    # Home manager for Darwin (follows unstable)
    home-manager-darwin = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };

    nixos-hardware.url = "github:NixOS/nixos-hardware/master";

    # declarative flatpaks for zen browser only atm
    nix-flatpak.url = "github:gmodena/nix-flatpak";
    # TMUX sessions plugin
    tmux-sessionx.url = "github:omerxx/tmux-sessionx";

    # CUSTOM STUFF
    # xremap
    xremap-flake.url = "github:xremap/nix-flake";
    sops-nix = {
      url = "github:mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Darwin-specific inputs
    darwin = {
      url = "github:LnL7/nix-darwin/master";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };
    nix-homebrew.url = "github:zhaofengli-wip/nix-homebrew";
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

  outputs = { self, nixpkgs, nixpkgs-unstable, home-manager, home-manager-darwin
    , nixos-hardware, nix-flatpak, darwin, nix-homebrew, homebrew-bundle
    , homebrew-core, homebrew-cask, homebrew-typesense, homebrew-ngrok
    , homebrew-mongodb, ... }@inputs:
    let
      # allow self referencing
      inherit (self) outputs;
      inherit (nixpkgs) lib;

      # System lists
      linuxSystems = [ "x86_64-linux" ];
      darwinSystems = [ "aarch64-darwin" "x86_64-darwin" ];
      systems = linuxSystems ++ darwinSystems;

      forAllSystems = lib.genAttrs systems;

      specialArgs = {
        inherit inputs;
        inherit outputs;
      };

      user = "tmx";

      # Helper to get the right nixpkgs for each system
      pkgsFor = system:
        if builtins.elem system darwinSystems then
          nixpkgs-unstable.legacyPackages.${system}
        else
          nixpkgs.legacyPackages.${system};
    in {
      # Your custom packages
      # Accessible through 'nix build', 'nix shell', etc
      packages = forAllSystems (system: import ./pkgs (pkgsFor system));

      # Formatter for your nix files, available through 'nix fmt'
      formatter = forAllSystems (system: (pkgsFor system).nixfmt-rfc-style);

      # Your custom packages and modifications, exported as overlays
      overlays = import ./overlays {
        inherit inputs;
        inherit outputs;
      };

      ################### DevShell ####################
      #
      # Custom shell for bootstrapping on new hosts, modifying nix-config, and secrets management
      devShells = forAllSystems (system:
        let pkgs = pkgsFor system;
        in {
          default = pkgs.mkShell {
            NIX_CONFIG =
              "extra-experimental-features = nix-command flakes repl-flake";
            nativeBuildInputs = builtins.attrValues {
              inherit (pkgs)
                nix home-manager git just

                age ssh-to-age sops;
            };
          };
        });

      # SYSTEMS
      nixosConfigurations = {
        nixos = lib.nixosSystem {
          modules = [
            nix-flatpak.nixosModules.nix-flatpak
            nixos-hardware.nixosModules.lenovo-thinkpad-p14s-amd-gen2
            ./system/configuration.nix
            home-manager.nixosModules.home-manager
            {
              home-manager.useGlobalPkgs = true;
              home-manager.useUserPackages = true;
              home-manager.backupFileExtension = "backup";
              home-manager.users.tmx = {
                imports = [ ./hosts/nixos/home.nix ];
              };
              home-manager.extraSpecialArgs = specialArgs;
            }
          ];
          specialArgs = specialArgs;
        };
      };

      darwinConfigurations = {
        macos = darwin.lib.darwinSystem {
          system = "aarch64-darwin";
          specialArgs = specialArgs;
          modules = [
            ./hosts/darwin
            home-manager-darwin.darwinModules.home-manager
            {
              home-manager.useGlobalPkgs = true;
              home-manager.useUserPackages = true;
              home-manager.extraSpecialArgs = specialArgs;
              home-manager.users.${user} = import ./hosts/darwin/home.nix;
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
