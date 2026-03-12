#!/usr/bin/env bash
set -euo pipefail

CHANNEL="<nixpkgs/nixos>"
CONTAINER_NAME=""
QUIET=0
FORCE=0

usage() {
  echo "Usage: $0 [-c channel] [-n name] [-q] [-f] <configuration.nix>" >&2
  exit 1
}

while getopts ":c:n:qf" opt; do
  case "$opt" in
    c) CHANNEL="$OPTARG" ;;
    n) CONTAINER_NAME="$OPTARG" ;;
    q) QUIET=1 ;;
    f) FORCE=1 ;;
    *) usage ;;
  esac
done
shift $((OPTIND - 1))

CONFIG="${1:-}"
if [[ -z "$CONFIG" ]]; then
  usage
fi

if [[ ! -f "$CONFIG" ]]; then
  echo "Error: configuration file '$CONFIG' not found" >&2
  exit 1
fi

info() {
  if [[ "$QUIET" -eq 0 ]]; then
    echo "info: $*" >&2
  fi
}

# Build the initial system derivation first, before creating any directories
info "Building system from $CONFIG (channel: $CHANNEL)"
SYSTEM_PATH="$(nix-build "$CHANNEL" -A system -I "nixos-config=$CONFIG" --no-out-link)"

# Generate a unique container ID
CONTAINER_ID="$(uuidgen)"
echo "$CONTAINER_ID"

# If no name override, use the ID as the machine name
if [[ -z "$CONTAINER_NAME" ]]; then
  CONTAINER_NAME="$CONTAINER_ID"
fi

GCROOT="/nix/var/nix/gcroots/per-container/$CONTAINER_ID"
ROOTFS="/var/lib/machines/$CONTAINER_NAME"
NSPAWN_FILE="/etc/systemd/nspawn/$CONTAINER_NAME.nspawn"

# Check for existing paths
if [[ "$FORCE" -eq 0 ]]; then
  CONFLICT=0
  for path in "$GCROOT" "$ROOTFS" "$NSPAWN_FILE"; do
    if [[ -e "$path" ]]; then
      echo "Error: $path already exists" >&2
      CONFLICT=1
    fi
  done
  if [[ "$CONFLICT" -eq 1 ]]; then
    echo "Use -f to force overwrite" >&2
    exit 1
  fi
fi

# Create gcroot directory
info "Creating gcroot directory: $GCROOT"
mkdir -p "$GCROOT"

# Link the system derivation into the gcroot
info "Linking system derivation to $GCROOT/system"
ln -s "$SYSTEM_PATH" "$GCROOT/system"

# Create rootfs and copy the initial configuration
info "Creating rootfs directory: $ROOTFS"
mkdir -p "$ROOTFS/etc/nixos"
info "Copying configuration to $ROOTFS/etc/nixos/configuration.nix"
cp "$CONFIG" "$ROOTFS/etc/nixos/configuration.nix"

# Copy os-release from the system derivation
# nspawn quirk: it needs to see a "os rootfs tree". /etc gets overwritten by nix
info "Symlinking os-release into rootfs"
mkdir -p "$ROOTFS/usr/lib"
cp $(readlink -f "$SYSTEM_PATH/etc/os-release") "$ROOTFS/usr/lib/os-release"

# Symlink init so the container can boot
info "Symlinking /sbin/init into rootfs"
mkdir -p "$ROOTFS/sbin"
ln -sf /nix/var/nix/profiles/system/init "$ROOTFS/sbin/init"

# Create bind mount destinations inside rootfs
info "Creating bind mount destinations in rootfs"
mkdir -p "$ROOTFS/nix/var/nix/profiles"
mkdir -p "$ROOTFS/nix/var/nix/daemon-socket"
touch "$ROOTFS/nix/var/nix/daemon-socket/socket"
mkdir -p "$ROOTFS/nix/store"
mkdir -p "$ROOTFS/nix/var/nix/db"

# Create the nspawn machine file
info "Creating nspawn file: $NSPAWN_FILE"
mkdir -p /etc/systemd/nspawn
cat > "$NSPAWN_FILE" <<EOF
[Exec]
Parameters=/nix/var/nix/profiles/system/init

[Files]
Bind=/nix/var/nix/gcroots/per-container/$CONTAINER_ID:/nix/var/nix/profiles:idmap
Bind=/nix/var/nix/daemon-socket/socket
BindReadOnly=/nix/store
BindReadOnly=/nix/var/nix/db
EOF
