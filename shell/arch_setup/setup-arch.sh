#!/bin/bash

set -e

# Get project directories
SCRIPT_PATH="$(cd -- "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P)"
PROFILES_DIR="$SCRIPT_PATH/profiles"

source "$PROFILES_DIR/_common.sh"

# Known profiles, in the order they are applied
AVAILABLE_PROFILES="base desktop devops js extras"

# Default
ASSUME_YES="false"
DRY_RUN="false"
COPY_DOTFILES="false"
INSTALL_COMPLETIONS="false"
CUSTOMIZE_SYSTEM="false"
UPGRADE_SYSTEM="false"
SELECTED_PROFILES=()

# Declare script helper
TEXT_HELPER="\nThis script aims to install a full setup for Arch Linux.
Following flags are available:
  -c    Install CLI completions.

  -f    Copy dotfiles into \$HOME (existing files are backed up).

  -n    Dry run, print what would be done without changing anything.

  -p    Install additional packages according to the given profile, available profiles are :
        -> 'base'     core CLI tooling
        -> 'desktop'  GUI applications
        -> 'devops'   cloud and infrastructure tooling
        -> 'js'       node toolchain
        -> 'extras'   personal applications
        Default is no profile, this flag accepts a CSV list (ex: -p \"base,js\").

  -u    Upgrade the whole system (pacman -Syu) before installing anything.

  -y    Assume yes, do not ask for confirmation before installing.

  -z    Customize the system (KDE theme, scroll direction, fonts, Num Lock).

  -h    Print script help.\n\n"

print_help() {
    printf "%b" "$TEXT_HELPER"
}

# Translate long options into their short equivalent before getopts
ARGS=()
for arg in "$@"; do
    case "$arg" in
        --dry-run) ARGS+=("-n") ;;
        --yes) ARGS+=("-y") ;;
        --upgrade) ARGS+=("-u") ;;
        --help) ARGS+=("-h") ;;
        *) ARGS+=("$arg") ;;
    esac
done
set -- "${ARGS[@]}"

# Parse options
while getopts hcfnuyzp: flag; do
    case "${flag}" in
        c) INSTALL_COMPLETIONS="true" ;;
        f) COPY_DOTFILES="true" ;;
        n) DRY_RUN="true" ;;
        u) UPGRADE_SYSTEM="true" ;;
        y) ASSUME_YES="true" ;;
        z) CUSTOMIZE_SYSTEM="true" ;;
        p)
            # Anchored match: an unknown or misspelled profile is an error
            # instead of being silently ignored.
            IFS=',' read -r -a requested <<<"$OPTARG"
            for profile in "${requested[@]}"; do
                profile="$(echo "$profile" | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]')"
                [ -z "$profile" ] && continue
                case " $AVAILABLE_PROFILES " in
                    *" $profile "*) SELECTED_PROFILES+=("$profile") ;;
                    *)
                        printf "%bUnknown profile: '%s'%b\n" "$red" "$profile" "$no_color" >&2
                        printf "Available profiles: %s\n" "$AVAILABLE_PROFILES" >&2
                        exit 1
                        ;;
                esac
            done
            ;;
        h | *)
            print_help
            exit 0
            ;;
    esac
done

selected() {
    local profile
    for profile in ${SELECTED_PROFILES[@]+"${SELECTED_PROFILES[@]}"}; do
        [ "$profile" = "$1" ] && return 0
    done
    return 1
}

# Settings
printf "\nScript settings:
  -> profiles: ${red}%s${no_color}
  -> upgrade system: ${red}%s${no_color}
  -> copy dotfiles: ${red}%s${no_color}
  -> install completions: ${red}%s${no_color}
  -> customize system: ${red}%s${no_color}
  -> dry run: ${red}%s${no_color}
  -> assume yes: ${red}%s${no_color}\n\n" \
    "${SELECTED_PROFILES[*]:-none}" "$UPGRADE_SYSTEM" "$COPY_DOTFILES" \
    "$INSTALL_COMPLETIONS" "$CUSTOMIZE_SYSTEM" \
    "$DRY_RUN" "$ASSUME_YES"

if ! confirm "Proceed with these settings?"; then
    printf "Aborted.\n"
    exit 0
fi

# Run a profile script in the current shell so it shares the step counter and
# the helpers from _common.sh.
run_profile() {
    local script="$PROFILES_DIR/$1.sh"
    if [ ! -f "$script" ]; then
        log "profile script not found: $script (skipped)" "$red"
        return 0
    fi
    # shellcheck source=/dev/null
    source "$script"
}

# Function to update the system
upgrade_system() {
    log "Upgrading the system" "$blue"
    run sudo pacman -Syu --noconfirm
}

install_common_packages() {
    log "Installing common packages" "$blue"
    run sudo pacman -S --needed --noconfirm git curl
}

# Main function to orchestrate the installation
main() {
    [ "$UPGRADE_SYSTEM" = true ] && upgrade_system
    install_common_packages

    # Install packages according to the given profiles, in a stable order
    local profile
    for profile in $AVAILABLE_PROFILES; do
        if selected "$profile"; then
            log "Running the $profile profile" "$red"
            run_profile "setup-$profile"
        fi
    done

    if [ "$COPY_DOTFILES" = true ]; then
        log "Copying dotfiles" "$red"
        run_profile "copy-dotfiles"
    fi

    if [ "$INSTALL_COMPLETIONS" = true ]; then
        log "Installing completions" "$red"
        # This one is a zsh script, it cannot be sourced from bash.
        if command -v zsh >/dev/null 2>&1; then
            DRY_RUN="$DRY_RUN" zsh "$PROFILES_DIR/setup-completions.sh"
        else
            log "zsh not found, skipping completions" "$red"
        fi
    fi

    if [ "$CUSTOMIZE_SYSTEM" = true ]; then
        log "Customizing the system" "$red"
        run_profile "customize"
    fi

    if [ ${#FAILED_PACKAGES[@]} -gt 0 ]; then
        printf "\n%bSome packages could not be installed:%b\n  %s\n" \
            "$red" "$no_color" "${FAILED_PACKAGES[*]}"
        exit 1
    fi

    printf "\n%bDone.%b\n" "$green" "$no_color"
}

main
