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

```yaml
api-keys:
  openai-compatibility:
    - name: openai
      base-url: https://api.openai.com/v1
      models:
        - name: gpt-4.1
          alias: gpt-4.1
```

Supply only the matching group's credentials in `secrets.yaml`:

```yaml
api-keys:
  openai-compatibility:
    - name: openai
      keys:
        - api-key: sk-YOUR_OPENAI_KEY
```

Groups are matched within each provider type, never by list position. Unmatched
groups are retained, including groups added only in the secrets file. A secrets
entry can override ordinary group fields too; nested lists such as `keys` and
`models` still replace their tracked counterparts when explicitly supplied.

Authenticate a provider, then point clients at `http://127.0.0.1:8317/v1` with your
client key:

```bash
cli-proxy-api --codex-login
# Or: cli-proxy-api --claude-login
# Headless: cli-proxy-api --codex-device-login --no-browser
curl -H "Authorization: Bearer YOUR_CLIENT_KEY" http://127.0.0.1:8317/v1/models
```

OAuth credentials live in `~/.local/share/cli-proxy-api/auth`, outside the dotfiles
tree. Runtime logs and panel assets use `~/.local/state/cli-proxy-api` by default.
Services and login commands create private files using `umask 077`.

### Service control

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
