{
  config,
  configLib,
  lib,
  pkgs,
  ...
}:
let
  driverName = "iHD";
in
{
  # GPU Accelerated video playback
  hardware.graphics = {
    enable = true;
    extraPackages = with pkgs; [
      intel-media-driver
    ];
  };
  environment.sessionVariables = {
    LIBVA_DRIVER_NAME = driverName;
  };
  my.hardwareAcceleration.LIBVA_DRIVER_NAME = driverName;
  my.hardwareAcceleration.enable = true;
}
