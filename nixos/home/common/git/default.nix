{
  ...
}:

{
  programs.git = {
    enable = true;
    settings = {
      user = {
        name = "tristan";
        email = "tm@tristanmayo.com";
      };
      push = {
        default = "current";
        autoSetupRemote = true;
      };
      pull = {
        rebase = true;
      };
      pack = {
        windowMemory = "256m";
        packSizeLimit = "256m";
      };
    };
  };
}
