#!/bin/bash
# Shared helpers for the Arch setup scripts.
# This file is meant to be sourced, never executed directly.

[ -n "${_COMMON_LOADED:-}" ] && return 0
_COMMON_LOADED=1

# Colorize terminal
red='\e[0;31m'
green='\e[0;32m'
blue='\e[0;34m'
grey='\e[0;37m'
no_color='\033[0m'

# Runtime switches, overridable by the caller
: "${DRY_RUN:=false}"
: "${ASSUME_YES:=false}"

# Console step increment, shared across every sourced profile
: "${STEP:=1}"

# Packages that could not be installed, reported in the final summary
FAILED_PACKAGES=()

# Log function
# Using an explicit assignment instead of ((STEP++)) which returns 1 when STEP
# is unset or 0, and would abort the script under `set -e`.
log() {
    printf "%b[%s] %s%b\n" "${2:-$no_color}" "$STEP" "$1" "$no_color"
    STEP=$((STEP + 1))
}
# example usage: log "Updating system and installing base dependencies" $blue

# Run a command, or just print it when running in dry-run mode
run() {
    if [ "$DRY_RUN" = true ]; then
        printf "%b    [dry-run] %s%b\n" "$grey" "$*" "$no_color"
    else
        "$@"
    fi
}

# Ask for confirmation unless -y was given. Always true in dry-run mode since
# nothing is actually applied.
confirm() {
    [ "$ASSUME_YES" = true ] && return 0
    [ "$DRY_RUN" = true ] && return 0

    local reply
    printf "%b%s%b [y/N] " "$blue" "$1" "$no_color"
    read -r reply </dev/tty || return 1
    case "$reply" in
        [yY] | [yY][eE][sS]) return 0 ;;
        *) return 1 ;;
    esac
}

# Check whether a package is installed. `pacman -Qq` also resolves virtual
# packages, unlike the plain `pacman -Q` this used to rely on.
pkg_installed() {
    pacman -Qq -- "$1" >/dev/null 2>&1
}

# Install the given whitespace separated package list in a single yay call,
# after listing what is missing and asking for confirmation.
install_packages() {
    local label="$1" packages="$2"
    local missing=() pkg

    for pkg in $packages; do
        if pkg_installed "$pkg"; then
            log "$pkg is already installed" "$green"
        else
            missing+=("$pkg")
        fi
    done

    if [ ${#missing[@]} -eq 0 ]; then
        log "$label: nothing to install" "$green"
        return 0
    fi

    log "$label: ${#missing[@]} package(s) to install" "$blue"
    printf "%b    %s%b\n" "$grey" "${missing[*]}" "$no_color"

    if ! confirm "Install these ${#missing[@]} package(s)?"; then
        log "$label: skipped" "$grey"
        return 0
    fi

    if ! run yay -S --needed --noconfirm "${missing[@]}"; then
        log "$label: installation failed" "$red"
        FAILED_PACKAGES+=("${missing[@]}")
    fi
}

# Locate the root of the toolbox checkout, wherever it happens to be cloned.
# Asking git first means the layout can move without breaking this; the
# relative walk is only a fallback for tarball downloads with no .git.
repo_root() {
    local here="$1" root

    if root="$(git -C "$here" rev-parse --show-toplevel 2>/dev/null)" && [ -n "$root" ]; then
        printf "%s\n" "$root"
        return 0
    fi

    # Walk up looking for a marker instead of hardcoding a depth
    root="$here"
    while [ "$root" != "/" ]; do
        if [ -d "$root/dotfiles" ] && [ -d "$root/shell" ]; then
            printf "%s\n" "$root"
            return 0
        fi
        root="$(dirname "$root")"
    done

    return 1
}

# Install the AUR helper. Lives here so every profile can rely on it.
install_yay() {
    if pkg_installed yay; then
        log "yay is already installed" "$green"
        return 0
    fi

    log "Installing yay" "$blue"
    run sudo pacman -S --needed --noconfirm base-devel git

    local build_dir
    build_dir="$(mktemp -d)"
    run git clone --depth 1 https://aur.archlinux.org/yay.git "$build_dir/yay"

    if [ "$DRY_RUN" = true ]; then
        printf "%b    [dry-run] makepkg -si --noconfirm (in %s)%b\n" "$grey" "$build_dir/yay" "$no_color"
    else
        (cd "$build_dir/yay" && makepkg -si --noconfirm)
    fi

    rm -rf "$build_dir"
}
