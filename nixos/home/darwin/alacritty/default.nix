{ pkgs, ... }:

{
  programs.alacritty = {
    enable = true;
    settings = {
      # Map Command+N to send Meta+N (Alt+N) escape sequences
      # This allows tmux M-n bindings to work with Command key on macOS
      keyboard.bindings = [
        # Window switching (Command+1-8 -> Meta+1-8)
        { key = "1"; mods = "Command"; chars = "\\u001b1"; }
        { key = "2"; mods = "Command"; chars = "\\u001b2"; }
        { key = "3"; mods = "Command"; chars = "\\u001b3"; }
        { key = "4"; mods = "Command"; chars = "\\u001b4"; }
        { key = "5"; mods = "Command"; chars = "\\u001b5"; }
        { key = "6"; mods = "Command"; chars = "\\u001b6"; }
        { key = "7"; mods = "Command"; chars = "\\u001b7"; }
        { key = "8"; mods = "Command"; chars = "\\u001b8"; }

        # Common Command key mappings to Meta equivalents
        { key = "H"; mods = "Command"; chars = "\\u001bh"; }
        { key = "L"; mods = "Command"; chars = "\\u001bl"; }
        { key = "J"; mods = "Command"; chars = "\\u001bj"; }
        { key = "K"; mods = "Command"; chars = "\\u001bk"; }
      ];

      # Optional: Make Option key behave as Alt/Meta as well
      window.option_as_alt = "Both";
    };
  };
}
