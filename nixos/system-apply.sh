#!bin/sh
pushhd ~/.dotfiles/nixos/
sudo nixos-rebuild switch --flake .#
popd
