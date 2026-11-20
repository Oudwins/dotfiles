# Workstation dashboard: Glance at http://localhost:41111 listing every
# my.dashboard.services entry. Modules add their local (or remote) services.
{ config, ... }:

{
  imports = [ ../../../shared/dashboard ];

  services.glance = {
    enable = true;
    settings = config.my.dashboard.settings // {
      server = {
        # Glance listens on every interface unless told otherwise.
        host = "127.0.0.1";
        port = 41111;
      };
    };
  };
}
