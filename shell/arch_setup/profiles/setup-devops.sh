#!/bin/bash
# Devops profile: cloud, container and infrastructure tooling.

source "$(dirname "${BASH_SOURCE[0]}")/_common.sh"

# Devops packages
# Note: the kubectx package also ships kubens, there is no separate package.
DEVOPS_PACKAGES="act \
  ansible \
  argocd \
  aws-cli-v2 \
  dive \
  github-cli \
  glab \
  hadolint \
  helm \
  insomnia \
  k9s \
  kind \
  kubecolor \
  kubectl \
  kubectx \
  kubeseal \
  kustomize \
  minio-client \
  openbao \
  opentofu \
  skopeo \
  sops \
  stern \
  terraform \
  tflint \
  trivy \
  vault"

SCW_INSTALLER="https://raw.githubusercontent.com/scaleway/scaleway-cli/master/scripts/get.sh"

# The scaleway-cli package lags several releases behind upstream, so use the
# official installer instead. It drops the binary in /usr/local/bin/scw using
# sudo, outside of pacman's control.
install_scw() {
    local current="" prompt="Install the Scaleway CLI by piping $SCW_INSTALLER to sh?"

    if command -v scw >/dev/null 2>&1; then
        current="$(scw version -o json 2>/dev/null | sed -n 's/.*"version"[^"]*"\([^"]*\)".*/\1/p')"
        [ -z "$current" ] && current="unknown"
        log "scw is already installed (version $current)" "$green"
        # The installer always fetches the latest release, so re-running it is
        # the update path. Ask rather than silently keeping an old binary.
        prompt="Re-run the Scaleway installer to update scw from $current to the latest?"
    fi

    if ! confirm "$prompt"; then
        log "Skipping scw" "$grey"
        return 0
    fi

    log "Installing scw from the official installer" "$blue"
    if [ "$DRY_RUN" = true ]; then
        printf "%b    [dry-run] curl -s %s | sh%b\n" "$grey" "$SCW_INSTALLER" "$no_color"
    elif ! curl -sSf "$SCW_INSTALLER" | sh; then
        log "scw installation failed" "$red"
        FAILED_PACKAGES+=("scw")
    fi
}

setup_devops() {
    install_yay
    install_packages "devops" "$DEVOPS_PACKAGES"
    install_scw
}

setup_devops
