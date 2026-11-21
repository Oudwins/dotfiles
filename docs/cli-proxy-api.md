# CLIProxyAPI (macOS and Linux)

Nix builds CLIProxyAPI from source and runs it as a system daemon under a dedicated
account: `cli-proxy-api` on NixOS, `_cliproxyapi` on macOS. A root launcher decrypts
SOPS and prepares private runtime files, then permanently drops UID/GID before
executing the proxy. Your login user is not a member of the service group.

Ordinary settings in `home-files/tmx/.cli-proxy-api/config.yaml` are tracked and Stow-linked to
`~/.cli-proxy-api/config.yaml`. Secrets live in **SOPS-encrypted**
`sops/shared/cli-proxy-api.yaml` in nix-secrets. Only ciphertext and scripts enter the Nix store;
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

## Initial setup

The encrypted file is shared by both machines. To import an existing local secrets
file without making another plaintext copy (do not overwrite an existing SOPS file):

```bash
cd ~/nix-secrets
test ! -e sops/shared/cli-proxy-api.yaml &&
  sops --encrypt --filename-override sops/shared/cli-proxy-api.yaml \
    ~/dotfiles/home-files/tmx/.cli-proxy-api/secrets.yaml > sops/shared/cli-proxy-api.yaml
```

For a fresh setup, use `~/dotfiles/home-files/tmx/.cli-proxy-api/secrets.example.yaml` as the input instead,
then edit with SOPS. Put a real client key in the top-level `client-key`: the
launcher adds it to `access.api-keys`, and Home Manager decrypts the same value for
Agent Vault to inject into agent requests. Further `access.api-keys` entries are for
clients outside Agent Vault; an empty list with no `client-key` means no client
authentication. `sops`' interactive editor uses a temporary plaintext
file: on NixOS, set `TMPDIR="$XDG_RUNTIME_DIR"` when editing. On macOS, use a private
RAM disk as `TMPDIR`, or use `sops set --value-stdin` to avoid editor temporary files.
Do not pass secret values as command-line arguments or put them in shell history.

The daemon converts `~/.ssh/id_ed25519` to an age identity at runtime by default.
Both machines' SSH-derived recipients are in nix-secrets' `.sops.yaml`; add other machines'
recipients and run `sops updatekeys sops/shared/cli-proxy-api.yaml` there before rebuilding.
For manual SOPS commands, if you do not already have an age identity configured,
use `export SOPS_AGE_KEY="$(ssh-to-age -private-key -i ~/.ssh/id_ed25519)"` first.

On macOS the hidden account defaults to UID/GID 493. Verify these are unused, or set
`services.cli-proxy-api.darwinUid` to a free ID before the first rebuild.

```bash
cd ~/dotfiles
./updateSymlinks.sh
# Git-backed flakes only include tracked files. Stage the new module/helpers and
# encrypted file first (`git add -N`), or evaluate a clean source snapshot containing them.
just switch
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
`home-files/tmx/.cli-proxy-api/secrets.yaml`, its `~/.cli-proxy-api/secrets.yaml` link, and
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

Authenticate a provider. Agents reach the proxy through Agent Vault (see
[Shared address across machines](agent-vault.md#shared-address-across-machines)); to query it
directly, use the client key:

```bash
sudo cli-proxy-api --codex-login
# Or: sudo cli-proxy-api --claude-login
# Headless: sudo cli-proxy-api --codex-device-login --no-browser
curl -H "Authorization: Bearer YOUR_CLIENT_KEY" http://127.0.0.1:8317/v1/models
```

OAuth logins survive service stops, restarts and reboots. They are stored as ordinary
credential files on persistent disk, protected by the dedicated service account's
permissions; unlike API keys, they are not managed by SOPS or placed in the RAM disk.
Services and login commands create private files using `umask 077`. Browser login
may need `--no-browser` and manually opening the URL because the service account
does not have a desktop session.


## Restarting the service

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

## Serving it from a server and recording sessions

`modules/nixos/services/llmproxy` runs the proxy on a server (tubby imports it)
behind nginx at `https://llmproxy.<location>.<domain>`. The proxy stays on
loopback and reads the tracked `config.yaml` and the shared SOPS file with the
server's master key. nginx allows 256 MB request bodies, does not buffer
streams, and returns 403 for the management API and panel, so use those over SSH
(`ssh -L 8317:127.0.0.1:8317 tubby`). To use it, log in on the server
(`sudo cli-proxy-api --codex-device-login --no-browser`, …) and then point a
workstation at it:

```nix
agents.llmproxy.address = "https://llmproxy.<location>.<domain>";
```

`modules/nixos/services/llm-sessions` records everything that proxy serves into
a local ClickHouse (database `llm`), using the `session-recorder` plugin
(`pkgs/cpa-session-recorder`):

- `usage`: one row per usage record (tokens, latency, TTFT, credential, model,
  session ID).
- `exchanges`: one row per model execution, with the client's request body and
  the response as delivered to the client (`response_body`, or every stream
  chunk or WebSocket event in `response_chunks`). Stored exactly as sent and
  sorted by session. Executions over 64 MB are cut short and flagged `truncated`.

Session IDs come from CLIProxyAPI, e.g. `claude:<uuid>` (sub-agents
`claude:<uuid>:agent:<id>`, with `parent_session_id`), `codex:<id>` or
`header:<X-Session-ID>`. Rows are dropped, not retried, while ClickHouse is
down, and the data is not backed up. Grafana gets an "LLM sessions" data
source with read-only access. Query as admin on the server:

```bash
sudo sh -c 'CLICKHOUSE_PASSWORD="$(cat /var/lib/llm-sessions/default)" clickhouse client'
```

```sql
-- Tokens per model per day
SELECT toDate(ts) AS day, model, sum(input_tokens) AS input, sum(output_tokens) AS output
FROM llm.usage GROUP BY day, model ORDER BY day;
-- The full conversation of each Claude Code session is its latest request
SELECT session_id, argMax(request_body, ts) FROM llm.exchanges
WHERE session_id LIKE 'claude:%' GROUP BY session_id
INTO OUTFILE 'claude-sessions.parquet' FORMAT Parquet;
```

The ClickHouse passwords are generated on the server under `/var/lib/llm-sessions`
and never leave it. `llm-sessions-schema` creates missing tables on start; change
existing ones with `ALTER TABLE`. Other plugins can be loaded the same way with
`services.cli-proxy-api.plugins.<id> = { package; settings; }`.

## Configuration notes and recommendations

- Use the [v8 options](https://help.router-for.me/configuration/options.html) and
  the [release's example](https://github.com/router-for-me/CLIProxyAPI/blob/v8.0.69/config.example.yaml).
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
