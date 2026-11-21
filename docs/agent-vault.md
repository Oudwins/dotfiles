# Agent Vault (macOS and Linux)

Nix installs the pinned standalone [Agent Vault](https://github.com/Infisical/agent-vault)
release and runs three user services using launchd on macOS and systemd on Linux:

- `agent-vault`: management UI/API on `127.0.0.1:14321` and credential-injecting
  forward proxy on `127.0.0.1:14322`.
- `agent-vault-credentials`: an authenticated credential-refresh endpoint on
  `127.0.0.1:14323` and unattended provisioning of the vault and client environment.
  It does not forward MCP traffic.
- `agent-vault-router`: Caddy serving named routes on `127.0.0.1:28760`, forwarding
  each to its configured target through Agent Vault. It streams requests/responses, including
  SSE, and preserves MCP session headers. It has no credential-generation logic,
  stdio bridge or automatic retries. Browser-origin requests are rejected. Caddy's
  admin API and configuration persistence are disabled; its runtime configuration
  is supplied on stdin so the proxy token is never written into the Nix store.

Settings live in `home-files/tmx/.config/agent-vault/config.json`, symlinked by Stow to
`~/.config/agent-vault/config.json`. Its `services` map is the source for both Caddy
routing and Agent Vault's credential rules:

| Client URL | Configured upstream | Injected credential |
| --- | --- | --- |
| `http://127.0.0.1:28760/executor` | `${EXECUTOR_MCP_URL}` from Nix | SOPS bearer token |
| `http://127.0.0.1:28760/llmproxy/…` | `${LLM_PROXY_URL}` from Nix | CLIProxyAPI client key |
| `http://127.0.0.1:28760/payload-staging` | `https://payload.eleven2.dev/api/mcp` | Staging IAP token |
| `http://127.0.0.1:28760/payload-production` | `https://payload.elevenlabs.io/api/mcp` | Production IAP token |

Add a service to this map to expose `/<service-name>` through Caddy. Each entry
has a `target` URL and optional credential `headers`; omit headers for a public
service. Environment placeholders use `${VARIABLE}` and are resolved by each
service at startup. Restart the credential helper and Caddy after editing the map.
A target without a path exposes its whole host: `/<name>/<subpath>` is forwarded
to `<target>/<subpath>`. A target with a path is served only at `/<name>`. Otherwise
unknown names and subpaths return 404; the request cannot choose a URL
outside the configured map.

API keys can be added in either of two ways, and both can be used at once:

- **SOPS (tracked, shared by all machines):** add the key to nix-secrets
  `sops/users/tmx.yaml` with `just secrets tmx`, declare it in `modules/home/common/sops/default.nix`
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
  as `tmx@<my.domain>` with the password from `sops decrypt --extract '["agent-vault"]["owner-password"]' sops/users/tmx.yaml` (in `~/nix-secrets`),
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
Vault's authenticated forward proxy and trust its CA. They check the credential
helper's health before launching and fail with an actionable error if it is unavailable.
For debugging, `codex-unwrapped`, `claude-unwrapped`, `pi-unwrapped` and
`opencode-unwrapped` run the npm executables without loading the vault environment.
They also remove inherited proxy and CA variables, so they work from inside a
wrapped agent session. These commands bypass credential injection; vault-backed
routes still require the services to be healthy. The launchers do not set or
override MCP URLs. Executor's fixed loopback URL bypasses that network proxy;
the router itself sends the upstream request through Agent Vault. No system certificate
installation or global network-proxy setting is needed. Restart existing agent
sessions and applications that launch them after changing the launchers.

Agent Vault injects credentials only for the configured service hosts and paths;
other destinations pass through without injected credentials. Loopback IPs
and `localhost`, including the router on `127.0.0.1:28760`, bypass the proxy, so
local dev servers on `http://localhost:<port>` work in agent sessions. Suffix
matching also bypasses `*.localhost` service hosts; only the router calls those,
and it sets its proxy explicitly, ignoring `NO_PROXY`.

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
(`<my.username>@<my.domain>`, set in `roles/agents.nix`). The owner password is shared
by every machine and lives in nix-secrets `sops/users/tmx.yaml` (`agent-vault/owner-password`).
A random master password and the credential-endpoint capability, client proxy token
and environment are kept as private files under `~/.agent-vault/`, outside Stow and
Git. The client token survives helper restarts; keep this directory when restarting
or rebuilding.

Agent Vault cannot change an account's email, so the server launcher records a hash of
the configured owner email and password in `~/.agent-vault/owner`. When they change
(or when the record is missing), it deletes the database, CA and published proxy
configuration before starting, and the helper registers the owner again using the
configured email and SOPS password. This cleanup also runs if the database was
already removed, so an interrupted reset cannot leave its old CA behind. A new
database generates a new encryption key even with the same master password; reusing
the old CA would leave the forward proxy unable to start. The master password and
credential-endpoint capability are kept. Config-managed credentials and services
are recreated; ones added through the UI are lost. A missing or empty password file
fails without deleting state. Unchanged owner credentials preserve the vault.
The service reconciles only the `dotfiles` vault.

After rotating the SOPS owner password, apply the configuration and restart the
vault stack so the server compares the new credentials. On Linux,
`systemctl --user restart agent-vault` also restarts the helper and router. On
macOS, restart all three launchd agents. Reconnect existing agent sessions after
a reset: their inherited proxy token and CA have changed.

Check readiness with `curl http://127.0.0.1:14323/health`. A running management API
on port 14321 does not imply the forward proxy is working: if the logs report
`CA init failed`, port 14322 may not be listening. Keep the database, `ca/` and
master password together when backing up or restoring `~/.agent-vault/`.

On macOS, logs are in
`~/Library/Logs/agent-vault*.log` and `~/Library/Logs/agent-vault-router*.log`; on Linux use
`journalctl --user -u agent-vault -u agent-vault-credentials -u agent-vault-router`. Restart both Agent Vault services
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
`pkgs/agent-vault/package.nix`.

## Shared address across machines

Agents reach shared services through `agent-vault-router` on
`http://127.0.0.1:28760/<name>`, which forwards through Agent Vault so it can inject
each service's credential. Clients hold no keys and their settings never change per
machine. Each service is wired in `roles/agents.nix`:

| Service | Client URL | Local endpoint | Injected credential |
| --- | --- | --- | --- |
| `llmproxy` | `http://127.0.0.1:28760/llmproxy` (`/v1` for OpenAI clients) | `http://llmproxy.localhost:8317` | CLIProxyAPI `client-key` |
| `executor` | `http://127.0.0.1:28760/executor` | `http://executor.localhost:4788/mcp` | Executor bearer token |

To use another machine's service, set its address in `hosts/<host>/default.nix`.
This disables the local service:

```nix
agents.llmproxy.address = "https://tubby.<tailnet>.ts.net:8317";
```

Addresses must use hostnames, such as Tailscale MagicDNS names, because Agent Vault
rejects IP-based service hosts. Agent Vault's network guard always allows Tailscale's
ranges (`100.64.0.0/10`, `fd7a:115c:a1e0::/48`), so remote services and other tailnet
hosts, such as the package registry, are reachable through the proxy; add other
private networks with `home-manager.users.tmx.services.agent-vault.networkAllowlist`.
Local endpoints use `.localhost` names: NixOS adds them to the hosts file, and macOS
resolves `.localhost` itself. The `llmproxy` address takes no path; the router passes
every subpath through to it. Rebuild, then restart the router, to switch.
New Nix files must be tracked first (`git add -N <file>`); never use a `path:`
flake ref, which would copy gitignored credentials under `home-files/` into the
Nix store.

This does not change `server.host: 127.0.0.1` on the serving machine, open firewall
ports, or configure TLS there. Before using a remote client, make the proxy reachable
on a trusted private interface or through a secure tunnel/reverse proxy; do not
publish the API online.

## Executor MCP across machines

Claude Code, Codex, pi and OpenCode use the fixed local URL
`http://127.0.0.1:28760/executor`, without authentication headers. These client settings
remain ordinary Stow-managed files (Claude's user entry lives in `~/.claude.json`).
The `agent-vault-router` service selects the `executor` entry in the shared
service map and forwards to its configured target through
Agent Vault, which injects the SOPS bearer token. To use another machine's
Executor, set its URL in `hosts/<host>/default.nix`; this disables the local service:

```nix
agents.executor.address = "https://executor.<tailnet>.ts.net/mcp";
```

Without an address, the router uses the local `http://executor.localhost:4788/mcp`.
Existing MCP connections may need reconnecting when switching servers. Addresses
follow the shared rules in [Shared address across machines](#shared-address-across-machines).
For remote clients, set `home-manager.users.tmx.services.executor.host` to a trusted
private interface on the server and allow TCP port `4788`, or use a secure tunnel.
Do not expose plain HTTP and its bearer token to an untrusted network.

The bearer token is stored with sops in nix-secrets `sops/users/tmx.yaml` (`executor/token`)
and decrypted by Home Manager to `~/.config/sops-nix/secrets/executor/token` using
`~/.ssh/id_ed25519`. The Executor service writes it into `auth.json` before
starting. Agent Vault reads it on first use and caches it for up to one hour.
Every machine shares one token and no process environment holds it. To add a machine,
put its `ssh-to-age` public key in nix-secrets' `.sops.yaml` and run
`sops updatekeys sops/users/tmx.yaml` in `~/nix-secrets` on a machine that can already
decrypt it. To rotate, run `just secrets tmx`, rebuild, and restart
`agent-vault-credentials` to invalidate the cached credential immediately. Claude Code's
global entry lives outside this repository in `~/.claude.json`. To configure a
new machine:

```sh
claude mcp add-json --scope user executor '{"type":"http","url":"http://127.0.0.1:28760/executor"}'
```
