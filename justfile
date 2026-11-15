# Everyday commands for every machine in this repo.
#
# Secrets come from the private nix-secrets flake. By default every recipe uses
# the local checkout at ~/nix-secrets (including uncommitted edits); run with
# SECRETS=pinned to use the revision locked in flake.lock instead. `bootstrap`
# always uses the locked revision (nixos-anywhere can't override inputs), so
# push nix-secrets and run `just update secrets` before bootstrapping.

set shell := ["bash", "-euo", "pipefail", "-c"]
set positional-arguments

repo := justfile_directory()
secrets_dir := env("NIX_SECRETS_DIR", home_directory() / "nix-secrets")
override := if env("SECRETS", "local") == "pinned" { "" } else { "--override-input secrets git+file://" + secrets_dir }

# List recipes
default:
    @just --list

# Build and activate this machine (nixos or macos)
switch *args:
    #!/usr/bin/env bash
    set -euo pipefail
    if [[ $(uname) == Darwin ]]; then
      # Evaluate and build as the user so the private input is fetched with
      # your SSH agent; only activation runs as root.
      system=$(nix build --no-link --print-out-paths "{{repo}}#darwinConfigurations.macos.system" {{override}} "$@")
      sudo nix-env -p /nix/var/nix/profiles/system --set "$system"
      sudo "$system/activate"
    else
      nixos-rebuild switch --sudo --flake "{{repo}}#$(hostname)" {{override}} "$@"
    fi

# Build a host without activating it
build host *args:
    nix build --no-link --print-out-paths "{{repo}}#nixosConfigurations.{{host}}.config.system.build.toplevel" {{override}} "${@:2}"

# Deploy a server over SSH, using the host's my.deploy settings
deploy host *args:
    #!/usr/bin/env bash
    set -euo pipefail
    deploy=$(nix eval --json "{{repo}}#nixosConfigurations.{{host}}.config.my.deploy" {{override}})
    target_host=$(jq -r .host <<<"$deploy")
    if [[ $target_host == null ]]; then
      echo "{{host}} has no my.deploy.host; set it in nix-secrets soft/ or hosts/{{host}}." >&2
      exit 1
    fi
    target="$(jq -r .user <<<"$deploy")@$target_host"
    flags=(--target-host "$target")
    [[ $(jq -r .buildOnTarget <<<"$deploy") == true ]] && flags+=(--build-host "$target")
    [[ $(jq -r .user <<<"$deploy") != root ]] && flags+=(--sudo)
    export NIX_SSHOPTS="${NIX_SSHOPTS:-} -p $(jq -r .port <<<"$deploy")"
    nixos-rebuild switch --flake "{{repo}}#{{host}}" {{override}} "${flags[@]}" "${@:2}"

# Install NixOS on a new machine: kind is vm, vps or encrypted (see scripts/bootstrap-*.sh)
bootstrap kind host destination *args:
    #!/usr/bin/env bash
    set -euo pipefail
    # The scripts run as you (so Nix can fetch the private secrets input with
    # your SSH agent); only reading the root-owned master key needs sudo.
    key=$(mktemp)
    trap 'rm -f "$key"' EXIT
    sudo cat "${MASTER_KEY:-/etc/ssh/ssh_master_key}" > "$key"
    cd "{{repo}}"
    ./scripts/bootstrap-{{kind}}.sh -n "{{host}}" -d "{{destination}}" --source-master-key "$key" "${@:4}"

# Edit a sops file in ~/nix-secrets: a host, user or shared name, or a path under sops/
secrets name:
    #!/usr/bin/env bash
    set -euo pipefail
    cd "{{secrets_dir}}"
    file=""
    case "{{name}}" in
      */*|*.yaml) file="sops/{{name}}"; [[ $file == *.yaml ]] || file="$file.yaml" ;;
      *) for kind in hosts users shared; do
           [[ -e sops/$kind/{{name}}.yaml ]] && { file="sops/$kind/{{name}}.yaml"; break; }
         done ;;
    esac
    if [[ -z $file ]]; then
      echo "No sops file for '{{name}}'. Use a path such as hosts/{{name}} to create one." >&2
      exit 1
    fi
    mkdir -p "$(dirname "$file")"
    nix develop "{{secrets_dir}}" -c sops "$file"
    # New files are untracked; make them visible to git+file flake inputs.
    git add --intent-to-add -- "$file"

# Edit the soft secrets (plain values merged into my.*)
soft:
    "${EDITOR:-vi}" "{{secrets_dir}}/soft/default.nix"

# Update flake inputs (all, or the ones given)
update *inputs:
    nix flake update --flake "{{repo}}" "$@"

# Evaluate every host and package (what CI runs). Not `nix flake check
# --no-build`: some modules need small builds during evaluation (shiori's key,
# hermes-agent's package.json), which --no-build refuses.
check:
    nix eval --raw "{{repo}}#checks.x86_64-linux" {{override}} \
      --apply 'cs: builtins.concatStringsSep "\n" (builtins.attrValues (builtins.mapAttrs (n: d: n + " " + d.drvPath) cs)) + "\n"'

# Build every host and package
check-build:
    nix flake check "{{repo}}" {{override}}
