#!/bin/bash

# Colorize terminal
red='\e[0;31m'
no_color='\033[0m'


# Defaults
PERMISSION="pull"

# Declare script helper
TEXT_HELPER="\nThis script aims to list all repository's node version for an Org.

Following flags are available:

  -o  Organisation.

  -h  Print script help.\n\n"

print_help() {
  printf "$TEXT_HELPER"
}

# Parse options
while getopts o:h flag; do
  case "${flag}" in
    o)
      ORGANISATION="${OPTARG}";;
    h | *)
      print_help
      exit 0;;
  esac
done

for repo in $(gh repo list $ORGANISATION --limit 1000 --json name -q ".[].name"); do
    gh api -H "Accept: application/vnd.github.raw" -H "X-GitHub-Api-Version: 2022-11-28" /repos/$ORGANISATION/$repo/contents/.nvmrc > reposversion 2> error.log
        if [ -s error.log ]; then
            echo "$repo do not have a .nvmrc file"
        else
            echo "$repo node version: $(cat reposversion)"
            echo "$repo node version: $(cat reposversion)" >> listofreposversion
        fi
done
