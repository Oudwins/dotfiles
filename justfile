# Everyday commands for every machine in this repo.
#
# Secrets come from the private nix-secrets flake, pinned in flake.lock.
# Set SECRETS to a local checkout path to include uncommitted edits instead.
# `bootstrap` always uses the locked revision (nixos-anywhere can't override
# inputs), so run `just secrets-push` before bootstrapping.

set shell := ["bash", "-euo", "pipefail", "-c"]
set positional-arguments

repo := justfile_directory()
secrets := env("SECRETS", "")
secrets_dir := absolute_path(if secrets == "" { home_directory() / "nix-secrets" } else { secrets })
override := if secrets == "" { "" } else { "--override-input secrets " + quote("git+file://" + secrets_dir) }

# List recipes
default:
    @just --list

# How to use these recipes
help:
    #!/usr/bin/env bash
    cat <<'EOF'
    Everyday
      just switch              build and activate this machine (nixos or macos)
      just deploy <host>       deploy a server over SSH (address, user and port from my.deploy)
      just build <host>        build a host without activating it
      just check               evaluate every host and package (what CI runs)
      just check-build         build every host and package
      just lint                check the architecture rules, formatting, dead code and
                               shell scripts (see docs/lint.md)

    Secrets (private repo, checked out at ~/nix-secrets)
      just secrets <name>      edit a sops file: a host (tubby), user (tmx) or shared
                               (wifi-control) name, or a path such as hosts/new-host
      just soft                edit the soft secrets (plain values merged into my.*)
      just secrets-push [msg]  commit pending edits (msg defaults to the changed files),
                               push nix-secrets and lock flake.lock to the pushed revision
      Builds and deploys use the revision locked in flake.lock by default.
      Set SECRETS to a checkout path to include uncommitted edits instead:
        SECRETS=~/nix-secrets just switch
      Editing commands use ~/nix-secrets unless SECRETS is set.
      After editing: just secrets-push ["<message>"]

    Inputs
      just update              update every flake input
      just update <input>...   update only those inputs (e.g. nixpkgs secrets)

    New machines
      just bootstrap <vm|vps|encrypted> <host> <user@address> [script options]
      Uses the pinned secrets, so run `just secrets-push` first.
      Reads the master key with sudo (override with MASTER_KEY=/path/to/key).

    Good to know
      - Nix only sees files git tracks. Register a new file with `git add -N <file>`
        before building; never use a path: flake ref (it copies gitignored
        credentials into the Nix store).
      - First switch on a machine without just: nix run nixpkgs#just -- switch
      - `just` alone lists every recipe.
    EOF

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
         done
         # A new file: the kind whose path a .sops.yaml creation rule covers.
         [[ -n $file ]] || for kind in hosts users shared; do
           while read -r regex; do
             [[ sops/$kind/{{name}}.yaml =~ $regex ]] && { file="sops/$kind/{{name}}.yaml"; break 2; }
           done < <(sed -n 's/^ *- path_regex: //p' .sops.yaml)
         done ;;
    esac
    if [[ -z $file ]]; then
      echo "No sops file or .sops.yaml creation rule for '{{name}}'. Use a path such as hosts/{{name}} to create one." >&2
      exit 1
    fi
    mkdir -p "$(dirname "$file")"
    nix develop "{{secrets_dir}}" -c sops "$file" || [[ $? -eq 200 ]]
    # New files are untracked; make them visible to git+file flake inputs.
    git add --intent-to-add -- "$file"

# Edit the soft secrets (plain values merged into my.*)
soft:
    "${EDITOR:-vi}" "{{secrets_dir}}/soft/default.nix"

# Commit pending edits and push nix-secrets, then lock flake.lock to it
secrets-push message="":
    #!/usr/bin/env bash
    set -euo pipefail
    cd "{{secrets_dir}}"
    # Tracked and intent-to-add files only (what `just secrets` registers).
    if [[ -n $(git status --porcelain --untracked-files=no) ]]; then
      files=$(git diff --name-only HEAD)
      git commit -a -m "${1:-Update ${files//$'\n'/, }}"
    fi
    git pull --rebase
    git push
    nix flake update --flake "{{repo}}" secrets

# Update flake inputs (all, or the ones given)
update *inputs:
    nix flake update --flake "{{repo}}" "$@"

# Not `nix flake check --no-build`: hermes-agent needs a small build during
# evaluation (it reads package.json from a fetched source), which that refuses.
# Evaluate every host and package (what CI runs); CI also passes an older revision to diff against
check flake=repo:
    nix eval --raw "{{flake}}#checks.x86_64-linux" {{override}} \
      --apply 'cs: builtins.concatStringsSep "\n" (builtins.attrValues (builtins.mapAttrs (n: d: n + " " + d.drvPath) cs)) + "\n"'

# Build every host and package
check-build:
    nix flake check "{{repo}}" {{override}}

# The linters come from this flake's locked inputs without evaluating the flake,
# so this needs no secrets. Only nixpkgs-unstable's ast-grep reads Markdown.
# Check the architecture rules, formatting, dead code and shell scripts (see docs/lint.md)
lint:
    #!/usr/bin/env bash
    set -euo pipefail
    cd "{{repo}}"
    nix shell --inputs-from . nixpkgs-unstable#ast-grep nixpkgs#statix nixpkgs#treefmt \
      nixpkgs#nixfmt nixpkgs#deadnix nixpkgs#shellcheck -c bash -c '
        status=0
        ast-grep test --skip-snapshot-tests || status=1
        ast-grep scan || status=1
        statix check || status=1
        treefmt --ci || status=1
        exit $status
      '
