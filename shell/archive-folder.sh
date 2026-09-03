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
DRY_RUN="false"
EXCLUDES=()

# Declare script helper
TEXT_HELPER="\nThis script archives one or more folders into a timestamped directory.
It is the arbitrary-folder counterpart of backup-home.sh, which targets
/etc, the dotfiles and the home directory.

Usage: $(basename "$0") [flags] FOLDER [FOLDER...]

Following flags are available:

  -c    (Optional) Use rsync compression during backup.
        Default is '$BACKUP_COMPRESSION'.

  -e    (Optional) Exclude a pattern, can be repeated.
        Example: -e '**/node_modules' -e '**/.venv'

  -n    (Optional) Dry run, list what would be copied without writing anything.

  -o    (Optional) Output directory.
        Default is '$(pwd)'.

  -h    Print script help.\n\n"

print_help() {
  printf "%b" "$TEXT_HELPER"
}

# Parse options
while getopts hcne:o: flag; do
  case "${flag}" in
    c)
      BACKUP_COMPRESSION="true"
      BACKUP_COMPRESSION_ARGS="--compress";;
    e)
      EXCLUDES+=(--exclude "${OPTARG}");;
    n)
      DRY_RUN="true";;
    o)
      BACKUP_DIR="${OPTARG%/}/backup-$NOW";;
    h | *)
      print_help
      exit 0;;
  esac
done
shift $((OPTIND - 1))

# Remaining arguments are the folders to archive
if [ $# -eq 0 ]; then
  printf "${red}Error: no folder given.${no_color}\n"
  print_help
  exit 1
fi

RSYNC_ARGS=(-ahW "$BACKUP_COMPRESSION_ARGS" --info=progress2 "${EXCLUDES[@]}")
[ "$DRY_RUN" = "true" ] && RSYNC_ARGS+=(--dry-run)

# Settings
printf "\nScript settings:
  -> backup target dir: ${red}${BACKUP_DIR}${no_color}
  -> use compression: ${red}${BACKUP_COMPRESSION}${no_color}
  -> dry run: ${red}${DRY_RUN}${no_color}
  -> folders: ${red}$*${no_color}\n"

MISSING="false"
for folder in "$@"; do
  if [ ! -e "$folder" ]; then
    printf "${red}Error: no such folder: %s${no_color}\n" "$folder"
    MISSING="true"
  fi
done
[ "$MISSING" = "true" ] && exit 1

for folder in "$@"; do
  # Trailing slash matters to rsync, strip it so the folder itself is copied
  folder="${folder%/}"
  target="${BACKUP_DIR%/}/$(basename "$folder")"

  printf "\n${red}${i}.${no_color} Archiving %s\n\n" "$folder"
  i=$(($i + 1))

  mkdir -p "$target"
  rsync "${RSYNC_ARGS[@]}" "$folder/" "$target"
done

printf "\n${green}Archive written to %s${no_color}\n" "$BACKUP_DIR"
