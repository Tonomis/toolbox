#!/bin/bash

set -e

# Colorize terminal
red='\e[0;31m'
green='\e[0;32m'
blue='\e[0;34m'
grey='\e[0;37m'
no_color='\033[0m'

# Log function
log() {
    echo -e "${2}[$i] $1${no_color}"
    ((i++))
}
# example usage: log "Updating system and installing base dependencies" $blue

# Console step increment
i=1

# Get project directories
SCRIPT_PATH="$( cd -- "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )"

# Default
COPY_DOTFILES="false"
INSTALL_BASE="false"
INSTALL_DEVOPS="false"
INSTALL_JS="false"
INSTALL_EXTRAS="false"
INSTALL_COMPLETIONS="false"
CUSTOMIZE_SYSTEM="false"

# Declare script helper
TEXT_HELPER="\nThis script aims to install a full setup for Arch Linux.
Following flags are available:
  -b,   Import browser bookmarks.

  -c    Install CLI completions.

  -f    Copy dotfiles.

  -p    Install additional packages according to the given profile, available profiles are :
        -> 'base'
        -> 'devops'
        -> 'extras'
        -> 'js'
      Default is no profile, this flag can be used with a CSV list (ex: -p "base,js").

  -z,   Customize the system (KDE theme, scroll direction, fonts, Num Lock).

  -h,   Print script help.\n\n"

print_help() {
  printf "$TEXT_HELPER"
}

# Parse options
while getopts hbcfzp: flag; do
  case "${flag}" in
    b)
      IMPORT_BOOKMARKS="true";;
    z)
      CUSTOMIZE_SYSTEM="true";;
    f)
      COPY_DOTFILES="true";;
    c)
      INSTALL_COMPLETIONS="true";;
    p)
      [[ "$OPTARG" =~ "base" ]] && INSTALL_BASE="true"
      [[ "$OPTARG" =~ "devops" ]] && INSTALL_DEVOPS="true"
      [[ "$OPTARG" =~ "js" ]] && INSTALL_JS="true"
      [[ "$OPTARG" =~ "extras" ]] && INSTALL_EXTRAS="true";;
    h | *)
      print_help
      exit 0;;
  esac
done

# Settings
printf "\nScript settings:
  -> install base: ${red}$INSTALL_BASE${no_color}
  -> install devops: ${red}$INSTALL_DEVOPS${no_color}
  -> install js: ${red}$INSTALL_JS${no_color}
  -> install extras: ${red}$INSTALL_EXTRAS${no_color}
  -> import bookmarks: ${red}$IMPORT_BOOKMARKS${no_color}
  -> customize system: ${red}$CUSTOMIZE_SYSTEM${no_color}\n"

# Function to update the system and install basic dependencies
update_system() {
    log "Updating system and installing base dependencies"
    sudo pacman -Syu --noconfirm
    sudo pacman -S --needed base-devel git --noconfirm
}

install_common_packages() {
    log "Installing common packages" $blue
    sudo pacman -S --needed \
        git \
        curl \
        sed \
        --noconfirm
}

create_directories() {
    log "Creating Project directories" $blue
    mkdir -p ~/Projects
    mkdir -p ~/Projects/MySG
    mkdir -p ~/Projects/Perso
}

# Function to check and install packages
install_packages() {
    for pkg in $1; do
        if ! pacman -Q $pkg &>/dev/null; then
            log "Installing $pkg" $red
            yay -S --needed $pkg --noconfirm
        else
            log "$pkg is already installed" $green
        fi
    done
}

# Main function to orchestrate the installation
main() {
    update_system
    install_common_packages

    # Install packages according to the given profile
    if [ "$INSTALL_BASE" = true ]; then
        log "Installing base packages" $red
        i=$(($i+1))

        sh "$SCRIPT_PATH/profiles/setup-base.sh"
    fi

    if [ "$INSTALL_DEVOPS" = true ]; then
        log "Installing devops packages" $red
        i=$(($i+1))

        sh "$SCRIPT_PATH/profiles/setup-devops.sh"
    fi

    if [ "$INSTALL_COMPLETIONS" = true ]; then
        log "Installing completions" $red
        i=$(($i+1))

        sh "$SCRIPT_PATH/profiles/setup-completions.sh"
    fi

    if [ "$INSTALL_JS" = true ]; then
        log "Installing JS packages" $red
        i=$(($i+1))

        sh "$SCRIPT_PATH/profiles/setup-js.sh"
    fi

    if [ "$INSTALL_EXTRAS" = true ]; then
        log "Installing extras packages" $red
        i=$(($i+1))

        sh "$SCRIPT_PATH/profiles/setup-extras.sh"
    fi

    if [ "$IMPORT_BOOKMARKS" = true ]; then
        log "Importing bookmarks" $red
        i=$(($i+1))

        sh "$SCRIPT_PATH/profiles/import-bookmarks.sh"
    fi

    if [ "$CUSTOMIZE_SYSTEM" = true ]; then
        log "Customizing the system" $red
        i=$(($i+1))

        sh "$SCRIPT_PATH/profiles/customize-system.sh"
    fi
}

main
