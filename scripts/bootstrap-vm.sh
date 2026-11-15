#!/usr/bin/env bash


# User variables
target_hostname=""
target_destination=""
source_master_key_path="/etc/ssh/ssh_master_key"
target_master_key_path="/etc/ssh/ssh_master_key"
ssh_key="${HOME}/.ssh/id_ed25519"
ssh_port="22"

# Parse command line arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    -n)
      target_hostname="$2"
      shift 2
      ;;
    -d)
      target_destination="$2"
      shift 2
      ;;
    -k)
      ssh_key="$2"
      shift 2
      ;;
    --source-master-key)
      source_master_key_path="$2"
      shift 2
      ;;
    --target-master-key)
      target_master_key_path="$2"
      shift 2
      ;;
    --port)
      ssh_port="$2"
      shift 2
      ;;
    *)
      echo "Unknown option: $1"
      exit 1
      ;;
  esac
done

# Check for required arguments
if [[ -z $target_hostname || -z $target_destination ]]; then
  echo "USAGE: $0 -n <target_hostname> -d <target_destination> -k <ssh_key> [OPTIONS]"
  echo "Required arguments:"
  echo "  -n <target_hostname>    Specify the target hostname"
  echo "  -d <target_destination> Specify the target destination -> root@ip -> e.g root@192.168.1.1"
  echo "Optional arguments:"
  echo "  -k <ssh_key>            Specify the SSH key (default: ${HOME}/.ssh/id_ed25519)"
  echo "  --source-master-key     Specify the source master key path (default: /etc/ssh/ssh_master_key)"
  echo "  --target-master-key     Specify the target master key path (default: /etc/ssh/ssh_master_key)"
  echo "  --port                  Specify the SSH port (default: 22)"
  exit 1
fi




# Create a temporary directory
temp=$(mktemp -d)
# Function to cleanup temporary directory on exit
cleanup() {
  rm -rf "$temp"
}
trap cleanup EXIT

# Create the directory where sshd expects to find the host keys
install -d -m755 "$temp/etc/ssh"

# Decrypt your private key from the password store and copy it to the temporary directory
cat "$source_master_key_path" > "$temp$target_master_key_path"

# Set the correct permissions so sshd will accept the key
chmod 600 "$temp$target_master_key_path"


# Install NixOS to the host system with our secrets
SHELL=/bin/sh nix run github:nix-community/nixos-anywhere -- -i "$ssh_key" --ssh-port "$ssh_port" --extra-files "$temp" --flake "$(git rev-parse --show-toplevel)#$target_hostname" $target_destination
