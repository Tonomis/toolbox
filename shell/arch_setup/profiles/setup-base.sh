#!/bin/bash
# Base profile: core CLI tooling only. GUI applications live in the
# 'desktop' profile.

source "$(dirname "${BASH_SOURCE[0]}")/_common.sh"

# Base packages
BASE_PACKAGES="age \
  atuin \
  bat \
  cheat \
  docker \
  docker-buildx \
  docker-compose \
  direnv \
  fastfetch \
  fd \
  fzf \
  git \
  git-delta \
  go-yq \
  jq \
  lazydocker \
  lazygit \
  ldns \
  less \
  man-db \
  man-pages \
  nmap \
  ripgrep \
  rsync \
  shellcheck \
  sshs \
  tree \
  vim \
  wl-clipboard \
  yamllint \
  zoxide"

# Function to install zsh
install_zsh() {
    log "Installing zsh" "$blue"
    run sudo pacman -S --needed --noconfirm zsh
}

OMZ_INSTALLER="https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh"

# Install oh-my-zsh, which the shipped .zshrc sources. --keep-zshrc stops the
# installer from replacing an existing .zshrc with its own template, and
# --unattended stops it from running chsh or dropping into a new shell.
install_oh_my_zsh() {
    if [ -d "$HOME/.oh-my-zsh" ]; then
        log "oh-my-zsh is already installed" "$green"
        return 0
    fi

    if ! confirm "Install oh-my-zsh by piping $OMZ_INSTALLER to sh?"; then
        log "Skipping oh-my-zsh" "$grey"
        return 0
    fi

    log "Installing oh-my-zsh" "$blue"
    if [ "$DRY_RUN" = true ]; then
        printf "%b    [dry-run] sh -c \"\$(curl -fsSL %s)\" \"\" --unattended --keep-zshrc%b\n" \
            "$grey" "$OMZ_INSTALLER" "$no_color"
    elif ! sh -c "$(curl -fsSL "$OMZ_INSTALLER")" "" --unattended --keep-zshrc; then
        log "oh-my-zsh installation failed" "$red"
        FAILED_PACKAGES+=("oh-my-zsh")
    fi
}

# Set zsh as default shell
set_default_shell() {
    if [ "$(getent passwd "$USER" | cut -d: -f7)" = "/usr/bin/zsh" ]; then
        log "zsh is already the default shell" "$green"
        return 0
    fi

    # chsh always prompts for a password, so let the user opt out of the
    # interruption in the middle of an otherwise unattended run.
    if confirm "Set zsh as the default shell? (asks for your password)"; then
        log "Setting zsh as the default shell" "$blue"
        run chsh -s /usr/bin/zsh
    else
        log "Keeping the current default shell" "$grey"
    fi
}

# Enable and start Docker service
configure_docker() {
    log "Enabling and starting Docker service" "$blue"
    run sudo systemctl enable --now docker
}

# Directories to scaffold under $HOME, override with
# PROJECT_DIRS="Projects Projects/foo" to use a different layout.
: "${PROJECT_DIRS:=Projects Projects/Work Projects/Perso}"

# Create Projects directories
create_projects_directories() {
    local name dir
    for name in $PROJECT_DIRS; do
        dir="$HOME/$name"
        if [ -d "$dir" ]; then
            log "$dir already exists" "$green"
        else
            log "Creating $dir" "$blue"
            run mkdir -p "$dir"
        fi
    done
}

setup_base() {
    install_yay
    install_packages "base" "$BASE_PACKAGES"
    install_zsh
    install_oh_my_zsh
    set_default_shell
    configure_docker
    create_projects_directories
}

setup_base
