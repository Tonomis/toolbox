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

# Extra packages, more personal stuff
EXTRA_PACKAGES="beeper \
    discord \
    obs-studio \
    obsidian \
    picard \
    nicotine+ \
    vlc"

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

# Function to install and configure Steam
install_steam() {
    log "Installing and configuring Steam" $blue
        # Enable multilib repository
        log "Enabling multilib repository" $blue
        sudo sed -i '/\[multilib\]/,/Include/ s/^#//' /etc/pacman.conf
        sudo pacman -Sy

        # Install Steam
        sudo pacman -S --needed steam

        # Install appropriate 32-bit Vulkan driver
        sudo pacman -S --needed lib32-vulkan-icd-loader

        # Install 32-bit OpenGL graphics driver
        sudo pacman -S --needed lib32-mesa

        # Generate en_US.UTF-8 locale
        sudo sed -i 's/^#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
        sudo locale-gen

        # Install XDG Desktop Portal and a backend
        sudo pacman -S --needed xdg-desktop-portal xdg-desktop-portal-gtk

        # Install a free alternative to the Arial font
        sudo pacman -S --needed ttf-liberation

        # Increase vm.max_map_count for some games
        echo 'vm.max_map_count=262144' | sudo tee -a /etc/sysctl.d/99-sysctl.conf
        sudo sysctl -p /etc/sysctl.d/99-sysctl.conf

        log "Steam installation and configuration completed. Please restart your system." $green
}

main() {
    install_packages "$EXTRA_PACKAGES"
}

main