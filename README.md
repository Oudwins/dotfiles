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

Nix builds CLIProxyAPI from source and runs it as a user service: launchd on macOS,
systemd on Linux. The settings in `tmx/.cli-proxy-api/config.yaml` are tracked in Git
and symlinked to `~/.cli-proxy-api/config.yaml` by Stow, not managed by Nix.
The installed `cli-proxy-api` launcher merges those settings with an optional
`~/.cli-proxy-api/secrets.yaml` at launch (including login commands). Secrets override
settings: nested mappings merge, while lists are replaced, except that upstream
`api-keys.<provider>` groups merge by `name` (unique and nonempty within each file).
The merged file lives at
`~/.local/state/cli-proxy-api/config.yaml`, has mode 600, and never enters the Nix store.
`--config /another/file.yaml` bypasses this merge and uses that file directly.

### Initial setup

Before rebuilding, create your local secrets file (do not overwrite an existing one):

```bash
cd ~/dotfiles
cp -n tmx/.cli-proxy-api/secrets.example.yaml tmx/.cli-proxy-api/secrets.yaml
openssl rand -hex 32
# Edit secrets.yaml and replace access.api-keys[0] with the generated key.
chmod 600 tmx/.cli-proxy-api/secrets.yaml
stow --no-folding -d tmx -t ~ .

# Git-backed flakes only see tracked files; stage the new Nix modules first.
git add nixos/pkgs/cli-proxy-api/package.nix nixos/home/common/cli-proxy-api/default.nix

# macOS
sudo darwin-rebuild switch --flake ./nixos#macos
# Linux / NixOS
sudo nixos-rebuild switch --flake ./nixos#nixos
```

Commit ordinary settings in `config.yaml`. Keep client keys, upstream API keys
and management secrets in `secrets.yaml`, which is Git-ignored but still linked by
Stow. `secrets.example.yaml` is only a starter template. Never put real secrets in
the tracked settings, the template, or Nix expressions. Without a real client key,
the placeholder in the tracked settings keeps proxy endpoints disabled.

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

Supply only the matching group's credentials in `secrets.yaml`:

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
cli-proxy-api --codex-login
# Or: cli-proxy-api --claude-login
# Headless: cli-proxy-api --codex-device-login --no-browser
curl -H "Authorization: Bearer YOUR_CLIENT_KEY" http://llmproxy.tristanmayo.com:8317/v1/models
```

OAuth credentials live in `~/.local/share/cli-proxy-api/auth`, outside the dotfiles
tree. Runtime logs and panel assets use `~/.local/state/cli-proxy-api` by default.
Services and login commands create private files using `umask 077`.

### Executor MCP across machines

All four coding agents use streamable HTTP at
`http://mcp.tristanmayo.com:4788/mcp`. Set the Executor machine's IP in
`nixos/hosts/<host>/default.nix`:

```nix
mcpProxy.address = "127.0.0.1"; # Default: local Executor.
# mcpProxy.address = "192.168.1.50"; # Remote Executor; disables the local service.
```

Rebuild Nix to apply the hosts-file mapping. On macOS, activation preserves
unrelated entries and creates `/etc/hosts.before-mcp` before the first change.
The server still listens on loopback by default. For remote clients, set
`home-manager.users.tmx.services.executor.host` to a trusted private interface
on the server and allow TCP port `4788`, or use a secure tunnel. Do not expose
plain HTTP and its bearer token to an untrusted network.

The bearer token is stored with sops in `nixos/secrets/home.yaml` (`executor/token`)
and decrypted by Home Manager to `~/.config/sops-nix/secrets/executor/token` using
`~/.ssh/id_ed25519`. The Executor service writes it into `auth.json` before
starting, and login shells export it as `EXECUTOR_MCP_TOKEN`, so every machine
shares one token. To add a machine, put its `ssh-to-age` public key in
`nixos/.sops.yaml` and run `sops updatekeys secrets/home.yaml` from `nixos/` on a
machine that can already decrypt it. To rotate, run `sops secrets/home.yaml` and
rebuild. Claude Code's global entry lives outside
this repository in `~/.claude.json`. To configure a new machine:

```sh
claude mcp add-json --scope user executor '{"type":"http","url":"http://mcp.tristanmayo.com:4788/mcp","headers":{"Authorization":"Bearer ${EXECUTOR_MCP_TOKEN}"}}'
```

Restart agent sessions after setting the token. Hosts-file changes select the
server without changing agent configuration.

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
launchctl kickstart -k "gui/$(id -u)/org.nix-community.home.cli-proxy-api"
# Linux
systemctl --user restart cli-proxy-api
systemctl --user status cli-proxy-api
```

Application logs are in `~/.local/state/cli-proxy-api/logs/main.log`. Startup errors
are in `~/Library/Logs/cli-proxy-api.error.log` on macOS or
`journalctl --user -u cli-proxy-api` on Linux. The user service starts at login;
Linux needs user lingering if it should run without an active login.

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
  random `management.secret-key` in `secrets.yaml` and set
  `management.disable-control-panel: false` in `config.yaml`;
  visit `http://127.0.0.1:8317/management.html`. The application downloads the panel
  at runtime, separately from the Nix-built server. Plaintext management keys are
  hashed and written back to the private runtime config on startup, not the tracked settings.
  Web panel settings changes also affect only the runtime file and are lost at the
  next launch; make persistent settings changes in the tracked `config.yaml` instead.
- Optional: `observability.usage.usage-statistics-enabled: true` enables in-memory
  usage totals for management. Leave request/debug logging off unless troubleshooting;
  request logs can contain prompts and responses. Application logs are capped at 100 MB.
- Restart the service after editing `config.yaml` or `secrets.yaml` to regenerate
  the merged runtime config. OAuth credential files still support hot reload.
- Check provider subscription terms before using subscription OAuth credentials
  with third-party clients; API-key upstreams are also supported.

Build just the package with `nix build ./nixos#cli-proxy-api`.
The standalone package has upstream defaults and does not merge secrets. Use the
Home Manager-installed launcher, or pass `--config ~/.local/state/cli-proxy-api/config.yaml`
after the launcher has generated the merged file.

## mcp-auth-proxy (macOS and Linux)

Nix installs [mcp-auth-proxy](https://github.com/Oudwins/mcp-auth-proxy) and, as a
convenience, also runs `mcp-auth-proxy http` as a user service (launchd on macOS,
systemd on Linux) listening on `127.0.0.1:28760`. The port is below both the macOS and
Linux ephemeral ranges, so outbound connections cannot take it. Settings live in
`tmx/.mcp-auth-proxy/config.yaml`, tracked in Git and symlinked to
`~/.mcp-auth-proxy/config.yaml` by Stow (not managed by Nix); change the port there.
The HTTP server has no client auth, so keep it on loopback.

The default mode is stdio: the MCP client spawns the binary, no port or service is
needed. Strategies `eleven-payload-staging` and `eleven-payload-production` mint the
Payload IAP token with `gcloud` (needs the one-time gcloud setup from the marketing-website
README). Each strategy has its own IAP audience and both need `--include-email`; use the
strategy that matches the target host (`payload.eleven2.dev` or `payload.elevenlabs.io`):

```json
{
  "command": "mcp-auth-proxy",
  "args": [
    "-s", "eleven-payload-production",
    "-t", "https://payload.elevenlabs.io/api/mcp",
    "-H", "Proxy-Authorization: Bearer {{token}}",
    "-H", "Authorization: Bearer ${env:PAYLOAD_MCP_API_KEY}"
  ]
}
```

To use the always-on HTTP service instead, point an `http` MCP client at it with a
strategy and target header:

```json
{
  "type": "http",
  "url": "http://127.0.0.1:28760/",
  "headers": {
    "X-Proxy-Strategy": "eleven-payload-production",
    "X-Proxy-Target": "https://payload.elevenlabs.io/api/mcp",
    "Proxy-Authorization": "Bearer {{token}}",
    "Authorization": "Bearer <payload mcp api key>"
  }
}
```

Check a strategy with `mcp-auth-proxy check`; service logs are in `~/Library/Logs/mcp-auth-proxy*.log`.
Restart after editing the config. Pinned to a commit in `nixos/pkgs/mcp-auth-proxy/package.nix`:
bump `rev`, `hash` and `vendorHash` together.
