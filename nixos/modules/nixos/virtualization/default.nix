{ config, pkgs, ... }:

{
  virtualisation = {
    spiceUSBRedirection.enable = true;
    libvirtd = {
      enable = true;
      qemu = {
        swtpm.enable = true;
      };
    };
    docker = {
      enable = true;
      rootless = {
        enable = true;
        setSocketVariable = true;
      };
    };
  };

  services.spice-vdagentd.enable = true;
  programs.virt-manager.enable = true;

  environment.systemPackages = with pkgs; [
    virt-manager
    virt-viewer
    spice
    spice-gtk
    spice-protocol
    win-spice
    qemu
  ];
}
