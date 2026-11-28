## What is this repo
This repo contains dotfiles for user and the Nix configuration of every machine
they run (workstations `nixos` and `macos`, and the servers). It is public;
secrets live in the private `Oudwins/nix-secrets` flake (checked out at
`~/nix-secrets`).

Breakdown of key directories:
```bash
# the flake; hosts are listed here via mkHost / mkDarwinHost (lib/hosts.nix)
flake.nix lib/
# one folder per machine, plus home.nix declaring that host's home-manager users
hosts/<name>/
# accounts, SSH public keys and home-manager entry per user
users/<name>/
# import bundles a host opts into (workstation, agents, server, hetzner, local-vm)
roles/
# shared (nixos+darwin), nixos/{core,desktop,services,hardware}, darwin, home/{common,linux,darwin}
modules/
# plain-file dotfiles, Stow-linked recursively: home-files/tmx/.config -> ~/.config
home-files/tmx/*
# automatic skills and manually invoked commands, linked into ~/.agents/skills
# and ~/.claude/skills by updateSymlinks.sh
agents/{skills,commands}/*
# architecture rules checked by `just lint` (ast-grep), explained in docs/lint.md
sgconfig.yml lint/{rules,rule-tests}/
# everyday commands: switch, deploy, build, bootstrap, secrets, update, check, lint
justfile
```

## Configuration management

- Nix configuration lives at the repo root (`flake.nix`, `hosts/`, `modules/`,
  …) and primarily manages packages and services. Modules are imported
  explicitly; importing a module enables it.
- Per-host values are typed `my.*` options declared in `modules/shared/my.nix`.
  Private values (domain, email, deploy addresses) come from nix-secrets
  `soft/default.nix` and are applied automatically; a host overrides with a plain
  assignment. Never hardcode private values in this public repo. Domains a host
  serves (websites, mail) go in soft secrets as `my.domains.<neutral key>` and
  are used as `"postmaster@${config.my.domains.main}"`; the key must not reveal
  the domain.
- Only add a `my.*` option when no NixOS/home-manager option already exists for
  it. Per-device settings that have one (`time.timeZone`, `i18n.*`,
  `services.openssh.ports`, …) are set directly in `hosts/<name>/`, and modules
  read them from there (e.g. `default = config.time.timeZone`).
- Sops secrets live in nix-secrets under `sops/{hosts,users,shared}/`. Reference
  them only through `configLib.secretFile "sops/…"`, never by interpolating
  `inputs.secrets`, which would copy the whole secrets repo into the store.
- Modules take secrets as file paths, never as sops secret names. The host (or
  user) declares `sops.secrets."<name>"` itself and passes
  `config.sops.secrets."<name>".path`; a module must not declare sops secrets
  from names in its options.
- Keep the usual layout for agent tooling too: packages in `pkgs/`, services
  and modules under `modules/`. `roles/agents.nix` imports and wires them;
  a host that wants agents imports that role and sets its options there.
- Don't restate values Nix already derives. For example, home-manager sets
  `home.username` and `home.homeDirectory` from `users.users.<name>`, so don't
  set them per host.
- Most application settings are **not managed by Nix**. Store them under
  `home-files/tmx/` using the same relative path they should have in the user's
  home directory. For example, `home-files/tmx/.config/app/config.yaml` becomes
  `~/.config/app/config.yaml`.
- GNU Stow creates symlinks from the home directory to these files; it does not
  move or copy them. Run `./updateSymlinks.sh` from this repository to apply them.
  The script restows `home-files/tmx` and links every agent entry.
- Agent skills and commands are an exception to the `home-files/` source layout:
  store them in `agents/skills/<name>/` and `agents/commands/<name>/`,
  respectively. Both use `SKILL.md`; commands also require
  `disable-model-invocation: true` in its frontmatter and
  `policy.allow_implicit_invocation: false` in `agents/openai.yaml`. Keep
  directory names and skill names identical and unique across both folders.
  A skill only some hosts should have (because it needs a tool only they
  install) goes in `agents/nix-skills/<name>/` instead, which updateSymlinks.sh
  skips; the module that installs the tool links it with `home.file`.
- Keep mutable settings in the Stow-managed files rather than generating them
  with Nix/Home Manager, unless that application's configuration is explicitly
  Nix-managed already. Do not manage the same path with both Stow and Nix.
- Files containing credentials should remain Git-ignored. Track a starter template
  instead, keeping the actual settings file local and ignored. Keep generated
  OAuth credentials outside the Stow tree.
- Paths to files in this repo inside configs use `$HOME/dotfiles/...` style
  absolute paths rather than relative ones.
- `just lint` enforces the rules above that a linter can check; `docs/lint.md`
  lists them with examples. Run it after changing Nix files, agent entries or
  shell scripts. A file in a check's baseline already fails it: fix the file and
  remove the entry, never add one.
