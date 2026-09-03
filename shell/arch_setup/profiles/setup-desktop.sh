#!/bin/bash
# Desktop profile: GUI applications and everything that only makes sense on a
# workstation. Split out of 'base' so a headless install stays lean.

source "$(dirname "${BASH_SOURCE[0]}")/_common.sh"

# Desktop packages
DESKTOP_PACKAGES="audacity \
  keepassxc \
  kitty \
  rdesktop"

setup_desktop() {
    install_yay
    install_packages "desktop" "$DESKTOP_PACKAGES"
}

setup_desktop
