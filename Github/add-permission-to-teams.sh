#!/bin/bash

# Colorize terminal
red='\e[0;31m'
no_color='\033[0m'


# Defaults
PERMISSION="pull"

# Declare script helper
TEXT_HELPER="\nThis script aims to grant permission to a github team in every repository.

Following flags are available:

  -t  Github Team to manage.

  -p  Permission to set (Pull, Triage, Write, Admin).
      Default is $PERMISSION

  -o  Organisation.

  -h  Print script help.\n\n"

print_help() {
  printf "$TEXT_HELPER"
}

# Parse options
while getopts t:p:o:h flag; do
  case "${flag}" in
    t)
      GITHUB_TEAM="${OPTARG}";;
    p)
      PERMISSION="${OPTARG}";;
    o)
      ORGANISATION="${OPTARG}";;
    h | *)
      print_help
      exit 0;;
  esac
done


# list all repo with gh
for repo in $(gh repo list $ORGANISATION --limit 1000 --json name -q ".[].name")
do
  gh api --silent orgs/$ORGANISATION/teams/$GITHUB_TEAM/repos/$ORGANISATION/$repo -X PUT -F permission="$PERMISSION"
done




