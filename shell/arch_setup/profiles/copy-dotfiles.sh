#!/bin/bash
# Copy the repository dotfiles into $HOME, backing up whatever is replaced.

source "$(dirname "${BASH_SOURCE[0]}")/_common.sh"

# Resolved at run time so the checkout can live anywhere. Override with
# DOTFILES_DIR=/some/path to point at a different set of dotfiles.
resolve_dotfiles_dir() {
    [ -n "${DOTFILES_DIR:-}" ] && return 0

    local here root
    here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

    if root="$(repo_root "$here")"; then
        DOTFILES_DIR="$root/dotfiles"
        return 0
    fi

    return 1
}

copy_dotfiles() {
    if ! resolve_dotfiles_dir; then
        log "Could not locate the toolbox checkout from $(dirname "${BASH_SOURCE[0]}")" "$red"
        log "Set DOTFILES_DIR=/path/to/dotfiles to install them anyway" "$grey"
        return 0
    fi

    if [ ! -d "$DOTFILES_DIR" ]; then
        log "No dotfiles directory found at $DOTFILES_DIR" "$red"
        return 0
    fi

    log "Using dotfiles from $DOTFILES_DIR" "$grey"

    # Walk individual files rather than top-level entries. Copying whole
    # directories would mean backing up all of ~/.config (tens of GB) just to
    # replace a single settings.json.
    local entries=() entry
    while IFS= read -r -d '' entry; do
        entries+=("${entry#"$DOTFILES_DIR"/}")
    done < <(find "$DOTFILES_DIR" -mindepth 1 -type f -print0 | sort -z)

    if [ ${#entries[@]} -eq 0 ]; then
        log "No dotfiles to copy" "$grey"
        return 0
    fi

    log "${#entries[@]} dotfile(s) to copy into $HOME" "$blue"
    for entry in "${entries[@]}"; do
        printf "%b    ~/%s%b\n" "$grey" "$entry" "$no_color"
    done

    if ! confirm "Copy these into $HOME? (existing files are backed up)"; then
        log "Skipping dotfiles" "$grey"
        return 0
    fi

    local backup_dir="$HOME/.dotfiles-backup-$(date +%Y%m%dT%H%M%S)"
    local needs_backup="false"
    for entry in "${entries[@]}"; do
        [ -f "$HOME/$entry" ] && needs_backup="true"
    done

    local subdir
    for entry in "${entries[@]}"; do
        # "." for files sitting directly in $HOME, no directory to create
        subdir="$(dirname "$entry")"
        [ "$subdir" = "." ] && subdir=""

        if [ -f "$HOME/$entry" ]; then
            log "Backing up ~/$entry" "$grey"
            [ -n "$subdir" ] && run mkdir -p "$backup_dir/$subdir"
            [ -z "$subdir" ] && run mkdir -p "$backup_dir"
            run cp -a "$HOME/$entry" "$backup_dir/$entry"
        fi
        log "Installing ~/$entry" "$blue"
        [ -n "$subdir" ] && run mkdir -p "$HOME/$subdir"
        run cp -a "$DOTFILES_DIR/$entry" "$HOME/$entry"
    done

    [ "$needs_backup" = true ] && log "Previous dotfiles saved in $backup_dir" "$green"
    return 0
}

copy_dotfiles
