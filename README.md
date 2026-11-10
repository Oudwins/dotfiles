## Agent commands and skills

Commands and automatically selected skills live in separate Stow packages:

- `agent-commands/.agents/skills/<name>/`: manually invoked commands.
- `agent-skills/.agents/skills/<name>/`: ordinary skills.

Each directory contains `SKILL.md` with `name` and `description` frontmatter,
plus any supporting files. Commands additionally set
`disable-model-invocation: true` in that frontmatter and include
`agents/openai.yaml` containing:

```yaml
policy:
  allow_implicit_invocation: false
```

Run `./updateSymlinks.sh` to merge both packages into `~/.agents/skills/`.
Each package also has `.claude/skills/<name>` symlinks pointing to its canonical
`.agents/skills/<name>` directories, exposing the same collection to Claude Code.
Invoke commands
with `/name` in Claude Code or `$name` in Codex. Pi's prompts link points only to
the commands package through `tmx/.agents/commands`; its directory-prompts
extension provides `/name` commands with companion-file support.

Edit the source package directly; nothing is generated or copied. Use matching
kebab-case directory and skill names, unique across both packages. When adding a
command, also add its Claude link (use `agent-skills` for an ordinary skill):

```sh
ln -s ../../.agents/skills/my-command agent-commands/.claude/skills/my-command
./updateSymlinks.sh
```

The former
`research_basic` and `research_basic_inline` prompts are now `research-basic`
and `research-basic-inline`. Existing filename-based names are otherwise kept.
Use ordinary user instructions for inputs and ask the agent to run shell commands
as part of the workflow rather than relying on client-specific substitutions.
OpenCode's commands link is retained, but directory-format commands are not
adapted for OpenCode.

The Stow script uses its own checkout as the common Stow directory, allowing
Stow to merge shared destination directories across packages. It can be rerun
after adding or removing commands and their Claude links. It also migrates links
from the previous single-package layout; unrelated files in
the home directory remain subject to Stow's normal conflict checks.
Git-ignored untracked files are excluded automatically; tracked files remain
included. Normal Stow directory folding is retained: ignored files inside a
linked directory remain accessible through that link. Preview changes with
`./updateSymlinks.sh --simulate`.

### Imported tstack skills

Imported from [t3dotgg/tstack](https://github.com/t3dotgg/tstack/tree/1085050f3baed1ac724caa4a8166145fb2ac88af/skills), with MIT licenses included:

All seven are ordinary skills in `agent-skills/.agents/skills/`: `babysit-pr`,
`council`, `file-pr`, `full-send`, `full-stop`, `leaving-pr-comments`, and `sol-loop`.

`modernize` and `takeover` are intentionally excluded.

## To add at some point
- https://github.com/junhoyeo/tokscale


```bash
# Connect to tubby
sudo tailscale set --exit-node=tubby
# Disconnect
sudo tailscale set --exit-node=

```



## Macos

```bash
sudo darwin-rebuild switch --flake .#macos
```

- Aerospace WM
  - https://www.youtube.com/watch?v=5nwnJjr5eOo&t=647s
  - sketchybar
  - sketchyBorder or something like that
- Allacritty Terminal -> or ghostty
  - Starship
- Raycast
  - Disable spotlight
- Cursor
- https://github.com/koekeishiya/skhd
  - Hotkeys to launch apps
- remap keys
  - https://github.com/pqrs-org/Karabiner-Elements
- Direnv
- screenshot tool -> Shottr

- Finder show path bar



## nix

```bash
# quickly test the build of a specific package
nix-build --expr '(import <nixpkgs> { }).callPackage ./package.nix { }'
```
# Notes

## CLIProxyAPI (macOS and Linux)

Nix builds CLIProxyAPI from source and runs it as a system daemon under a dedicated
account: `cli-proxy-api` on NixOS, `_cliproxyapi` on macOS. A root launcher decrypts
SOPS and prepares private runtime files, then permanently drops UID/GID before
executing the proxy. Your login user is not a member of the service group.

Ordinary settings in `tmx/.cli-proxy-api/config.yaml` are tracked and Stow-linked to
`~/.cli-proxy-api/config.yaml`. Secrets live in **SOPS-encrypted**
`nixos/secrets/cli-proxy-api.yaml`. Only ciphertext and scripts enter the Nix store;
Nix never decrypts or interpolates secret values during evaluation/build.

The launcher merges them at runtime (including login commands). Nested mappings
merge and lists replace, except upstream `api-keys.<provider>` groups merge by
unique, nonempty `name`. The resulting mode-600 config is owned by the service user:

- NixOS: `/run/cli-proxy-api/config.yaml` on tmpfs; startup refuses other filesystems.
- macOS: `/private/var/run/cli-proxy-api/config.yaml` on a root-mounted 32 MiB HFS RAM
  disk. Startup verifies an existing mount is a RAM disk and never falls back to `/tmp`.

The runtime directory is root-owned, mode 750, with only the service group allowed
to enter. Plaintext staging files are root-only and removed after merging. Only API
keys and the management secret use this RAM-backed config. OAuth files persist in
`/var/lib/cli-proxy-api/auth`, owned by the service account with directory mode 700;
logs/panel assets also use `/var/lib/cli-proxy-api`.
`--config /another/file.yaml` explicitly bypasses the merge and persistent auth-path
override; securing that file and its OAuth directory is then your responsibility.

### Initial setup

The encrypted file is shared by both machines. To import an existing local secrets
file without making another plaintext copy (do not overwrite an existing SOPS file):

```bash
cd ~/dotfiles/nixos
test ! -e secrets/cli-proxy-api.yaml &&
  sops --encrypt --filename-override secrets/cli-proxy-api.yaml \
    ../tmx/.cli-proxy-api/secrets.yaml > secrets/cli-proxy-api.yaml
```

For a fresh setup, use `../tmx/.cli-proxy-api/secrets.example.yaml` as the input instead,
then edit with SOPS. Put a real client key in `access.api-keys`; an empty list means
no client authentication. `sops`' interactive editor uses a temporary plaintext
file: on NixOS, set `TMPDIR="$XDG_RUNTIME_DIR"` when editing. On macOS, use a private
RAM disk as `TMPDIR`, or use `sops set --value-stdin` to avoid editor temporary files.
Do not pass secret values as command-line arguments or put them in shell history.

The daemon converts `~/.ssh/id_ed25519` to an age identity at runtime by default.
Both machines' SSH-derived recipients are in `nixos/.sops.yaml`; add other machines'
recipients and run `sops updatekeys secrets/cli-proxy-api.yaml` before rebuilding.
For manual SOPS commands, if you do not already have an age identity configured,
use `export SOPS_AGE_KEY="$(ssh-to-age -private-key -i ~/.ssh/id_ed25519)"` first.

On macOS the hidden account defaults to UID/GID 493. Verify these are unused, or set
`services.cli-proxy-api.darwinUid` to a free ID before the first rebuild.

```bash
cd ~/dotfiles
stow --no-folding -d tmx -t ~ .
# Git-backed flakes only include tracked files. Stage the new module/helpers and
# encrypted file first, or evaluate a clean source snapshot containing them.

# macOS
sudo darwin-rebuild switch --flake ./nixos#macos
# Linux / NixOS
sudo nixos-rebuild switch --flake ./nixos#nixos
```

Commit ordinary settings and the encrypted SOPS file, never plaintext secrets or
private identities. Without a real client key, the tracked placeholder disables
proxy endpoints. `secrets.example.yaml` is only a starter template.

When migrating, stop the old user service before starting the system daemon:

```bash
# NixOS
systemctl --user disable --now cli-proxy-api
# macOS
launchctl bootout "gui/$(id -u)/org.nix-community.home.cli-proxy-api"
```

After verifying SOPS decryption and the new service, remove the old plaintext
`tmx/.cli-proxy-api/secrets.yaml`, its `~/.cli-proxy-api/secrets.yaml` link, and
`~/.local/state/cli-proxy-api/config.yaml`. Old OAuth files in
`~/.local/share/cli-proxy-api/auth` are not automatically migrated or deleted.
To keep those existing logins, stop the proxy before copying them into the new
persistent directory (after rebuilding has created the dedicated account):

```bash
service_user=cli-proxy-api # Use _cliproxyapi on macOS.
sudo install -d -m 700 -o "$service_user" -g "$service_user" /var/lib/cli-proxy-api/auth
sudo cp -R ~/.local/share/cli-proxy-api/auth/. /var/lib/cli-proxy-api/auth/
sudo chown -R "$service_user:$service_user" /var/lib/cli-proxy-api/auth
sudo chmod -R u=rwX,go= /var/lib/cli-proxy-api/auth
```

The new launcher never reads these legacy files. Deletion cannot undo old backups
or SSD snapshots; rotate credentials if that matters.

**Security boundary:** another Unix account prevents ordinary processes running as
your login user from reading the runtime paths or the proxy's process memory.
It does not protect secrets from root/sudo, someone holding a SOPS decryption key,
or someone with the management API password. Your mutable settings also remain
trusted input: a hostile user who controls them can change upstream/proxy endpoints.
For a root-only identity instead of your SSH key, set the string option
`services.cli-proxy-api.ageKeyFile = "/var/root/cli-proxy-api-age.txt";` (use a
root-owned mode-600 file), add its public recipient, re-encrypt, and remove login-user
recipients if they must not decrypt. Rotate the secrets too: old ciphertext/history
may remain decryptable with the old key. Stronger isolation also requires moving the
mutable settings out of your login user's control. Never use a Nix path literal or
`readFile` for the identity. RAM-backed storage can still reach swap/hibernation; configure those
separately for a strict no-physical-storage guarantee. Core dumps are disabled.

For example, keep the OpenAI URL and model list in `config.yaml`:

Use `api-keys.codex` for the official OpenAI Responses API with ordinary API keys;
this keeps reasoning and tool calls on upstream `/v1/responses`. The generic
`openai-compatibility` route instead uses upstream Chat Completions, even when
clients call the proxy's Responses endpoint.

```yaml
api-keys:
  codex:
    - name: openai
      base-url: https://api.openai.com/v1
      models:
        - name: gpt-6-astra
          alias: gpt-6-astra
```

Supply only the matching group's credentials in the SOPS-encrypted file:

```yaml
api-keys:
  codex:
    - name: openai
      keys:
        - api-key: sk-YOUR_OPENAI_KEY
```

Groups are matched within each provider type, never by list position. Unmatched
groups are retained, including groups added only in the secrets file. A secrets
entry can override ordinary group fields too; nested lists such as `keys` and
`models` still replace their tracked counterparts when explicitly supplied.

Authenticate a provider, then point clients at `http://llmproxy.tristanmayo.com:8317/v1` with your
client key:

```bash
sudo cli-proxy-api --codex-login
# Or: sudo cli-proxy-api --claude-login
# Headless: sudo cli-proxy-api --codex-device-login --no-browser
curl -H "Authorization: Bearer YOUR_CLIENT_KEY" http://llmproxy.tristanmayo.com:8317/v1/models
```

OAuth logins survive service stops, restarts and reboots. They are stored as ordinary
credential files on persistent disk, protected by the dedicated service account's
permissions; unlike API keys, they are not managed by SOPS or placed in the RAM disk.
Services and login commands create private files using `umask 077`. Browser login
may need `--no-browser` and manually opening the URL because the service account
does not have a desktop session.

### Executor MCP across machines

Claude Code, Codex, pi and OpenCode use the fixed local URL
`http://127.0.0.1:28760/executor`, without authentication headers. These client settings
remain ordinary Stow-managed files (Claude's user entry lives in `~/.claude.json`).
The Caddy-based `executor-router` service selects the `executor` entry in the shared
service map and forwards to its configured target through
Agent Vault, which injects the SOPS bearer token. Set the upstream URL per machine in
`nixos/hosts/<host>/default.nix`:

```nix
mcp-gateway.address = "http://executor.localhost:4788/mcp"; # Default: local Executor.
# mcp-gateway.address = "https://executor.example.com/mcp"; # Remote Executor; disables the local service.
```

Nix passes `EXECUTOR_MCP_URL` to the router and credential helper, never to client
MCP settings. Rebuild to switch the destination; client configs stay unchanged.
Existing MCP connections may need reconnecting when switching servers. Agent Vault
requires service hostnames, so use `executor.localhost` for the local service.
NixOS adds that name to the hosts file; macOS resolves `.localhost` names itself.
The default network allowlist permits loopback. For a remote Executor on a private
network, add its IP/CIDR to
`home-manager.users.tmx.services.agent-vault.environment.AGENT_VAULT_NETWORK_ALLOWLIST`
alongside `127.0.0.1/32,::1/128`. For remote clients, set
`home-manager.users.tmx.services.executor.host` to a trusted private interface
on the server and allow TCP port `4788`, or use a secure tunnel. Do not expose
plain HTTP and its bearer token to an untrusted network.

The bearer token is stored with sops in `nixos/secrets/home.yaml` (`executor/token`)
and decrypted by Home Manager to `~/.config/sops-nix/secrets/executor/token` using
`~/.ssh/id_ed25519`. The Executor service writes it into `auth.json` before
starting. Agent Vault reads it on first use and caches it for up to one hour.
Every machine shares one token and no process environment holds it. To add a machine,
put its `ssh-to-age` public key in `nixos/.sops.yaml` and run
`sops updatekeys secrets/home.yaml` from `nixos/` on a machine that can already
decrypt it. To rotate, run `sops secrets/home.yaml`, rebuild, and restart
`agent-vault-credentials` to invalidate the cached credential immediately. Claude Code's
global entry lives outside this repository in `~/.claude.json`. To configure a
new machine:

```sh
claude mcp add-json --scope user executor '{"type":"http","url":"http://127.0.0.1:28760/executor"}'
```

### Shared address across machines

All coding-agent clients use `llmproxy.tristanmayo.com` on port `8317`. Set one
Nix option in the machine's `nixos/hosts/<host>/default.nix`:

```nix
llmProxy.address = "127.0.0.1"; # Default: map the hostname locally and run CLIProxyAPI.
```

On a remote client, set that option to the proxy server's stable IP instead. Nix
updates the hosts-file mapping and disables the local proxy service; no agent
settings need changing. IPv6 loopback (`::1`) also selects the local service, but
requires a matching server listener in the YAML settings.

NixOS uses `networking.hosts`. On macOS, activation maintains a marked block in
`/etc/hosts`, preserves all unrelated entries, and saves the original file as
`/etc/hosts.before-llmproxy` before its first change. Rebuild Nix to apply the mapping
before starting clients with the new hostname. New Nix files must be staged first,
or use `--flake path:./nixos#macos` / `--flake path:./nixos#nixos` while testing.

This does not change `server.host: 127.0.0.1`, open firewall ports, or configure TLS.
Before using a remote client, make the proxy reachable on a trusted private
interface or through a secure tunnel/reverse proxy. A hosts-file entry alone does
not expose or encrypt the service; do not publish the unauthenticated API online.

### Restarting the service

```bash
# macOS
sudo launchctl kickstart -k system/org.nixos.cli-proxy-api
# Linux
sudo systemctl restart cli-proxy-api
systemctl status cli-proxy-api
```

Application logs are in `/var/lib/cli-proxy-api/logs/main.log` (use sudo). Startup
errors are in `/var/log/cli-proxy-api.error.log` on macOS or
`sudo journalctl -u cli-proxy-api` on NixOS. The system service starts at boot and
does not require a login session or lingering. On macOS the RAM disk is reused
across restarts and disappears on reboot.

### Configuration notes and recommendations

- Use the [v8 options](https://help.router-for.me/configuration/options.html) and
  the [release's example](https://github.com/router-for-me/CLIProxyAPI/blob/v8.0.20/config.example.yaml).
  The basic configuration page still shows the older layout. Client keys belong
  under `access.api-keys`; upstream keys belong under `api-keys.<provider>`.
- Keep `server.host: 127.0.0.1` for local use. Don't expose this port publicly
  without authentication and TLS (or a trusted private-network/reverse-proxy setup).
- Session affinity improves prompt-cache reuse across multiple credentials.
  Streaming keep-alives and bootstrap retries help with idle timeouts and failures
  before streaming starts. Both are included in the tracked config.
- Management is disabled by default. To use the web panel, set a **different**
  random `management.secret-key` in SOPS and set
  `management.disable-control-panel: false` in `config.yaml`;
  visit `http://127.0.0.1:8317/management.html`. The application downloads the panel
  at runtime, separately from the Nix-built server. Plaintext management keys are
  hashed and written back to the private RAM-backed config on startup.
  Web panel settings changes also affect only the runtime file and are lost at the
  next launch; make persistent settings changes in the tracked `config.yaml` instead.
- Optional: `observability.usage.usage-statistics-enabled: true` enables in-memory
  usage totals for management. Leave request/debug logging off unless troubleshooting;
  request logs can contain prompts and responses. Application logs are capped at 100 MB.
- Rebuild after editing the SOPS file, then restart the service to use its new
  encrypted store copy. Restart after editing `config.yaml` to regenerate
  the merged runtime config. OAuth credential files still support hot reload.
- Check provider subscription terms before using subscription OAuth credentials
  with third-party clients; API-key upstreams are also supported.

Build just the package with `nix build ./nixos#cli-proxy-api`.
The standalone package has upstream defaults and does not merge/decrypt secrets.
Use the system-installed launcher with sudo for the isolated, RAM-backed setup.

## Agent Vault (macOS and Linux)

Nix installs the pinned standalone [Agent Vault](https://github.com/Infisical/agent-vault)
release and runs three user services using launchd on macOS and systemd on Linux:

- `agent-vault`: management UI/API on `127.0.0.1:14321` and credential-injecting
  forward proxy on `127.0.0.1:14322`.
- `agent-vault-credentials`: an authenticated credential-refresh endpoint on
  `127.0.0.1:14323` and unattended provisioning of the vault and client environment.
  It does not forward MCP traffic.
- `executor-router`: Caddy serving named MCP routes on `127.0.0.1:28760`, forwarding
  each to its configured target through Agent Vault. It streams requests/responses, including
  SSE, and preserves MCP session headers. It has no credential-generation logic,
  stdio bridge or automatic retries. Browser-origin requests are rejected. Caddy's
  admin API and configuration persistence are disabled; its runtime configuration
  is supplied on stdin so the proxy token is never written into the Nix store.

Settings live in `tmx/.config/agent-vault/config.json`, symlinked by Stow to
`~/.config/agent-vault/config.json`. Its `services` map is the source for both Caddy
routing and Agent Vault's credential rules:

| Client URL | Configured upstream | Injected credential |
| --- | --- | --- |
| `http://127.0.0.1:28760/executor` | `${EXECUTOR_MCP_URL}` from Nix | SOPS bearer token |
| `http://127.0.0.1:28760/payload-staging` | `https://payload.eleven2.dev/api/mcp` | Staging IAP token |
| `http://127.0.0.1:28760/payload-production` | `https://payload.elevenlabs.io/api/mcp` | Production IAP token |

Add a service to this map to expose `/<service-name>` through Caddy. Each entry
has a `target` URL and optional credential `headers`; omit headers for a public
service. Environment placeholders use `${VARIABLE}` and are resolved by each
service at startup. Restart the credential helper and Caddy after editing the map.
Unknown names and arbitrary subpaths return 404; the request cannot choose a URL
outside the configured map.

API keys can be added in either of two ways, and both can be used at once:

- **SOPS (tracked, shared by all machines):** add the key to `nixos/secrets/home.yaml`
  with `sops`, declare it in `nixos/home/common/sops/default.nix`
  (`secrets."openai/api_key" = { };`), then reference the decrypted file from
  `credentials` and use it in a service's headers:

  ```json
  "credentials": { "OPENAI_API_KEY": { "file": "~/.config/sops-nix/secrets/openai/api_key" } },
  "services": {
    "openai": {
      "target": "https://api.openai.com/v1",
      "headers": { "Authorization": "Bearer {{ OPENAI_API_KEY }}" }
    }
  }
  ```

- **Agent Vault UI (local to one machine):** open `http://127.0.0.1:14321`, sign in
  as `tmx@agent-vault.local` with the password in `~/.agent-vault/owner-password`,
  and add the credential and a service to the `dotfiles` vault.

The helper upserts config services by name and deletes only services that it
previously created from config and that have since been removed
(tracked in `~/.agent-vault/managed-services.json`). Services added through the
UI survive restarts, unless they share a name with a config service.
UI services are applied by the forward proxy only; they get no
`/<service-name>` route. Don't reuse a `credentials` key name in the UI;
the helper rewrites those keys on every start.

Nix installs launchers for `codex`, `claude`, `pi` and `opencode`, ahead of the
manually updated executables in `~/.npm/bin`. Each launcher reads the private
`~/.agent-vault/proxy.env` and configures its process and children to use Agent
Vault's authenticated forward proxy and trust its CA. The launchers do not set or
override MCP URLs. Executor's fixed loopback URL bypasses that network proxy;
the router itself sends the upstream request through Agent Vault. No system certificate
installation or global network-proxy setting is needed. Restart existing agent
sessions and applications that launch them after changing the launchers.

Agent Vault injects credentials only for the configured service hosts and paths;
other destinations pass through without injected credentials. Loopback IPs and
the model endpoint `llmproxy.tristanmayo.com` bypass the proxy. Keep `localhost`
out of `noProxy`: suffix matching would also bypass `executor.localhost`.

The credential endpoint adapts the configured fixed `gcloud` commands and SOPS
file to Agent Vault's OAuth refresh protocol. Credentials are generated lazily,
and Agent Vault refreshes them within five minutes of expiry. Each Payload command
uses its own audience, service-account impersonation and `--include-email`; the
one-time gcloud setup from the marketing-website README is still required.
The Payload application API key remains a separate client header:

```json
{
  "type": "http",
  "url": "http://127.0.0.1:28760/payload-production",
  "headers": {
    "Authorization": "Bearer <payload mcp api key>"
  }
}
```

On first start the services create an encrypted local database, a dedicated
`dotfiles` vault, a proxy-only `coding-agents` agent and an invite-only owner account
(`tmx@agent-vault.local`). Random master/owner passwords and the credential-endpoint
capability, client proxy token and environment are kept as private files under
`~/.agent-vault/`, outside Stow and Git. The client token survives helper restarts.
The owner's password is in `~/.agent-vault/owner-password`; keep this directory
when restarting or rebuilding. The service reconciles only the `dotfiles` vault.

Check readiness with `curl http://127.0.0.1:14323/health`. On macOS, logs are in
`~/Library/Logs/agent-vault*.log` and `~/Library/Logs/executor-router*.log`; on Linux use
`journalctl --user -u agent-vault -u agent-vault-credentials -u executor-router`. Restart both Agent Vault services
after editing ports, or just the helper after editing services/credential sources.
Restart the router after changing its upstream URL, client proxy token or CA.
Restart agent processes if their network-proxy address, client token or CA changes.
For example, on macOS:

```sh
launchctl kickstart -k gui/$(id -u)/org.nix-community.home.agent-vault-credentials
```

On Linux use `systemctl --user restart agent-vault-credentials`. Authentication
rejections are returned to clients; MCP POST requests are not replayed. No stdio
bridge is provided. The package version and platform checksums live in
`nixos/pkgs/agent-vault/package.nix`.
