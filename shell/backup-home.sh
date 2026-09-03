#!/bin/bash

set -e

# Colorize terminal
red='\e[0;31m'
green='\e[0;32m'
grey='\e[0;37m'
no_color='\033[0m'
# Console step increment
i=1

# Get Date
NOW=$(date +'%Y-%m-%dT%H-%M-%S')

# Default
BACKUP_DIR="$(pwd)/backup-$NOW"
BACKUP_COMPRESSION="false"
BACKUP_COMPRESSION_ARGS="--no-compress"
BACKUP_FULL="false"
DRY_RUN="false"

# Directories backed up when -f is not given, override with
# BACKUP_SOURCES="$HOME/Projects $HOME/Documents".
: "${BACKUP_SOURCES:=$HOME/Projects}"

# Declare script helper
TEXT_HELPER="\nThis script aims to copy important files and directories before a restoration.
Following flags are available:

  -c    (Optional) Use rsync compression during backup.
        Default is '$BACKUP_COMPRESSION'.

  -f    (Optional) Perform a full backup of the entire home directory (for personal use).
        Default is '$BACKUP_FULL'.

  -n    (Optional) Dry run, list what would be copied without writing anything.

  -o    (Optional) Output directory.
        Default is '$(pwd)'.

  -h    Print script help.\n\n"

print_help() {
  printf "%b" "$TEXT_HELPER"
}

# Parse options
while getopts hcfno: flag; do
  case "${flag}" in
    c)
      BACKUP_COMPRESSION="true"
      BACKUP_COMPRESSION_ARGS="--compress";;
    f)
      BACKUP_FULL="true";;
    n)
      DRY_RUN="true";;
    o)
      BACKUP_DIR="${OPTARG%/}/backup-$NOW";;
    h | *)
      print_help
      exit 0;;
  esac
done

RSYNC_ARGS=(-ahW "$BACKUP_COMPRESSION_ARGS" --info=progress2)
[ "$DRY_RUN" = "true" ] && RSYNC_ARGS+=(--dry-run)

# Settings
printf "\nScript settings:
  -> backup target dir: ${red}${BACKUP_DIR}${no_color}
  -> use compression: ${red}${BACKUP_COMPRESSION}${no_color}
  -> full backup: ${red}${BACKUP_FULL}${no_color}
  -> dry run: ${red}${DRY_RUN}${no_color}\n"

# Only copy sources that exist, rsync aborts on a missing one
existing_sources() {
  local src
  for src in "$@"; do
    if [ -e "$src" ]; then
      printf "%s\n" "$src"
    else
      printf "${grey}  skipping missing %s${no_color}\n" "$src" >&2
    fi
  done
}

backup() {
  local label="$1" target="$2"
  shift 2

  printf "\n${red}${i}.${no_color} %s\n\n" "$label"
  i=$(($i + 1))

  local sources=()
  while IFS= read -r src; do
    sources+=("$src")
  done < <(existing_sources "$@")

  if [ ${#sources[@]} -eq 0 ]; then
    printf "${grey}  nothing to copy${no_color}\n"
    return 0
  fi

  mkdir -p "$target"
  rsync "${RSYNC_ARGS[@]}" "${sources[@]}" "$target"
}

# Backup /etc files
backup "Backup /etc files" "${BACKUP_DIR%/}/etc" \
  /etc/hosts \
  /etc/resolv.conf

# Backup dotfiles. ~/.config is mostly application caches, which can run into
# tens of GB, so drop the known offenders rather than the whole directory.
RSYNC_ARGS+=(
  --exclude '.config/*/Cache/**'
  --exclude '.config/*/CachedData/**'
  --exclude '.config/*/Code Cache/**'
  --exclude '.config/*/GPUCache/**'
  --exclude '.config/*/Service Worker/CacheStorage/**'
  --exclude '.config/*/logs/**'
)
backup "Backup dotfiles" "${BACKUP_DIR%/}/dotfiles" \
  "$HOME/.aws" \
  "$HOME/.config" \
  "$HOME/.docker" \
  "$HOME/.gitconfig" \
  "$HOME/.gnupg" \
  "$HOME/.kube" \
  "$HOME/.mc" \
  "$HOME/.npmrc" \
  "$HOME/.ssh" \
  "$HOME/.zshrc"

# Backup home directory
if [ "$BACKUP_FULL" = "true" ]; then
  HOME_DIRS=("$HOME")
else
  # Word splitting is intended here, BACKUP_SOURCES is a space separated list
  HOME_DIRS=($BACKUP_SOURCES)
fi

RSYNC_ARGS+=(--exclude '**/node_modules' --exclude '**/.venv' --exclude '**/target')
backup "Backup home directory" "${BACKUP_DIR%/}/home" "${HOME_DIRS[@]}"

printf "\n${green}Backup written to %s${no_color}\n" "$BACKUP_DIR"
