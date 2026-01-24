{
  ...
}:

{
  programs.git = {
    enable = true;
    userName = "tristan";
    userEmail = "tm@tristanmayo.com";
    extraConfig = {
      push = {
        autoSetupRemote = true;
      };
      pack = {
        windowMemory = "256m";
        packSizeLimit = "256m";
      };
    };
  };
}
