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
        autoSetupRemote = true;
      };
      pack = {
        windowMemory = "256m";
        packSizeLimit = "256m";
      };
    };
  };
}
