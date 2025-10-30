# Toolbox 🧰

A collection of usefull (or not) scripts and dotfiles.

## Shell
| Script                                                         | Description                                                    |
| -------------------------------------------------------------- | -------------------------------------------------------------- |
| [setup-arch.sh](shell/arch-setup/setup-arch.sh)                | Set up Arch Linux with essential packages and configurations   |
| [backup-files.sh](shell/backup-files.sh)                       | Backup important files and directories to a specified location |
| [system-check.sh](shell/system-check.sh)                       | Quick Linux system diagnostic (OS agnostic, server or desktop) |
| [gh-init-vars.sh](shell/gh-init-vars.sh)                       | Initialize environment variables for a Github repository       |
| [gh-add-permissions.sh](shell/gh-add-permissions.sh)           | Grant permission to a github team in every repositories.       |
| [gh-delete-old-artifacts.sh](shell/gh-delete-old-artifacts.sh) | Delete artifacts older than X days from a Github repository.   |
| [gh-list-node-versions.sh](shell/gh-list-node-versions.sh)     | List, in a file, all repositories node version's               |
| [gitmoji.sh](shell/gitmoji.sh)                                 | Add gitmoji support to your git commits cli                    |
| [kube-secrets.sh](shell/kube-secrets.sh)                       | Backup, transfer or restore Kubernetes secrets                 |
| [rsync-time-window.sh](shell/rsync-time-window.sh)             | Rsync files within a specific time window                      |

Thanks to [@this-is-tobi](https://github.com/this-is-tobi) for the shell scripts structure inspiration.

## Dotfiles
| Files                                                            | Description             |
| ---------------------------------------------------------------- | ----------------------- |
| [dotfiles/.zshrc](dotfiles/.zshrc)                               | Zsh configuration file. |
| [dotfiles/.gitconfig](dotfiles/.gitconfig)                       | Git configuration file. |
| [dotfiles/.vscode/settings.json](dotfiles/.vscode/settings.json) | VSCode settings file.   |

