# Matrix and WhatsApp on vela

Tuwunel 1.9.3 runs as `tuwunel.service`, using the official release flake pinned
in `flake.lock`. The homeserver is `matrix.tristanmayo.com`, with nginx forwarding
to `127.0.0.1:6167`. Its data is at `/var/lib/tuwunel/` (backed by systemd's
private state directory).

The personal WhatsApp bridge runs as `mautrix-whatsapp.service`, listening only
on `127.0.0.1:29318`. Only `@tmx:matrix.tristanmayo.com` can use it. Both services
are configured through the native NixOS modules.

## Declarative registrations and secrets

`whatsapp.nix` defines both appservice registrations. SOPS renders them at
activation, and tmpfiles links them into `/run/matrix-appservices/`, which
Tuwunel loads on startup. The bridge installs the same main registration into
its state directory before the native module's startup script runs. This avoids
random token generation and keeps both services in sync.

The YAML/JSON registration flag for MSC4190 is **`io.element.msc4190: true`**.
Tuwunel's TOML configuration calls it `device_management`, but that is not the
field name accepted by its YAML registration reader in this release.

Credentials live under `matrix.whatsapp` in `secrets/vela.yaml`:

- `as_token` and `hs_token`: main bridge registration.
- `double_puppet_as_token` and `double_puppet_hs_token`: double-puppeting registration.
- `pickle_key`: encryption key for the bridge's crypto database.

The registration files are readable only by root and the `matrix-appservices`
service group. SOPS changes restart the relevant services. Ordinary rebuilds
do not require sending registration messages in the admin room.

Do not also register these IDs in the homeserver database: Tuwunel rejects
duplicates between file-backed and database-backed registrations.

## Deploy

```sh
nixos-rebuild switch --flake .#vela --build-host root@vela --target-host root@vela --use-substitutes
```

The Tuwunel package and its dependencies use the upstream release's pins. The
module configures upstream's signed Nix cache. The bridge is pinned to 26.09
and uses the optional pure-Go crypto implementation (`goolm`).

`vela-dev` shares the homeserver module, but does not enable the WhatsApp bridge.
An existing Conduit database must be migrated before deploying the changed
homeserver module there; the one-time production migration does not run as an
activation script.

## Pair WhatsApp

1. Create an encrypted DM in Element with `@whatsappbot:matrix.tristanmayo.com`.
2. Send `login qr`.
3. On the phone, open WhatsApp → Linked devices → Link a device, and scan the QR.
4. Check a DM and a group in both directions, including an image, a voice
   message, and a message sent from the phone itself.

The first login creates up to five recent chat rooms and imports up to 50
messages per room. Other chats are created when messages arrive. Adjust
`network.history_sync` and `backfill` before pairing for different initial limits.
WhatsApp status broadcasts are disabled. Upload limits are 100 MiB.

Rooms are encrypted and non-federated. The bridge uses `self_sign = true` and
`msc4190 = true` with ordinary `/sync` encryption (`appservice = false`). Automatic
double puppeting sends phone-originated messages as the real Matrix user and
auto-accepts room invites; impersonation is restricted to that exact user ID.

## Operations

```sh
ssh root@vela 'systemctl status tuwunel mautrix-whatsapp'
ssh root@vela 'journalctl -u mautrix-whatsapp -n 100 --no-pager'
ssh root@vela 'systemctl restart tuwunel mautrix-whatsapp'
```

When restarting the homeserver, include the bridge: its `Requires` dependency
stops it when Tuwunel stops. The backup job also restarts both explicitly.

WhatsApp login and crypto state live in `/var/lib/mautrix-whatsapp/`. Preserve
the matching SOPS pickle key when restoring that database. Keep the phone online
periodically; WhatsApp disconnects linked devices after roughly two weeks
without the primary phone.

## Backups and migration

`restic-backups-matrix.timer` runs daily around 04:00. It briefly stops both
services, snapshots their state under `/var/lib/matrix-backup/`, then restarts
them before uploading to the `vela.matrix` repository. The snapshot includes
both databases, media, crypto configuration, and registration files.

```sh
ssh root@vela 'systemctl start restic-backups-matrix'
ssh root@vela 'restic-matrix snapshots'
ssh root@vela 'restic-matrix check'
```

The October 3, 2026 cutover used Conduit's supported admin commands to remove
the two old database-backed registrations after taking a checkpoint. Its state
was then copied into the new Tuwunel directory for upstream's automatic migration.
Accounts, room history, and nine media originals migrated successfully.

Pre-cutover recovery points:

- Local checkpoint: `/var/lib/matrix-before-tuwunel-20261003T154607Z`.
- Restic snapshot: `e3256b72`, tagged `pre-tuwunel`.
- The checkpoint's `previous-system` file records the previous NixOS closure.

A partial self-signing initialization inherited from the failed Conduit setup
was repaired once using Mautrix's documented `overwrite` recovery marker, after
backing up the bridge database. Normal starts preserve the resulting identity.

For recovery, restore a snapshot to a staging directory, stop both services,
and restore the matching homeserver and bridge state with correct ownership.
Rolling back to Conduit requires the **pre-migration** database and matching
bridge checkpoint; do not open Tuwunel's migrated database with Conduit. Activate
a saved system closure using `nixos-rebuild switch --no-reexec --store-path PATH`.

## Upstream documentation

- [Tuwunel NixOS setup](https://matrix-construct.github.io/tuwunel/deploying/nixos.html)
- [Tuwunel appservices](https://matrix-construct.github.io/tuwunel/appservices.html)
- [WhatsApp login](https://docs.mau.fi/bridges/go/whatsapp/authentication.html)
- [Double puppeting](https://docs.mau.fi/bridges/general/double-puppeting.html)
- [Encryption](https://docs.mau.fi/bridges/general/end-to-bridge-encryption.html)
