#!/bin/bash
# System customization: KDE theme, scroll direction, fonts, Num Lock.

source "$(dirname "${BASH_SOURCE[0]}")/_common.sh"

# Customization packages
CUSTOMIZATION_PACKAGES=""

customize_system() {
    if [ -n "${CUSTOMIZATION_PACKAGES// /}" ]; then
        install_yay
        install_packages "customization" "$CUSTOMIZATION_PACKAGES"
    fi

    # TODO: KDE theme, scroll direction, fonts and Num Lock are advertised in
    # the help text but not implemented yet.
    log "No customization step implemented yet" "$grey"
}

customize_system
