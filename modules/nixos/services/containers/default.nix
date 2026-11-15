{
  config,
  lib,
  pkgs,
  ...
}:
{

  virtualisation = {

    # Docker config
    docker = {
      enable = true;
      autoPrune = {
        enable = true;
        dates = "weekly";
      };
      # Set up resource limits
      daemon.settings = {
        experimental = true;
        default-address-pools = [
          {
            base = "172.30.0.0/16";
            size = 24;
          }
        ];
      };
    };
    oci-containers = {
      backend = "docker";
    };

    # Podman config
    # podman = {
    #   enable = true;
    #   dockerCompat = true;
    #   dockerSocket.enable = true;
    #   defaultNetwork.settings.dns_enabled = true;
    #   autoPrune.enable = true;
    # };

  };

}
