{ lib, pkgs, ... }:

{
  home.file.".config/ghostty/config.ghostty".text = ''
    # disable topbar. So it behaves like alacritty
    gtk-titlebar = false
    gtk-tabs-location = hidden
    confirm-close-surface = false


    # Window settings
    window-padding-x = 0
    window-padding-y = 0

    # Terminal settings
    term = xterm-256color


    # Color scheme from omarchy theme
    background = 1a1b26
    foreground = a9b1d6

    # Normal colors
    palette = 0=#32344a
    palette = 1=#f7768e
    palette = 2=#9ece6a
    palette = 3=#e0af68
    palette = 4=#7aa2f7
    palette = 5=#ad8ee6
    palette = 6=#449dab
    palette = 7=#787c99

    # Bright colors
    palette = 8=#444b6a
    palette = 9=#ff7a93
    palette = 10=#b9f27c
    palette = 11=#ff9e64
    palette = 12=#7da6ff
    palette = 13=#bb9af7
    palette = 14=#0db9d7
    palette = 15=#acb0d0

    # Selection color
    selection-background = 7aa2f7
  '' + lib.optionalString pkgs.stdenv.isDarwin ''

    keybind = cmd+k=esc:k
  '';
}
