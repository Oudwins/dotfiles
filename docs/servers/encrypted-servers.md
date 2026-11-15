# Encrypted servers with LAN SSH unlock

Two independent, reusable NixOS files are available:

- `hosts/common/disks/encryptedDisko.nix`: a UEFI GPT layout with a 1 GiB EFI
  partition and LUKS2-encrypted ext4 root. No swap or automatic disk-unlock key.
- `modules/system/remote-unlock.nix`: early-boot SSH on port 2222, wired IPv4
  DHCP, and an interactive disk-password prompt. Networkd hosts automatically
  reuse its LAN configuration after unlocking. It does not change accounts,
  bootloaders, disk layouts, or the normal networking backend.

## Use on a new server

```nix
{ config, configLib, inputs, ... }:
{
  imports = [
    inputs.disko.nixosModules.disko
    (configLib.relativeToRoot "hosts/common/disks/encryptedDisko.nix")
    (configLib.relativeToRoot "modules/system/remote-unlock.nix")
  ];

  disko.devices.disk.main.device = "/dev/nvme0n1";
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # Use the actual Ethernet driver; hardware generation may omit it from initrd.
  boot.initrd.availableKernelModules = [ "igc" ];

  # Optional: otherwise the initrd uses root's authorized keys/key files.
  boot.initrd.network.ssh.authorizedKeys =
    config.users.users.tmx.openssh.authorizedKeys.keys;
}
```

Configure the host's users, hardware, and networking backend separately. For a
networkd-based host:

```nix
networking.useNetworkd = true;
networking.useDHCP = false;
```

The module shares `10-lan` between both boot stages automatically, keeping the
DHCP identity consistent. Configure static addressing or interface matching under
`boot.initrd.systemd.network.networks."10-lan"`; networkd uses that same
configuration after unlocking. Review existing networkd rules to avoid conflicts.

For other networking setups, including NetworkManager, normal networking is left
untouched. Reserve a LAN IP for the Ethernet MAC and ensure the initrd DHCP client
identity is appropriate for your router.

## Installation and configuration

Use `scripts/bootstrap-encrypted.sh`, copied from the existing VPS bootstrap
script and extended for this encrypted layout:

```bash
sudo ./scripts/bootstrap-encrypted.sh -n <hostname> -d root@<LAN-IP>
```

It confirms disk erasure, prompts twice for the disk passphrase, copies the SOPS
master key, generates and pins a **unique** early-boot SSH host key, and runs
`nixos-anywhere` with hardware generation. Disk and key paths and the unlock
port are read from the selected host's Nix configuration. The passphrase is
sent only to the live installer, never copied into the installed OS.

- The script supports the shared layout's single disk, single LUKS root, and one
  early-boot SSH host key. Use the same CLI options as `bootstrap-vps.sh`;
  `--help` lists them. The original bootstrap scripts are unchanged.
- Customize the installation password path with the native
  `disko.devices.disk.main.content.partitions.root.content.passwordFile` option;
  it must be under `/tmp`. The script reads this value automatically.
- Never reuse a normal host or personal private key for early-boot SSH. Retain
  the generated key on the installed host for rebuilds and back it up securely.
- Customize the port, host keys, or authorized keys using the native
  `boot.initrd.network.ssh` options. Defaults are port 2222 and root's authorized
  keys/key files. No separate custom option layer is required.
- Keep the unlock service on a trusted LAN. Its SSH host key and the boot
  environment necessarily reside on the unencrypted boot partition.

See [the Rizos installation guide](../hosts/rizos/README.md) for a complete
installation command, host-key pinning, unlock commands, and recovery notes.

## Existing servers

For an **already encrypted** server, import only `remote-unlock.nix`, supply its
dedicated initrd host key, and include its Ethernet driver in the initrd. Test
with physical console access before relying on remote unlock.

For an **unencrypted** server, importing the disk layout and running
`nixos-rebuild switch` does **not** encrypt existing data. Plan a backup,
reinstallation with the encrypted layout, and data restore. Replace the existing
unencrypted disk-layout import rather than importing both. Running disko or
`nixos-anywhere` with this layout erases the selected disk.

No existing host is changed merely by adding these reusable files.
