{ ... }:

{
  homebrew.enable = true;
  homebrew.onActivation = {
    autoUpdate = true;
    upgrade = true;
  };
  homebrew.casks = [
    "cursor"
    "telegram"
    "beekeeper-studio"
    "obsidian"
    "obs"
    "bruno"
    "font-liberation"
  ];

  homebrew.brews = [
    "docker"
    "docker-compose"
    "docker-buildx"
    "pnpm"
    "imagemagick"
    "k6"
    "pnpm"
    "node"
    "syncthing"
    "uv"
    "poppler"
    "ffmpeg"
  ];
}
