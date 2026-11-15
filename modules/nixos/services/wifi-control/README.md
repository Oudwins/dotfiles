# Wi-Fi control

A standard-library-only Go service with an embedded web page, a configurable set
of routers, and per-router schedule locks. Each router has a stable **ID**, display
name, **connection type**, URL, TLS settings, and **credential references**.

The page is configured at **https://wifi.t.tristanmayo.com** on Ethernet-connected
`tubby`, linked from Homepage. nginx allows the local LAN and Tailscale; the
backend listens on `127.0.0.1:8790`.

## Daily events and locks

Two independent systemd timers send explicit commands to **all unlocked routers**:

- **07:00 Europe/Madrid:** Wi-Fi on.
- **23:00 Europe/Madrid:** Wi-Fi off.

Each driver reads the actual radio state and skips redundant changes. Routers are
processed independently: one inaccessible router does not block the others.
Failures appear in the service logs and cause the scheduled CLI command to exit
unsuccessfully; the per-router results are still printed.

The page's **Pause / Resume** control changes only that router's schedule lock:

- Paused routers are skipped by both timers, even if the router is unreachable.
- Manual on/off controls still work while paused.
- Pausing and resuming never change Wi-Fi immediately or move a timer.
- Resuming permits the next scheduled event; no missed events are replayed.
- Locks survive service and host restarts.

For example: manual on at 22:00 → scheduled off at 23:00 → manual on at 23:30 →
scheduled on at 07:00 (no write needed) → scheduled off at 23:00.

The service manages one private JSON file, `/var/lib/wifi-control/locks.json`,
containing only paused router IDs. The UI updates it atomically. No database or
manual state-file editing is needed. Corrupt state causes startup to fail instead
of silently unlocking everything. Keep IDs stable when renaming a router.

Starting the service performs no Wi-Fi changes. Timers use `Persistent=false`, so
events missed while the host is off wait until the next daily occurrence. Spain's
summer/winter clock changes are handled by `Europe/Madrid`.

## Connection types

### `zte-http`

The tested DIGI ZTE H3600 V9 web API, with `username` and `password` credentials.
Uses the router's 2.4/5 GHz radio controls, challenge authentication, decoded session
tokens, and RSA request checks. It verifies settings after writing them. Radio
enablement may precede actual beacon visibility by around 30–40 seconds.

### `openwrt-ubus`

The standard HTTPS JSON-RPC API at `https://<router>/ubus`. Uses
`network.wireless.status`, `network.wireless.up`, and `network.wireless.down`.
No SSH client or SSH credential is needed by the service.

Authentication supports **one** of:

- `username` and `password`: create a session per operation and destroy it
  afterward. This is the configured mode for our OpenWrt router and supports
  unattended operation after router/rpcd restarts without renewing tokens manually.
- `token`: an existing `ubus_rpc_session`. The service never destroys a supplied
  token. It must allow `network.wireless` `status`, `up`, and `down`. Standard ubus
  tokens are sessions, not necessarily permanent API keys: they can expire or
  disappear when rpcd/router restarts. An unrelated API's bearer key is not an
  interchangeable credential.

The OpenWrt router has a dedicated RPC account, `wifi-control`, defined in the
`wifi_control` login section of `/etc/config/rpcd`. It uses a SHA-512 password hash
and the `wifi-control` read/write ACL group. Its permissions are limited to
wireless status/up/down and its API session access/cleanup. The ACL source is
[`openwrt-acl.json`](openwrt-acl.json), installed on the router at
`/usr/share/rpcd/acl.d/wifi-control.json`.

Both the login configuration and ACL persist across ordinary router reboots.
The service uses HTTPS for normal operation; SSH was only used to provision the
account. Re-provision these router-side files after a factory reset/replacement.

The backend controls runtime Wi-Fi state while preserving radios explicitly
disabled in OpenWrt's configuration. On this router, 2.4 GHz is configured enabled
and 5 GHz is configured disabled. Pending startup/DFS checks are displayed as
pending, rather than claiming the radios are already broadcasting. Runtime
up/down commands do not modify UCI; after a router reboot, its configured wireless
state can return until the next timer or manual command.

## Adding routers with Nix

Router definitions live in `hosts/tubby/default.nix` under
`my.wifiControl.routers`. The attribute name is the ID. Declare the router's
sops secrets in the host and pass their paths (`wifiControlSecret` sets
`sopsFile` and `restartUnits`; see `hosts/tubby/default.nix`):

```nix
sops.secrets."wifi-control/office/username" = wifiControlSecret;
sops.secrets."wifi-control/office/password" = wifiControlSecret;

my.wifiControl.routers.office = {
  name = "Office";
  connectionType = "openwrt-ubus";
  url = "https://192.168.1.12/ubus";
  certificateSHA256 = "<certificate SHA-256>";
  credentials = {
    username = config.sops.secrets."wifi-control/office/username".path;
    password = config.sops.secrets."wifi-control/office/password".path;
  };
};
```

`credentials` maps backend authentication fields to files holding them, never
plaintext values. The module supplies each file through systemd `LoadCredential`
and generates the non-secret router configuration. Multiple routers can use the
same connection type. Add another backend implementation to support a different
router API.

`enable = false` omits a router and its scheduled commands. Both DIGI and OpenWrt are configured for tubby. An empty credential makes
only that router unavailable until it is filled; other routers remain usable.

### Edit Wi-Fi credentials with SOPS

```sh
just secrets wifi-control
```

The secret layout follows the router IDs. DIGI's existing values are preserved;
OpenWrt's dedicated account credentials have already been generated and stored:

```yaml
wifi-control:
  digi:
    username: <existing value>
    password: <existing value>
  openwrt:
    username: <provisioned API account>
    password: <generated password>
```

The secret names are `wifi-control/digi/username`, `wifi-control/digi/password`,
`wifi-control/openwrt/username`, and `wifi-control/openwrt/password`. No token needs
to be generated or saved. When rotating the OpenWrt password, also update the
matching password hash in its `/etc/config/rpcd` account. Save and close the SOPS
editor to encrypt changes, then deploy on tubby. The service receives credentials
through systemd `LoadCredential` and restarts when its deployed secrets change.

HTTPS certificates are validated against system CAs or an exact SHA-256 pin for
self-signed router certificates. Update a pin if a verified router replacement or
firmware change replaces its certificate.

## CLI and API

```sh
wifi-control status --router digi
wifi-control set --router openwrt on
wifi-control set --router digi off
wifi-control lock --router openwrt on   # pause scheduled changes
wifi-control lock --router openwrt off  # resume future scheduled changes
wifi-control scheduled-set on          # same operation as the morning timer
wifi-control scheduled-set off         # same operation as the evening timer
```

All commands accept `--server http://127.0.0.1:8790` before positional arguments.
Manual commands target one ID; `scheduled-set` applies to all unlocked routers.

- `GET /api/config`: router metadata/locks, shared schedule, and next event.
- `GET /api/routers/{id}/status`: live radios and that router's lock state.
- `POST /api/routers/{id}/wifi`, JSON `{"enabled":true|false}`: manual change.
- `POST /api/routers/{id}/lock`, JSON `{"locked":true|false}`: pause/resume.
- `POST /api/schedule`, JSON `{"enabled":true|false}`: all unlocked routers.

Credentials and upstream response bodies are never returned to the browser.
Writes require JSON and reject cross-origin browser requests. A failed read is an
unknown/error state, not a false “Wi-Fi off” state. Per-router serialization makes
schedule lock changes and scheduled commands consistent.

## Build, test, and deploy

```sh
cd pkgs/wifi-control
go test -race ./...
go vet ./...
```

Once new files are tracked by Git, from the repository root:

```sh
nix build .#wifi-control
sudo nixos-rebuild switch --target-host root@tubby --flake .#tubby
```

On tubby:

```sh
systemctl status wifi-control.service
systemctl list-timers 'wifi-control-*'
journalctl -u wifi-control -u wifi-control-on -u wifi-control-off
```

The test suite uses HTTPS router simulators for both protocols, and covers
idempotency, disabled OpenWrt radios, pending startup, token errors, password
sessions, secret redaction, multiple routers, persistent locks, lock/command
races, partial failures, HTTP input validation, and daylight-saving dates.
