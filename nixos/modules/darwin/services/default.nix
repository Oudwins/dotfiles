{ pkgs, ... }:

{
  launchd.agents."colima.default" = {
    command = "${pkgs.colima}/bin/colima start --foreground";
    serviceConfig = {
      Label = "com.colima.default";
      RunAtLoad = true;
      KeepAlive = {
        SuccessfulExit = true;
      };
      StandardOutPath = "/tmp/colima.default.stdout.log";
      StandardErrorPath = "/tmp/colima.default.stderr.log";
      EnvironmentVariables = {
        PATH = "${pkgs.colima}/bin:${pkgs.docker}/bin:/usr/bin:/bin:/usr/sbin:/sbin";
      };
    };
  };

  # Linux VM running a T3 Code server (port spaces), forwarded to 127.0.0.1:13773.
  launchd.agents."colima.t3-e2e" = {
    command = "${pkgs.colima}/bin/colima start --profile t3-e2e --foreground";
    serviceConfig = {
      Label = "com.colima.t3-e2e";
      RunAtLoad = true;
      KeepAlive = {
        SuccessfulExit = true;
      };
      StandardOutPath = "/tmp/colima.t3-e2e.stdout.log";
      StandardErrorPath = "/tmp/colima.t3-e2e.stderr.log";
      EnvironmentVariables = {
        PATH = "${pkgs.colima}/bin:/usr/bin:/bin:/usr/sbin:/sbin";
      };
    };
  };
}
