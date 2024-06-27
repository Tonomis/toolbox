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

# Bases packages
BASES_PACKAGES=" atuin \
  audacity \
  age \
  bat \
  cheat \
  cups \
  docker \
  docker-compose \
  docker-buildx \
  firefox \
  fzf \
  jq \
  keepassxc \
  kitty \
  lazydocker \
  ldns \
  less \
  man \
  man-db \
  nmap \
  neofetch \
  rdesktop \
  rsync \
  sshs \
  tree \
  vim \
  visual-studio-code-bin \
  yq \
  wl-clipboard "

# Install aur helper
install_yay() {
    if ! pacman -Q yay &>/dev/null; then
        log "Installing yay" $blue
        mkdir /tmp/yay
        cd /tmp/yay
        curl -OJ 'https://aur.archlinux.org/cgit/aur.git/plain/PKGBUILD?h=yay'
        makepkg -si --noconfirm
        cd
        rm -rf /tmp/yay
    else
        log "yay is already installed" $green
    fi
}

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


# Function to install zsh
install_zsh() {
    log "Installing zsh" $blue
    sudo pacman -S --needed zsh --noconfirm
}

# Set zsh as default shell
set_default_shell() {
    if [ "$SHELL" != "/usr/bin/zsh" ]; then
        log "Setting zsh as the default shell" $blue
            chsh -s /usr/bin/zsh
    else 
        log "zsh is already the default shell" $green
    fi
}

# Enable and start Docker service
configure_docker() {
    log "Enabling and starting Docker service" $blue
    sudo systemctl enable docker
    sudo systemctl start docker
}

# Create Projects directory
create_projects_directory() {
    log "Creating Projects directory" $blue
    if [ ! -d ~/Projects ]; then
        mkdir -p ~/Projects
    else
        log "Projects directory already exists" $green
    fi
    log "Creating MySG directory" $blue
    if [ ! -d ~/Projects/MySG ]; then
        mkdir -p ~/Projects/MySG
    else
        log "MySG directory already exists" $green
    fi
    log "Creating Perso directory" $blue
    if [ ! -d ~/Projects/Perso ]; then
        mkdir -p ~/Projects/Perso
    else
        log "Perso directory already exists" $green
    fi
}

main() {
    install_yay
    install_packages "$BASES_PACKAGES"
    install_zsh
    set_default_shell
    configure_docker
    create_projects_directory
}

main