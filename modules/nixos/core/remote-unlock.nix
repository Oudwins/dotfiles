# Import to enable wired LAN SSH unlocking for an encrypted root filesystem.
# This does not change disk layouts, accounts, or the normal networking backend.
{ config, lib, ... }:

{
  # Networkd hosts use the same MAC-based DHCP identity in both boot stages.
  systemd.network.networks = lib.mkIf config.networking.useNetworkd {
    "10-lan" = config.boot.initrd.systemd.network.networks."10-lan";
  };

  boot.initrd = {
    systemd = {
      enable = true;
      network.networks."10-lan" = {
        matchConfig.Name = lib.mkDefault "en* eth*";
        networkConfig.DHCP = lib.mkDefault "ipv4";
        dhcpV4Config = {
          ClientIdentifier = lib.mkDefault "mac";
          Hostname = lib.mkDefault config.networking.hostName;
        };
      };
      # SSH goes straight to the LUKS password prompt, not a root shell.
      users.root.shell = "/bin/systemd-tty-ask-password-agent";
    };
    network = {
      enable = true;
      ssh = {
        enable = true;
        port = lib.mkDefault 2222;
        # Supply a dedicated private key during installation, never through Git.
        hostKeys = lib.mkDefault [ "/etc/secrets/initrd/ssh_host_ed25519_key" ];
        # Native NixOS defaults reuse root's authorized keys and key files.
        extraConfig = ''
          AddressFamily inet
          AllowTcpForwarding no
          AllowAgentForwarding no
          X11Forwarding no
        '';
      };
    };
  };
}
