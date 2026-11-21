# Rizos: encrypted physical server

- One NVMe disk: `/dev/nvme0n1` (approximately 1 TB).
- UEFI boot, 1 GiB unencrypted EFI partition, remaining space LUKS2 + ext4 root.
- No swap partition. All OS data, including `/nix`, lives inside LUKS.
- Wired IPv4 DHCP, with the same MAC-based client identity in both boot stages.
- Early-boot SSH on **2222**, normal SSH on **22**.
- Both use the shared root authorized-key list: `id_ed25519` and `id_master`.
- Root and tmx use SOPS-backed account passwords for physical-console login.
  Sudo requires the tmx password. Normal SSH remains key-only.

The server waits for a passphrase after every reboot, including a power outage.
SSH authentication alone does **not** unlock the disk.

The disk layout and SSH-unlock configuration are shared files, not Rizos-only
implementations. See [reusing this setup](../../docs/encrypted-servers.md).

User definitions come from the existing `hosts/common/users/tmx` and
`hosts/common/users/root` modules, with passwords in `secrets/rizos.yaml`.

## Before installation

**Installation erases all of `/dev/nvme0n1`. Back up anything on it first.**
Do not use the existing unencrypted bootstrap scripts for this host.

1. Boot a NixOS installer USB in **UEFI mode**, connect Ethernet, and run
   `sudo passwd` to set a temporary installer root password. Confirm the disk
   with `lsblk -o NAME,SIZE,MODEL,SERIAL` and get the LAN IP with `ip -4 addr`.
   Verify `/sys/firmware/efi` exists. This bootstrap assumes x86_64 hardware.
2. Identify the Ethernet driver on the installer:

   ```bash
   # Replace enp1s0 with the connected interface from `ip link`.
   basename "$(readlink -f /sys/class/net/enp1s0/device/driver/module)"
   ```

   If it is not one of `r8169`, `e1000e`, `igb`, or `igc`, add it to
   `boot.initrd.availableKernelModules` in `default.nix`. Out-of-tree NIC drivers
   may also need their kernel package configured. This is essential: normal
   networking working does not guarantee networking works before disk unlock.
3. Reserve an IPv4 address for the Ethernet MAC in your router. Use that IP for
   unlocking; hostname resolution might not work in early boot. Keep this
   service on a trusted LAN: do not port-forward 2222 from the internet.
4. Store a strong disk passphrase in your password manager. Keep a separate,
   offline copy: there is no automatic unlock or recovery without a valid key.

## Account passwords and SOPS

Before building or installing, create `secrets/rizos.yaml`. Generate password
hashes for root and tmx interactively (run once per account):

```bash
nix shell nixpkgs#whois -c mkpasswd -m yescrypt
nix develop -c sops secrets/rizos.yaml
```

In the SOPS editor, use this structure with the generated hashes:

```yaml
users:
  root:
    hashed_password: <root password hash>
  tmx:
    hashed_password: <tmx password hash>
```

Save the file encrypted; do not commit plaintext passwords or hashes. The SOPS
creation rule grants access to the existing users and main master key. The
installation script below copies that existing private master key to
`/etc/ssh/ssh_master_key`, matching the other servers' SOPS setup. It stays on the
encrypted root filesystem, not in the early-boot SSH environment. Make sure the
source key is readable by the account running the installation command.

The account passwords are separate from the LUKS disk passphrase. Test physical
login and password-protected sudo after installation.

## Install from this repository

Run the encrypted variant of the existing bootstrap script from the repo root,
replacing the example IP:

```bash
sudo ./scripts/bootstrap-encrypted.sh -n rizos -d root@192.168.1.50
```

It copies `bootstrap-vps.sh`'s host resolution, master-key provisioning, and
hardware generation flow, adding disk-erasure confirmation, a confirmed disk
passphrase, and a dedicated early-boot SSH key. It reads the disk, password-file
path, host-key path, and unlock port from the Nix configuration.

The script pins the early-boot host key in your SSH known-hosts file and prints
the unlock command. When run through sudo, it uses the invoking user's SSH key
and known-hosts file. Use `--help` for the existing bootstrap options, including
`-k`, `--source-master-key`, `--host-config-dir`, and `--port` (the installer SSH
port, not the unlock port).

Private keys and the disk passphrase are held in a private temporary directory
that is cleaned up on exit. Only the master key and early-boot host key are
copied into the installed OS; the disk passphrase goes only to the live
installer. Neither private key belongs in Git or a Nix expression.

`nixos-anywhere` generates `hosts/rizos/hardware-configuration.nix` before
building/installing the system. The host imports it once it exists; there is no
hand-written hardware placeholder. Review and commit the generated file
afterwards. The bootstrap script registers the file with `git add -N` so the
git-backed flake ref sees it; never use a `path:` ref, which would copy gitignored
credentials under `home-files/` into the Nix store.

The early-boot host private key is retained at
`/etc/secrets/initrd/ssh_host_ed25519_key` for future bootloader updates. Keep it
root-only and back it up securely. A remote rebuild does not need that key on
your workstation: it is appended to the initrd on the target during activation.

## Reboot and unlock

After installation, or after `ssh root@<LAN-IP> reboot`, wait for port 2222:

```bash
ssh -t -i ~/.ssh/id_ed25519 -o HostKeyAlias=rizos-initrd \
  -p 2222 root@<LAN-IP>
```

Enter the **disk passphrase** at the prompt. Boot resumes and the early-boot SSH
connection closes. Normal SSH is then available:

```bash
ssh -i ~/.ssh/id_ed25519 tmx@<LAN-IP>
```

The early-boot login only runs the password agent, not a general root shell.
If you connect before a password request exists, reconnect when the prompt is
ready. Normal SSH uses a separate host key; verify its fingerprint on first
connection. For later updates, run `just deploy rizos`; do **not** rerun the installation
command.

## Coding agents

Rizos runs `roles/agents.nix` (LLM proxy, Executor, Agent Vault, agent CLIs)
plus a T3 Code server. nginx serves the proxy, Executor and T3 Code at
`llmproxy.r.<domain>`, `executor.r.<domain>` and `t3.r.<domain>` on the tailnet
interface only. nixos uses the proxy and Executor from here.

tmx's home-manager secrets are decrypted with a dedicated age key,
`users/tmx/age_key` in `sops/hosts/rizos.yaml`, which is a recipient of
`sops/users/tmx.yaml` and `sops/shared/cli-proxy-api.yaml`.

After the first deploy (or a reinstall):

1. Point a Cloudflare DNS record for `*.r.<domain>` at rizos's tailnet IP.
2. Nothing to do for the Stow-managed files the proxy and Agent Vault read:
   the `dotfiles-bootstrap` user service clones this repo to `~/dotfiles` if
   missing and runs `./updateSymlinks.sh` at boot
   (`journalctl --user -u dotfiles-bootstrap` if they are missing).
3. Log the proxy's OAuth providers in again (`sudo cli-proxy-api -claude-login`
   and so on), or copy `/var/lib/cli-proxy-api/auth` from the old machine.
4. Pair T3 Code: `t3 auth pairing create --base-url https://t3.r.<domain>` and
   open the printed link, or add the URL and code in the desktop app.

## Recovery and security

- Test a complete reboot and LAN unlock while a keyboard and screen are still
  available. If DHCP or the NIC driver fails, enter the same passphrase locally.
- After installation, back up the LUKS header to external storage, e.g.
  `sudo cryptsetup luksHeaderBackup /dev/disk/by-partlabel/disk-main-root --header-backup-file /path/on/external/storage/rizos-luks-header.img`.
  Store it securely alongside recovery information; it does not replace data
  backups. Test that you can unlock using your saved passphrase.
- The EFI partition, kernel and initrd are **not encrypted**. The early-boot SSH
  host key is necessarily present there; never reuse a normal host or personal
  private key for it. This setup protects data at rest, not against someone
  tampering with the boot environment and returning the machine. Secure Boot
  with a verified boot chain would require additional configuration.
- No Tailscale service is available before unlock. LAN access is sufficient for
  this configuration. Reboots are remote, but still require you to unlock.
