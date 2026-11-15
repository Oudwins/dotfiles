{ config, pkgs, ... }:

{
  services.udisks2.enable = true;
  services.gvfs.enable = true;
  services.davfs2.enable = true;

  sops.secrets."nextcloud/autofs_secrets_file" = {
    mode = "600";
    path = "/etc/davfs2/secrets";
  };

  systemd.tmpfiles.rules = [
    "d /mnt/nextcloud 0777 tmx users"
  ];

  fileSystems."/mnt/nextcloud" = {
    device = "https://cloud.tristanmayo.com/remote.php/webdav/";
    fsType = "davfs";
    options = [
      "user"
      "rw"
      "noauto"
      "_netdev"
      "mode=0777"
    ];
  };

  systemd.services."mount-nextcloud" = {
    description = "Mount Nextcloud WebDAV filesystem";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "/run/current-system/sw/bin/mount -o uid=${toString config.users.users.tmx.uid},gid=${toString config.users.groups.users.gid} /mnt/nextcloud";
      ExecStop = "/run/current-system/sw/bin/umount /mnt/nextcloud";
      RemainAfterExit = true;
      User = "root";
      Group = "root";
      IgnoreSIGPIPE = "no";
      FailureAction = "ignore";
    };
  };

  security.sudo.extraRules = [
    {
      users = [ "tmx" ];
      commands = [
        {
          command = "/run/current-system/sw/bin/mount";
          options = [ "NOPASSWD" ];
        }
      ];
    }
  ];
}
