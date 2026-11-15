# Secrets

`~/nix-secrets` (private) holds:

- `sops/{hosts,users,shared}/*.yaml`: sops-encrypted secrets. Each host names
  the files it uses, e.g. `sops.defaultSopsFile = configLib.secretFile "sops/hosts/tubby.yaml";`.
  `secretFile` copies only that file into the store, so no machine receives
  other machines' ciphertext or the soft secrets.
- `soft/default.nix`: private plain values (domain, email, deploy addresses).
  They are applied to every host's `my.*` options (global, then per host). Values
  are masked in public CI logs unless wrapped in `public`.
- `.sops.yaml`: recipients for each file.

CI (`.github/workflows/check.yml`) needs the read-only deploy key secret
`NIX_SECRETS_DEPLOY_KEY`; it masks every soft secret before printing anything.

## Local vs pinned secrets

Recipes use `~/nix-secrets` directly, including uncommitted edits, so secrets
changes apply without pushing. `SECRETS=pinned just …` uses the revision locked in
`flake.lock` instead; bump it with `just update secrets` after pushing nix-secrets.
Plain `nixos-rebuild switch --sudo --flake .#<host>` also works against the pin.
New secrets files must be known to git (`just secrets` runs `git add -N` for you).
For a different master key, e.g. iss: `MASTER_KEY=/etc/ssh/iss_ssh_master_key just bootstrap …`.
