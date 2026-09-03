#!/bin/zsh
# Install zsh completions for the tools that ship one.
# Run with zsh, not sh: this file relies on the user's .zshrc.

red='\e[0;31m'
grey='\e[0;37m'
no_color='\033[0m'

# COMPLETION_DIR is normally exported by .zshrc. Read the value instead of
# sourcing the whole interactive config, which would fire the oh-my-zsh hooks
# and spray terminal escapes over the output. Falls back to the oh-my-zsh
# location so this also works before the dotfiles are installed.
if [ -z "$COMPLETION_DIR" ] && [ -f "$HOME/.zshrc" ]; then
  COMPLETION_DIR="$(sed -n 's/^[[:space:]]*export[[:space:]]\+COMPLETION_DIR=//p' "$HOME/.zshrc" | tail -1)"
  COMPLETION_DIR="${COMPLETION_DIR//\"/}"
  COMPLETION_DIR="${COMPLETION_DIR/\$HOME/$HOME}"
fi
: "${COMPLETION_DIR:=$HOME/.oh-my-zsh/completions}"

DRY_RUN="${DRY_RUN:-false}"

run() {
  if [ "$DRY_RUN" = true ]; then
    printf "%b    [dry-run] %s%b\n" "$grey" "$*" "$no_color"
  else
    "$@"
  fi
}

step() {
  printf "\n${red}[completion] =>${no_color} %s\n" "$1"
}

step "Using completion directory $COMPLETION_DIR"
run mkdir -p "$COMPLETION_DIR"

# kubectl
if command -v kubectl >/dev/null 2>&1; then
  step "Install kubectl completion"
  if [ "$DRY_RUN" = true ]; then
    printf "%b    [dry-run] kubectl completion zsh > %s/_kubectl%b\n" "$grey" "$COMPLETION_DIR" "$no_color"
  else
    kubectl completion zsh > "$COMPLETION_DIR/_kubectl"
  fi
fi

# vault
if command -v vault >/dev/null 2>&1; then
  step "Install vault completion"
  run vault -autocomplete-install
fi

# terraform
if command -v terraform >/dev/null 2>&1; then
  step "Install terraform completion"
  run terraform -install-autocomplete
fi

# minio client
if command -v mc >/dev/null 2>&1; then
  step "Install minio completion"
  run mc --autocompletion
fi

# scaleway
if command -v scw >/dev/null 2>&1; then
  step "Install scw completion"
  run scw autocomplete install
fi

# cheat
if command -v cheat >/dev/null 2>&1; then
  step "Install cheat completion"
  run curl -sSL -o "$COMPLETION_DIR/_cheat" \
    https://raw.githubusercontent.com/cheat/cheat/master/scripts/cheat.zsh
fi
