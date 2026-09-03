#!/bin/bash
# JS profile: node version manager and the package managers driven by corepack.

source "$(dirname "${BASH_SOURCE[0]}")/_common.sh"

# JS dev packages
JS_PACKAGES="fnm"
NODE_PACKAGES="pnpm"

enable_node_packages() {
    if ! command -v corepack >/dev/null 2>&1; then
        log "corepack not found, skipping node packages (install node first)" "$red"
        return 0
    fi

    local pkg
    for pkg in $NODE_PACKAGES; do
        log "Enabling node package: $pkg" "$blue"
        run corepack enable "$pkg"
    done
}

setup_js() {
    install_yay
    install_packages "js" "$JS_PACKAGES"
    enable_node_packages
}

setup_js
