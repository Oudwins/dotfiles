# Lint

`just lint` checks the repo's architecture rules, formatting, dead code and
shell scripts. CI runs it on every push and pull request
(`.github/workflows/lint.yml`). It needs no secrets.

| Tool | Checks | Configuration |
| --- | --- | --- |
| [ast-grep](https://ast-grep.github.io) | The architecture rules below | `sgconfig.yml`, `lint/rules/`, `lint/rule-tests/` |
| [statix](https://github.com/oppiliappan/statix) | Nix anti-patterns | `statix.toml` |
| [nixfmt](https://github.com/NixOS/nixfmt) | Nix formatting | `treefmt.toml` |
| [deadnix](https://github.com/astro/deadnix) | Unused Nix bindings and arguments | `treefmt.toml` |
| [shellcheck](https://www.shellcheck.net) | Every tracked `*.sh` | `treefmt.toml` |

## Baselines

Files that already failed a check when it was added are listed in that check's
baseline: `ignores` in a rule file, `ignore` in `statix.toml`, `excludes` in
`treefmt.toml`. A baseline exempts the whole file from that one check. Fix the
file, then remove its entry. Never add an entry.

A single deliberate exception goes on the line above the code instead:

```nix
# ast-grep-ignore: nix-reads-ci-skipped-path
```

## Architecture rules

Each rule is one file in `lint/rules/`, with test cases like the examples here
in `lint/rule-tests/`. `just lint` runs those tests first.

### sops-secrets-in-module

A module under `modules/` takes a secret as a file path. The host, user or role
declares the sops secret and passes its path.

```nix
# Bad: modules/nixos/services/memos/default.nix
sops.secrets."memos/env_file" = { };
systemd.services.memos.serviceConfig.EnvironmentFile = config.sops.secrets."memos/env_file".path;

# Good: the module only has an option ...
options.services.memos.environmentFile = lib.mkOption { type = lib.types.path; };
# ... and hosts/faker/default.nix fills it
sops.secrets."memos/env_file" = { };
services.memos.environmentFile = config.sops.secrets."memos/env_file".path;
```

### secrets-input-outside-lib

Only `lib/` and `flake.nix` touch `inputs.secrets`. Anything else goes through
`configLib.secretFile`, which copies one file into the store instead of the
whole secrets repo.

```nix
# Bad
sops.defaultSopsFile = "${inputs.secrets}/sops/hosts/rizos.yaml";

# Good
sops.defaultSopsFile = configLib.secretFile "sops/hosts/rizos.yaml";
```

### my-option-outside-my-nix

`my.*` options are declared in `modules/shared/my.nix`. A module's own options
go under `services.<name>` or `programs.<name>`. Setting a `my.*` value is fine
anywhere.

```nix
# Bad: modules/nixos/services/memos/default.nix
options.my.memos.environmentFile = lib.mkOption { type = lib.types.path; };

# Good
options.services.memos.environmentFile = lib.mkOption { type = lib.types.path; };
```

### module-imports-upward

Hosts import roles, users and modules. A module never imports from `hosts/`,
`roles/` or `users/`.

```nix
# Bad: modules/nixos/core/server-base/default.nix
imports = [ ../../../users/tmx/server.nix ];
imports = [ (configLib.relativeToRoot "roles/server") ];

# Good: the host imports both
imports = [
  (configLib.relativeToRoot "modules/nixos/core/server-base")
  (configLib.relativeToRoot "users/tmx/server.nix")
];
```

### agent-module-outside-agents-role

`roles/agents.nix` is the only file that imports the agent modules:
`modules/shared/cli-proxy-api` and `executor`, `agent-vault`,
`pr-review-server`, `npm-global` and `t3code` under `modules/home/common/`.

```nix
# Bad: hosts/rizos/home.nix
imports = [ ../../modules/home/common/executor ];

# Good: hosts/rizos/default.nix
imports = [ (configLib.relativeToRoot "roles/agents.nix") ];
```

### home-identity-set

home-manager derives `home.username` and `home.homeDirectory` from
`users.users.<name>`.

```nix
# Bad
home.username = "tmx";
home.homeDirectory = "/home/tmx";

# Good: set neither; read them where needed
home.file.".foo".text = config.home.homeDirectory;
```

### nix-reads-ci-skipped-path

`.github/workflows/check.yml` does not run for changes under `home-files/`,
`agents/`, `docs/`, `tests/`, `scripts/`, `infra/`, `assets/`, `ssh/` or
`lint/`. If Nix reads a file there, a change to it is never built. Move the
file, or re-include it in the workflow's `paths` and in this rule, as
`docs/hosts-file` is.

```nix
# Bad: roles/agents.nix
agentVaultConfig = lib.importJSON ../home-files/tmx/.config/agent-vault/config.json;

# Good: hosts/nixos/default.nix (re-included in check.yml)
networking.extraHosts = builtins.readFile ../../docs/hosts-file;
```

### command-is-model-invocable

Every `agents/commands/<name>/SKILL.md` disables model invocation. An entry the
model may pick up on its own belongs in `agents/skills/`.

```markdown
<!-- Bad -->
---
name: commit
description: Create focused git commits.
---

<!-- Good -->
---
name: commit
description: Create focused git commits.
disable-model-invocation: true
---
```

### command-allows-implicit-invocation

Every `agents/commands/<name>/agents/openai.yaml` says the same for Codex.

```yaml
# Bad
policy:
  allow_implicit_invocation: true

# Good
policy:
  allow_implicit_invocation: false
```

## Not checked

These rules from `AGENTS.md` have no linter and still rely on review:

- No private value (domain, email, address) in a tracked file.
- No path managed by both Stow and Nix.
- A `my.*` option only where no NixOS or home-manager option exists.
- Agent entry names matching their directory. `updateSymlinks.sh` does reject
  a name used in both `agents/skills` and `agents/commands`.

The architecture rules match syntax. They miss a secret, option or import that
is built dynamically.
