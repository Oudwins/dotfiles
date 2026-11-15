# Import alongside inputs.disko.nixosModules.disko and set
# disko.devices.disk.main.device in the host configuration.
{ config, lib, ... }:

{
  disko.devices.disk.main = {
    type = "disk";
    content = {
      type = "gpt";
      partitions = {
        ESP = {
          size = "1G";
          type = "EF00";
          content = {
            type = "filesystem";
            format = "vfat";
            mountpoint = "/boot";
            mountOptions = [ "umask=0077" ];
          };
        };
        root = {
          size = "100%";
          content = {
            type = "luks";
            name = "cryptroot";
            extraFormatArgs = [ "--type" "luks2" ];
            # Only used by disko in the live installer, not for boot unlocking.
            passwordFile = lib.mkDefault "/tmp/${config.networking.hostName}-luks-password";
            settings.crypttabExtraOpts = [ "tries=0" "timeout=0" ];
            content = {
              type = "filesystem";
              format = "ext4";
              mountpoint = "/";
            };
          };
        };
      };
    };
  };
}
