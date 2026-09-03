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
alias kkk="k9s"
alias kubectl=kubecolor
alias kns=kubens
alias kcx=kubectx

# cdp is a function who change directory to ~/Projects/Work/$1 
cdps () {
	cd "$HOME/Projects/Work/starter-new"
}

cdp () {
	cd "$HOME/Projects/Work/$1"
}

cdpp () {
	cd "$HOME/Projects/Perso/$1"
}

_cdp_autocomplete() {
    local cur
    cur="${COMP_WORDS[COMP_CWORD]}"
    COMPREPLY=( $(compgen -W "$(ls -d $HOME/Projects/Work/*/ 2>/dev/null | xargs -n 1 basename)" -- "$cur") )
}

complete -F _cdp_autocomplete cdp

_cdpp_autocomplete() {
    local cur
    cur="${COMP_WORDS[COMP_CWORD]}"
    COMPREPLY=( $(compgen -W "$(ls -d $HOME/Projects/Perso/*/ 2>/dev/null | xargs -n 1 basename)" -- "$cur") )
}

complete -F _cdpp_autocomplete cdpp

# Fonction pour décoder un secret Kubernetes
dks() {
  local secret="$1"
  local namespace="$2"

  if [[ -z "$secret" ]]; then
    echo "Usage: dks <secret-name> [namespace]" >&2
    return 1
  fi

  local ns_arg=()
  [[ -n "$namespace" ]] && ns_arg=(-n "$namespace")

  kubectl get secret "$secret" "${ns_arg[@]}" -o json \
    | jq -r '.data | to_entries[] | "\(.key): \(.value | @base64d)"'
}

# Autocomplétion pour dks
_dks() {
  local arg_position=$((CURRENT - 1))

  case $arg_position in
    1)
      local secrets
      if [[ -n "${words[3]}" ]]; then
        # Namespace déjà tapé, filtrer par celui-ci
        secrets=($(kubectl -n "${words[3]}" get secrets --no-headers \
          -o custom-columns=":metadata.name" 2>/dev/null))
      else
        # Pas encore de namespace, lister depuis tous les namespaces
        secrets=($(kubectl get secrets --all-namespaces --no-headers \
          -o custom-columns=":metadata.name" 2>/dev/null))
      fi
      _describe 'secrets' secrets
      ;;
    2)
      local namespaces
      namespaces=($(kubectl get namespaces --no-headers \
        -o custom-columns=":metadata.name" 2>/dev/null))
      _describe 'namespaces' namespaces
      ;;
  esac
}

compdef _dks dks

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

# Kubeconfig
# export KUBECONFIG="$HOME/.kube/config:$HOME/.kube/kubeconfig-dev-cluster.yaml"
#export KUBECONFIG="$HOME/.kube/mysg/dev-cluster.yaml:$HOME/.kube/mysg/prod-cluster.yaml"
export KUBECONFIG="$HOME/.kube/config"

## [Completion]
## Completion scripts setup. Remove the following line to uninstall
[[ -f /home/florian/.dart-cli-completion/zsh-config.zsh ]] && . /home/florian/.dart-cli-completion/zsh-config.zsh || true

# kubecolor completion
compdef kubecolor=kubectl

# add Krew to PATH
export PATH="${KREW_ROOT:-$HOME/.krew}/bin:$PATH"

# Weather function
weather() {
	case "$1" in
	-h | --help)
		printf "Description:\n"
		printf "  Get the weather for a given location.\n\n"
		printf "Usage:\n"
		printf "  weather <location>   get the weather.\n"
		;;
	*)
		curl "wttr.in/$1"
		;;
	esac
}

# Zoxide
eval "$(zoxide init zsh)"
fpath=(~/.zsh/completions $fpath)
autoload -U compinit && compinit

# opencode
export PATH=/home/florian/.opencode/bin:$PATH

# Added by LM Studio CLI (lms)
export PATH="$PATH:/home/florian/.lmstudio/bin"
# End of LM Studio CLI section

# Disable RTK telemetry
export RTK_TELEMETRY_DISABLED=1
