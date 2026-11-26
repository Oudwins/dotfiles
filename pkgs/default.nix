# Custom packages, that can be defined similarly to ones from nixpkgs
# You can build them using 'nix build .#example'
pkgs: rec {
  # example = pkgs.callPackage ./example { };
  artifact = pkgs.callPackage ./artifact/package.nix { };
  beads = pkgs.callPackage ./beads/package.nix { };
  btca = pkgs.callPackage ./btca/package.nix { };
  cli-proxy-api = pkgs.callPackage ./cli-proxy-api/package.nix { };
  executor = pkgs.callPackage ./executor/package.nix { };
  jsonc2json = pkgs.callPackage ./jsonc2json/package.nix { };
  agent-vault = pkgs.callPackage ./agent-vault/package.nix { };
  agent-vault-service = pkgs.callPackage ./agent-vault-service/package.nix { inherit agent-vault; };
  agent-vault-clients = pkgs.callPackage ./agent-vault-clients/package.nix { };
  agent-vault-router = pkgs.callPackage ./agent-vault-router/package.nix { };
  pr-review-server = pkgs.callPackage ./pr-review-server/package.nix { };
  t3code = pkgs.callPackage ./t3code/package.nix { };

  # Servers
  manager-server = pkgs.callPackage ./managerio { };
  wifi-control = pkgs.callPackage ./wifi-control { };

  sv = pkgs.writeShellApplication {
    name = "sv";
    runtimeInputs = [ pkgs.mkpasswd ];
    text = ''
            set -euo pipefail

            usage() {
              cat <<'EOF'
      Usage:
        sv hashpassword [password]

      Examples:
        sv hashpassword
        sv hashpassword my-secret-password
      EOF
            }

            command=''${1:-}
            if [[ -z "$command" ]]; then
              usage
              exit 1
            fi

            shift

            case "$command" in
              hashpassword)
                if [[ $# -eq 0 ]]; then
                  exec mkpasswd -sm bcrypt
                fi

                exec printf '%s' "$*" | mkpasswd -sm bcrypt -s
                ;;
              *)
                usage
                exit 1
                ;;
            esac
    '';
  };
}
