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

# Devops packages
DEVOPS_PACKAGES="act \
  argocd \
  ansible \
  aws-cli-v2 \
  github-cli \
  glab \
  hadolint \
  helm \
  insomnia \
  k9s \
  kind \
  kubectl \
  minio-client \
  open-tofu \
  scw \
  terraform \
  trivy \
  vault"

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

main() {
    install_yay
    install_packages "$DEVOPS_PACKAGES"
}

main