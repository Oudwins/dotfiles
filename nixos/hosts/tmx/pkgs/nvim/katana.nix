{
  config,
  lib,
  pkgs,
  ...
}:

{
  # Enable uinput kernel module for input remapping
  boot.kernelModules = [ "uinput" ];

  # Enable uinput device
  hardware.uinput.enable = true;

  # Configure udev rules for uinput device permissions
  services.udev.extraRules = ''
    KERNEL=="uinput", MODE="0660", GROUP="uinput", OPTIONS+="static_node=uinput"
  '';

  # Ensure uinput group exists
  users.groups.uinput = { };

  # Configure Kanata service
  services.kanata = {
    enable = true;
    keyboards.default = {
      # Find these paths with: ls /dev/input/by-path/
      # Using wildcard patterns for all keyboards
      devices = [
        "/dev/input/by-path/pci-0000:07:00.3-usb-0:2:1.0-event-kbd"
        "/dev/input/by-path/pci-0000:07:00.3-usb-0:2:1.1-event-kbd"
        "/dev/input/by-path/pci-0000:07:00.3-usbv2-0:2:1.0-event-kbd"
        "/dev/input/by-path/pci-0000:07:00.3-usbv2-0:2:1.1-event-kbd"
        "/dev/input/by-path/pci-0000:07:00.4-usb-0:2.4:1.1-event-kbd"
        "/dev/input/by-path/pci-0000:07:00.4-usbv2-0:2.4:1.1-event-kbd"
        "/dev/input/by-path/platform-i8042-serio-0-event-kbd"
      ];

      # Process unmapped keys to let other keys work normally
      extraDefCfg = "process-unmapped-keys yes";

      config = ''
        (defsrc
          caps esc
        )

        (deflayer base
          esc caps
        )
      '';
    };
  };
}
