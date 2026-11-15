# Notes

## Tailscale exit node

```bash
# Connect to tubby
sudo tailscale set --exit-node=tubby
# Disconnect
sudo tailscale set --exit-node=

```

## macOS setup

```bash
just switch
sudo cli-proxy-api -claude-login --no-browser
```

- Aerospace WM
  - https://www.youtube.com/watch?v=5nwnJjr5eOo&t=647s
  - sketchybar
  - sketchyBorder or something like that
- Allacritty Terminal -> or ghostty
  - Starship
- Raycast
  - Disable spotlight
- Cursor
- https://github.com/koekeishiya/skhd
  - Hotkeys to launch apps
- remap keys
  - https://github.com/pqrs-org/Karabiner-Elements
- Direnv
- screenshot tool -> Shottr

- Finder show path bar


## Nix

```bash
# quickly test the build of a specific package
nix-build --expr '(import <nixpkgs> { }).callPackage ./package.nix { }'
```

## To add at some point
- https://github.com/junhoyeo/tokscale
