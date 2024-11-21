#!/bin/sh

# Define the directory
directory="$HOME/dotfiles/"

# Change directory
cd "$directory" || exit

# Execute the command
#echo "currently working in '${pwd}'"
stow -d tmx -t ~ .
