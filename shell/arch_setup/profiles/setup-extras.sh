#!/bin/bash
# Extras profile: personal applications, plus the optional Steam setup.

source "$(dirname "${BASH_SOURCE[0]}")/_common.sh"

# Extra packages, more personal stuff
EXTRA_PACKAGES="beeper \
  discord \
  nicotine+ \
  obs-studio \
  obsidian \
  picard \
  vlc"

# Function to install and configure Steam
install_steam() {
    if ! confirm "Install and configure Steam? (enables the multilib repository)"; then
        log "Skipping Steam" "$grey"
        return 0
    fi

    log "Enabling multilib repository" "$blue"
    run sudo sed -i '/\[multilib\]/,/Include/ s/^#//' /etc/pacman.conf
    run sudo pacman -Sy

    log "Installing Steam and its 32-bit dependencies" "$blue"
    run sudo pacman -S --needed --noconfirm \
        steam \
        lib32-vulkan-icd-loader \
        lib32-mesa \
        xdg-desktop-portal \
        xdg-desktop-portal-gtk \
        ttf-liberation

    log "Generating the en_US.UTF-8 locale" "$blue"
    run sudo sed -i 's/^#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
    run sudo locale-gen

    # Some games need a higher mmap limit. Keep it in its own file so re-runs
    # overwrite instead of appending the same line over and over.
    log "Raising vm.max_map_count" "$blue"
    if [ "$DRY_RUN" = true ]; then
        printf "%b    [dry-run] write vm.max_map_count=262144 to /etc/sysctl.d/99-max-map-count.conf%b\n" "$grey" "$no_color"
    else
        echo 'vm.max_map_count=262144' | sudo tee /etc/sysctl.d/99-max-map-count.conf >/dev/null
        sudo sysctl -p /etc/sysctl.d/99-max-map-count.conf
    fi

    log "Steam is installed, a reboot is recommended" "$green"
}

setup_extras() {
    install_yay
    install_packages "extras" "$EXTRA_PACKAGES"
    install_steam
}

setup_extras
