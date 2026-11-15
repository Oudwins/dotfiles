> Moved here from the former `servers` repo. Hosts now live in `hosts/<name>` (vela/vela-dev and iss/iss-dev are separate folders), secrets in the private nix-secrets repo, and CI in `.github/workflows/check.yml`. Use `just deploy <host>` and `just bootstrap <vm|vps|encrypted> <host> <destination>` instead of the raw commands below.

# Dependency updates and build checks

Renovate opens dependency merge requests. GitLab CI builds the declared Nix
artifacts before you merge. Nothing is merged or deployed automatically, and
there is no minimum release-age restriction.

## Build checks

Merge-request pipelines and default-branch pipelines run:

```sh
nix flake check --no-update-lock-file --keep-going --print-build-logs
```

`checks.x86_64-linux` is derived from the flake's existing outputs:

- Every `nixosConfigurations` entry becomes a `nixos-<host>` check that builds
  the complete system toplevel.
- Every `packages.x86_64-linux` entry is also built, including packages not
  currently used by a server.

Adding a host or exported package automatically includes it in CI. The lockfile
must already be up to date; CI will not regenerate it. Independent builds
continue after a build failure, but the job still fails.

These are build checks, not runtime or deployment tests. In particular, a
successful NixOS build does not pull or validate container images referenced by
name, test database migrations, or decrypt production secrets. System closures
are not uploaded as GitLab artifacts in this initial setup.

The jobs use GitLab's Linux amd64 container runners and the public Nix binary
cache. No production SSH keys, SOPS decryption keys, or privileged containers
are required. Runner eligibility, available disk space, and CI minutes still
apply; the build job has a three-hour timeout and an initially cold Nix store.

## Enable the scheduled updater

After merging this configuration:

1. Protect the default branch. Require merge requests, disable direct pushes,
   and enable **Pipelines must succeed** in the project's merge checks. The bot
   does not need permission to merge into the default branch.
2. Create a GitLab project access token with the **Developer** role and `api`
   scope, or use a dedicated bot account's personal access token with equivalent
   project access. A CI job token is not a substitute for this token.
3. Add it under **Settings > CI/CD > Variables** as `RENOVATE_TOKEN`. Mark it
   **Masked** and **Protected**, and set its environment scope to `renovate`.
   Only the scheduled updater job declares that environment, so build and
   validation jobs do not receive the token, even on the default branch.
4. Add a read-only GitHub token as `RENOVATE_GITHUB_COM_TOKEN`, with the same
   masking, protection, and environment scope. This is recommended for GitHub
   changelogs, tool downloads, and API rate limits; it needs no repository write
   permissions.
5. Under **Build > Pipeline schedules**, create a schedule targeting the protected
   default branch. For example, `0 3 * * 1` runs weekly at 03:00 in the timezone
   selected for the schedule. The schedule owner must be allowed to run pipelines
   on that protected branch.
6. Run the schedule once manually and inspect the `renovate` job. You can set
   `RENOVATE_DRY_RUN=full` as a schedule variable for an initial read-only run;
   remove it to allow branches, issues, and merge requests to be created.

The schedule runs only Renovate. The resulting merge requests run the build
and configuration-validation jobs. Regular default-branch pipelines run those
checks too. Renovate itself runs on GitLab CI, not on any of the managed servers.
Its image installs the Nix tooling required for lockfile updates at runtime.

## Update coverage

- Renovate refreshes `flake.lock` within the input references declared in
  `flake.nix`. NixOS release-channel changes are disabled; advancing the revision
  within an existing channel is allowed.
- The GitLab CI manager updates the pinned CI images.
- A custom manager updates literal tagged container images in `hosts/**/*.nix`
  and `modules/**/*.nix`, such as `image = "neosmemo/memos:0.29.1";` or
  `nginxImage = "nginx:alpine";`. Unused Nextcloud documentation is excluded.
- Other natively supported dependency files, such as Terraform configuration
  and Go modules, use Renovate's recommended defaults.

The following still need manual updates or dedicated updaters:

- Flake inputs explicitly pinned to release tags, such as `hermes-agent` and
  `tuwunel`: refreshing the lockfile does not select a newer release tag.
- Container versions interpolated from variables or module options, composite
  tags such as OpenLiteSpeed/PHP, and digest-only image references.
- Mutable image tags such as `latest` and `alpine` are not immutable pins. A
  changed image behind the same tag is not reliably represented by a code diff.
- Custom Nix package versions, source hashes, and dependency hashes under `pkgs/`.
- WordPress core, plugins, and themes managed inside running instances.

Auto-merge is explicitly disabled. Failed updates remain open for review; there
is no deployment, rollback, or production access in this workflow.