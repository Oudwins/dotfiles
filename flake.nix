{
  description = "Workstations and servers";

  inputs = {
    # Stable channel for every NixOS host unless it opts into unstable.
    nixpkgs.url = "github:nixos/nixpkgs/nixos-26.05";
    # Darwin's nixpkgs, and `pkgs.unstable` everywhere (see overlays/).
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    # NixOS hosts built with `channel = "unstable"` (iss, iss-dev).
    nixos-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";

    # Private: sops files + soft secrets. SECRETS=/path/to/checkout overrides the pin in `just`.
    secrets = {
      url = "git+ssh://git@github.com/Oudwins/nix-secrets.git";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Home manager for NixOS (follows stable)
    home-manager.url = "github:nix-community/home-manager/release-26.05";
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

    sops-nix = {
      url = "github:mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Servers
    # declarative disk partitioning
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    simple-nixos-mailserver = {
      url = "gitlab:simple-nixos-mailserver/nixos-mailserver";
      inputs.nixpkgs.follows = "nixos-unstable";
    };
    hermes-agent.url = "github:NousResearch/hermes-agent/v0.23.3";
    tuwunel.url = "github:matrix-construct/tuwunel/v1.9.3";

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

  outputs =
    { self, nixpkgs, nixpkgs-unstable, ... }@inputs:
    let
      inherit (self) outputs;
      inherit (nixpkgs) lib;

      linuxSystems = [ "x86_64-linux" ];
      darwinSystems = [ "aarch64-darwin" "x86_64-darwin" ];
      forAllSystems = lib.genAttrs (linuxSystems ++ darwinSystems);

      # Darwin uses unstable, Linux uses stable. Unfree is allowed so the
      # `packages` output can build unfree custom packages (manager-server).
      pkgsFor =
        system:
        import (if builtins.elem system darwinSystems then nixpkgs-unstable else nixpkgs) {
          inherit system;
          config.allowUnfree = true;
        };

      configLib = import ./lib {
        inherit lib configLib;
        inherit (inputs) secrets;
      };
      hosts = import ./lib/hosts.nix { inherit inputs outputs configLib; };
      inherit (hosts) mkHost mkDarwinHost;
    in
    {
      # Custom packages. Accessible through 'nix build', 'nix shell', etc
      packages = forAllSystems (system: import ./pkgs (pkgsFor system));

      # Formatter for your nix files, available through 'nix fmt'
      formatter = forAllSystems (system: (pkgsFor system).nixfmt-rfc-style);

      # Custom packages and modifications, applied to every host by lib/hosts.nix
      overlays = import ./overlays { inherit inputs; };

      templates.python = {
        path = ./templates/python;
        description = "Python FHS shell";
      };

      # Shell for bootstrapping hosts, editing this config and managing secrets
      devShells = forAllSystems (
        system:
        let
          pkgs = pkgsFor system;
        in
        {
          default = pkgs.mkShell {
            NIX_CONFIG = "extra-experimental-features = nix-command flakes";
            nativeBuildInputs = builtins.attrValues {
              inherit (pkgs)
                nix
                home-manager
                git
                just
                jq
                age
                ssh-to-age
                sops
                ;
            };
            packages = [ self.packages.${system}.sv ];
          };
        }
      );

      nixosConfigurations = {
        nixos = mkHost { name = "nixos"; };
        tubby = mkHost { name = "tubby"; };
        faker = mkHost { name = "faker"; };
        rizos = mkHost { name = "rizos"; };
        vela = mkHost { name = "vela"; };
        vela-dev = mkHost { name = "vela-dev"; };
        iss = mkHost {
          name = "iss";
          channel = "unstable";
        };
        iss-dev = mkHost {
          name = "iss-dev";
          channel = "unstable";
        };
      };

      darwinConfigurations.macos = mkDarwinHost { name = "macos"; };

      # Every NixOS system plus the custom packages. `just check` evaluates them
      # (what CI runs); `just check-build` builds them.
      checks = forAllSystems (
        system:
        lib.optionalAttrs (builtins.elem system linuxSystems) (
          self.packages.${system}
          // lib.mapAttrs' (
            name: host: lib.nameValuePair "nixos-${name}" host.config.system.build.toplevel
          ) self.nixosConfigurations
        )
      );

      # Soft-secret values CI must mask before printing anything.
      ci.mask = inputs.secrets.soft.mask;
    };
}
