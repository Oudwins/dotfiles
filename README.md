# dotfiles

Dotfiles and the Nix configuration for every machine I run: the `nixos` and
`macos` workstations and the servers `tubby`, `faker`, `rizos`, `vela`,
`vela-dev`, `iss` and `iss-dev`. One flake at the repo root describes them all.
Secrets live safely encrypted in a private flake (`Oudwins/nix-secrets`, checked out at
`~/nix-secrets`), so this repo can stay public.

## Layout

```
flake.nix  justfile  lib/        hosts are listed in flake.nix via mkHost / mkDarwinHost
hosts/<name>/                    one folder per machine (+ home.nix for home-manager users)
users/<name>/                    accounts, SSH keys, home-manager entry
roles/                           import bundles: workstation, agents, server, hetzner, local-vm
modules/                         shared, nixos, darwin and home-manager modules
pkgs/  overlays/  templates/     custom packages, overlays, `nix flake init -t .#python`
home-files/tmx/                  plain config files, Stow-linked into ~
agents/{skills,commands}/        agent skills and commands
infra/  scripts/  docs/          server APIs, bootstrap scripts, docs
```

Modules are imported explicitly; importing one enables it. Per-host values are
typed `my.*` options (`modules/shared/my.nix`), with private values filled in
from nix-secrets.

## Commands

Run `just help` for the full list.

### This machine

```sh
just switch                 # build + activate this machine (nixos or macos)
./updateSymlinks.sh         # Stow-link home-files/tmx and agent skills into ~
```

### Workstation services

All bind to `127.0.0.1`. On machine, tunnel first, e.g.
`ssh -L 14321:127.0.0.1:14321 tubby`.

| Service | URL | Notes |
| --- | --- | --- |
| Agent Vault UI | http://127.0.0.1:14321 | `tmx@<my.domain>`, password is `agent-vault/owner-password` in `sops/users/tmx.yaml` |
| CLIProxyAPI (llmproxy) panel | http://127.0.0.1:8317/management.html | key is `management.secret-key` in SOPS |
| Executor | http://127.0.0.1:4788 | MCP gateway, OAuth logins for MCP servers |
| PR review server | http://127.0.0.1:7457/pr/<owner>/<repo>/<number> | pr-review-doc pages (root is 404) |
| Agent router | http://127.0.0.1:28760/<name> | `llmproxy`, `executor`, … (no UI) |

### Updating servers

```sh
just build tubby            # build a host without activating it
just deploy tubby           # activate over SSH; builds on the target if my.deploy.buildOnTarget, else locally

# bump dependencies, then roll out
just update                 # or: just update nixpkgs
just check                  # evaluate every host and package (what CI runs)
just deploy tubby           # repeat per host: faker, rizos, vela, vela-dev, iss, iss-dev

# rizos after a reboot: unlock the encrypted disk
ssh -t -p 2222 root@<rizos-address>

# clean up an aborted switch on the server
sudo systemctl stop nixos-rebuild-switch-to-configuration.service
sudo systemctl reset-failed nixos-rebuild-switch-to-configuration.service
```

### Secrets

Builds and deploys use pinned secrets by default; a local checkout is only needed
for editing. Set `SECRETS` to a checkout path to test uncommitted changes:

```sh
just secrets tubby          # edit a sops file (host, user or shared name)
just soft                   # edit soft secrets (plain values merged into my.*)
SECRETS=~/nix-secrets just deploy tubby
# then commit + push nix-secrets and pin it here:
just update secrets
```

Commit and push the updated `flake.lock`. Other machines only need to pull dotfiles
and run `just switch`; Nix fetches the matching secrets automatically.

### New machines

```sh
just bootstrap vps iss root@<ip> -k ~/.ssh/id_ed25519   # kind: vm | vps | encrypted
```

Bootstrap uses the pinned secrets, so push nix-secrets and run
`just update secrets` first. Nix only sees git-tracked files: `git add -N` new
files before building.

## Docs

- [Secrets](docs/secrets.md)
- [Agent commands and skills](docs/agent-skills.md)
- [Agent Vault, agent service routing and Executor](docs/agent-vault.md)
- [CLIProxyAPI](docs/cli-proxy-api.md)
- [Servers](docs/servers/README.md), [encrypted servers](docs/servers/encrypted-servers.md), [dependency updates](docs/servers/dependency-updates.md)
- [Notes](docs/notes.md)
