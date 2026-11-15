#!/usr/bin/env bash
set -euo pipefail

target_hostname=""
target_destination=""
host_config_dir=""
source_master_key_path="/etc/ssh/ssh_master_key"
target_master_key_path="/etc/ssh/ssh_master_key"
ssh_key="${HOME}/.ssh/id_ed25519"
ssh_port="22"

temp_dir=$(mktemp -d)

cleanup() {
  rm -rf "$temp_dir"
}

usage() {
  echo "USAGE: $0 -n <target_hostname> -d <target_destination> [OPTIONS]"
  echo "Required arguments:"
  echo "  -n <target_hostname>     Flake host name, for example iss-prod"
  echo "  -d <target_destination>  SSH target, for example root@203.0.113.10"
  echo "Optional arguments:"
  echo "  -k <ssh_key>             SSH key path (default: ${HOME}/.ssh/id_ed25519)"
  echo "  --host-config-dir <dir>  Relative path to the host dir, for example hosts/iss"
  echo "  --source-master-key      Local master key path (default: /etc/ssh/ssh_master_key)"
  echo "  --target-master-key      Install path for the master key (default: /etc/ssh/ssh_master_key)"
  echo "  --port <ssh_port>        SSH port for the installer environment (default: 22)"
  exit 1
}

expand_path() {
  local path=$1
  if [[ $path == ~* ]]; then
    printf '%s\n' "${path/#\~/$HOME}"
  else
    printf '%s\n' "$path"
  fi
}

resolve_host_dir() {
  local repo_root=$1
  local requested_dir=$2
  local host_name=$3
  local default_dir="${repo_root}/hosts/${host_name}"

  if [[ -n $requested_dir ]]; then
    if [[ $requested_dir == /* ]]; then
      printf '%s\n' "$requested_dir"
    else
      printf '%s\n' "${repo_root}/${requested_dir}"
    fi
    return 0
  fi

  if [[ -d $default_dir ]]; then
    printf '%s\n' "$default_dir"
    return 0
  fi

  mapfile -t matches < <(find "${repo_root}/hosts" -path "*/${host_name}/default.nix")

  if [[ ${#matches[@]} -eq 1 ]]; then
    dirname "${matches[0]}"
    return 0
  fi

  if [[ ${#matches[@]} -gt 1 ]]; then
    echo "Multiple host directories matched ${host_name}; pass --host-config-dir explicitly." >&2
  else
    echo "Could not find a host directory for ${host_name}; pass --host-config-dir explicitly." >&2
  fi

  return 1
}

trap cleanup EXIT

while [[ $# -gt 0 ]]; do
  case $1 in
    -n)
      target_hostname=$2
      shift 2
      ;;
    -d)
      target_destination=$2
      shift 2
      ;;
    -k)
      ssh_key=$(expand_path "$2")
      shift 2
      ;;
    --host-config-dir)
      host_config_dir=$2
      shift 2
      ;;
    --source-master-key)
      source_master_key_path=$(expand_path "$2")
      shift 2
      ;;
    --target-master-key)
      target_master_key_path=$2
      shift 2
      ;;
    --port)
      ssh_port=$2
      shift 2
      ;;
    -h|--help)
      usage
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage
      ;;
  esac
done

if [[ -z $target_hostname || -z $target_destination ]]; then
  usage
fi

if [[ ! -r $source_master_key_path ]]; then
  echo "Cannot read source master key: ${source_master_key_path}" >&2
  exit 1
fi

if [[ ! -r $ssh_key ]]; then
  echo "Cannot read SSH key: ${ssh_key}" >&2
  exit 1
fi

repo_root=$(git rev-parse --show-toplevel)
resolved_host_dir=$(resolve_host_dir "$repo_root" "$host_config_dir" "$target_hostname")
hardware_config_path="${resolved_host_dir}/hardware-configuration.nix"

# Flake refs go through git so gitignored files (credentials in home-files/)
# never reach the store. nixos-anywhere writes the hardware config during the
# install, so make sure git already tracks the path (intent-to-add).
if [[ ! -e $hardware_config_path ]]; then
  printf '{ }\n' > "$hardware_config_path"
fi
git -C "$repo_root" add --intent-to-add -- "$hardware_config_path"

if [[ ! -f ${resolved_host_dir}/default.nix ]]; then
  echo "Host config not found at ${resolved_host_dir}/default.nix" >&2
  exit 1
fi

install -d -m755 "$temp_dir$(dirname "$target_master_key_path")"
cp "$source_master_key_path" "$temp_dir$target_master_key_path"
chmod 600 "$temp_dir$target_master_key_path"

(
  cd "$repo_root"
  SHELL=/bin/sh nix run github:nix-community/nixos-anywhere -- \
    --flake "${repo_root}#${target_hostname}" \
    --target-host "$target_destination" \
    -i "$ssh_key" \
    --ssh-port "$ssh_port" \
    --ssh-option StrictHostKeyChecking=no \
    --ssh-option UserKnownHostsFile=/dev/null \
    --extra-files "$temp_dir" \
    --generate-hardware-config nixos-generate-config "$hardware_config_path"
)
