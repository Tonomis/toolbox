#!/bin/bash

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

# JS dev packages
JS_PACKAGES=""
NODES_PACKAGES="pnpm"

# Function to check and install packages
install_packages() {
    for pkg in $1; do
        if ! pacman -Q $pkg &>/dev/null; then
            log "Installing $pkg" $blue
            yay -S --needed $pkg --noconfirm
        else
            log "$pkg is already installed" $green
        fi
    done
}

install_fnm() {
    log "Installing fnm" $blue
    curl -fsSL https://fnm.vercel.app/install | bash
}

corepack_enable() {
    for pkg in $NODES_PACKAGES; do
        log "Install node package : $pkg" $blue
        corepack enable $pkg
    done
}

main() {
    install_packages "$JS_PACKAGES"
    install_fnm
    install_node_packages
}

main