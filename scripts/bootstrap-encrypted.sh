#!/usr/bin/env bash
set -euo pipefail
umask 077

target_hostname=""
target_destination=""
host_config_dir=""
source_master_key_path="/etc/ssh/ssh_master_key"
target_master_key_path="/etc/ssh/ssh_master_key"
ssh_home="$HOME"
if [[ -n ${SUDO_USER:-} && $SUDO_USER != root ]]; then
  ssh_home=$(getent passwd "$SUDO_USER" | cut -d: -f6)
fi
ssh_key="${ssh_home}/.ssh/id_ed25519"
ssh_port="22"

usage() {
  echo "USAGE: $0 -n <target_hostname> -d <target_destination> [OPTIONS]"
  echo "Required arguments:"
  echo "  -n <target_hostname>     Flake host name, for example rizos"
  echo "  -d <target_destination>  SSH target, for example root@192.168.1.50"
  echo "Optional arguments:"
  echo "  -k <ssh_key>             SSH key path (default: ${ssh_home}/.ssh/id_ed25519)"
  echo "  --host-config-dir <dir>  Relative or absolute host directory"
  echo "  --source-master-key      Local master key path (default: /etc/ssh/ssh_master_key)"
  echo "  --target-master-key      Install path for the master key (default: /etc/ssh/ssh_master_key)"
  echo "  --port <ssh_port>        SSH port for the installer environment (default: 22)"
  echo ""
  echo "Uses encryptedDisko.nix with one disk, one LUKS root, and one early-boot SSH host key."
  echo "Prompts for disk-erasure confirmation and a new disk passphrase."
}

expand_path() {
  case $1 in
    \~) printf '%s\n' "$ssh_home" ;;
    \~/*) printf '%s/%s\n' "$ssh_home" "${1:2}" ;;
    *) printf '%s\n' "$1" ;;
  esac
}

resolve_host_dir() {
  local repo_root=$1
  local requested_dir=$2
  local host_name=$3
  local default_dir="${repo_root}/hosts/${host_name}"
  local -a matches

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

while [[ $# -gt 0 ]]; do
  case $1 in
    -n)
      target_hostname=${2:?Missing hostname after -n}
      shift 2
      ;;
    -d)
      target_destination=${2:?Missing SSH target after -d}
      shift 2
      ;;
    -k)
      ssh_key=$(expand_path "${2:?Missing SSH key after -k}")
      shift 2
      ;;
    --host-config-dir)
      host_config_dir=${2:?Missing directory after --host-config-dir}
      shift 2
      ;;
    --source-master-key)
      source_master_key_path=$(expand_path "${2:?Missing source master key}")
      shift 2
      ;;
    --target-master-key)
      target_master_key_path=${2:?Missing target master-key path}
      shift 2
      ;;
    --port)
      ssh_port=${2:?Missing installer SSH port}
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [[ -z $target_hostname || -z $target_destination ]]; then
  usage >&2
  exit 1
fi

if [[ ! -r $source_master_key_path ]]; then
  echo "Cannot read source master key: ${source_master_key_path}" >&2
  exit 1
fi

if [[ ! -r $ssh_key ]]; then
  echo "Cannot read SSH key: ${ssh_key}" >&2
  exit 1
fi

if [[ $target_master_key_path != /* || $target_master_key_path == *'/../'* || $target_master_key_path == *'/..' ]]; then
  echo "The target master-key path must be an absolute path without '..'." >&2
  exit 1
fi

repo_root=$(git rev-parse --show-toplevel)
resolved_host_dir=$(resolve_host_dir "$repo_root" "$host_config_dir" "$target_hostname")
hardware_config_path="${resolved_host_dir}/hardware-configuration.nix"

if [[ ! -f ${resolved_host_dir}/default.nix ]]; then
  echo "Host config not found at ${resolved_host_dir}/default.nix" >&2
  exit 1
fi

# Flake refs go through git so gitignored files (credentials in home-files/)
# never reach the store. nixos-anywhere writes the hardware config during the
# install, so make sure git already tracks the path (intent-to-add).
if [[ ! -e $hardware_config_path ]]; then
  printf '{ }\n' > "$hardware_config_path"
fi
git -C "$repo_root" add --intent-to-add -- "$hardware_config_path"

# Read the shared layout's effective settings rather than duplicating its paths.
host_settings=$(nix eval --raw \
  "${repo_root}#nixosConfigurations.${target_hostname}.config" \
  --apply 'c:
    let
      root = c.disko.devices.disk.main.content.partitions.root.content;
      ssh = c.boot.initrd.network.ssh;
    in
    assert builtins.attrNames c.disko.devices.disk == [ "main" ];
    assert root.type == "luks";
    assert root.passwordFile != null;
    assert ssh.enable;
    assert builtins.length ssh.hostKeys == 1;
    assert builtins.isString (builtins.head ssh.hostKeys);
    builtins.concatStringsSep "\n" [
      c.disko.devices.disk.main.device
      root.passwordFile
      (builtins.head ssh.hostKeys)
      (toString ssh.port)
    ]')
mapfile -t settings <<< "$host_settings"
disk=${settings[0]}
luks_password_path=${settings[1]}
initrd_host_key_path=${settings[2]}
unlock_port=${settings[3]}

if [[ $luks_password_path != /tmp/* || $luks_password_path == *'/../'* || $luks_password_path == *'/..' ]]; then
  echo "The LUKS installation password file must be under /tmp without '..'." >&2
  exit 1
fi
if [[ $initrd_host_key_path != /* || $initrd_host_key_path == /nix/store/* || $initrd_host_key_path == *'/../'* || $initrd_host_key_path == *'/..' ]]; then
  echo "The initrd SSH host key must use an absolute path outside the Nix store, without '..'." >&2
  exit 1
fi

echo "WARNING: Installing ${target_hostname} on ${target_destination} ERASES ${disk}."
read -r -p "Type '${target_hostname}' to continue: " confirmation
if [[ $confirmation != "$target_hostname" ]]; then
  echo "Installation cancelled." >&2
  exit 1
fi

temp_dir=$(mktemp -d)
cleanup() {
  rm -rf "$temp_dir"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
extra_files_dir="${temp_dir}/extra-files"

# Keep the passphrase out of traces, even if invoked with bash -x.
set +x
read -r -s -p "New disk passphrase: " passphrase
echo
read -r -s -p "Repeat disk passphrase: " confirmation
echo
if [[ -z $passphrase || $passphrase != "$confirmation" ]]; then
  echo "Disk passphrases must be nonempty and match." >&2
  exit 1
fi
printf '%s' "$passphrase" > "${temp_dir}/luks-password"
unset passphrase confirmation

install -D -m600 "$source_master_key_path" "$extra_files_dir$target_master_key_path"
install -d -m700 "$(dirname "$extra_files_dir$initrd_host_key_path")"
ssh-keygen -t ed25519 -N '' -f "$extra_files_dir$initrd_host_key_path"

(
  cd "$repo_root"
  SHELL=/bin/sh nix run github:nix-community/nixos-anywhere -- \
    --flake "${repo_root}#${target_hostname}" \
    --target-host "$target_destination" \
    -i "$ssh_key" \
    --ssh-port "$ssh_port" \
    --ssh-option StrictHostKeyChecking=no \
    --ssh-option UserKnownHostsFile=/dev/null \
    --extra-files "$extra_files_dir" \
    --disk-encryption-keys "$luks_password_path" "${temp_dir}/luks-password" \
    --generate-hardware-config nixos-generate-config "$hardware_config_path"
)

# Pin only this server's initrd identity after a successful installation.
host_key_alias="${target_hostname}-initrd"
known_hosts_file="${ssh_home}/.ssh/known_hosts"
mkdir -p "${ssh_home}/.ssh"
touch "$known_hosts_file"
ssh-keygen -R "$host_key_alias" -f "$known_hosts_file" >/dev/null
printf '%s %s\n' "$host_key_alias" "$(cat "$extra_files_dir$initrd_host_key_path.pub")" >> "$known_hosts_file"
if [[ -n ${SUDO_USER:-} && $SUDO_USER != root ]]; then
  chown "${SUDO_UID}:${SUDO_GID}" "${ssh_home}/.ssh" "$known_hosts_file"
fi

echo "Installation finished. Unlock after boot with:"
printf 'ssh -t -i %q -o HostKeyAlias=%q -p %q %q\n' \
  "$ssh_key" "$host_key_alias" "$unlock_port" "root@${target_destination##*@}"
