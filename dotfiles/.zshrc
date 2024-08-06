export ZSH="$HOME/.oh-my-zsh"

ZSH_THEME="robbyrussell"

plugins=(
  aliases
  ansible
  colored-man-pages
  docker
  docker-compose
  gh
  git
  gitignore
  helm
  kind
  kubectl
  nmap
  node
  rsync
  scw
  sudo
  systemadmin
  terraform
)

source $ZSH/oh-my-zsh.sh

export EDITOR='vim'

# completion
export COMPLETION_DIR=$HOME/.oh-my-zsh/completions

# Do not track 
export DO_NOT_TRACK=1

# Aliases
alias cpc="wl-copy"
alias cat=bat
alias f="fzf --preview 'bat --color=always {}' --preview-window='right:60%:nohidden'"
alias pau="sudo pacman -Suy"

# cdp is a function who change directory to ~/Projects/MySG/$1 
cdps () {
	cd "$HOME/Projects/MySG/starter-new"
}

cdp () {
	cd "$HOME/Projects/MySG/$1"
}

# Crée un dossier et rentre dedans avec cd
mcd () {
	mkdir -p -- "$1" && cd -P -- "$1" || exit
}

cdl () {
	cd "$1" && ls
}

# Fnm : Node version manager
FNM_PATH="$HOME/.local/share/fnm"
if [ -d "$FNM_PATH" ]; then
  export PATH="$HOME/.local/share/fnm:$PATH"
  eval "`fnm env`"
fi

# Utility functions
cheat_bat () {
  cheat "$@" | bat --language=md
}

# cheat
export CHEAT_USE_FZF=true

# pnpm
export PNPM_HOME="$HOME/.local/share/pnpm"
case ":$PATH:" in
  *":$PNPM_HOME:"*) ;;
  *) export PATH="$PNPM_HOME:$PATH" ;;
esac

# atuin
eval "$(atuin init zsh --disable-up-arrow)"

autoload -U +X bashcompinit && bashcompinit
complete -o nospace -C /usr/bin/vault vault
complete -o nospace -C /usr/bin/terraform terraform

# Scaleway CLI autocomplete initialization.
eval "$(scw autocomplete script shell=zsh)"

# exegol with pipx
export PATH="$PATH:$HOME/.local/bin"
alias exegol='sudo -E $HOME/.local/bin/exegol'
eval "$(register-python-argcomplete --no-defaults exegol)"
