#!/bin/bash

# Terminal colors
red='\e[0;31m'
no_color='\033[0m'

# Defaults, resolved next to this script so the checkout can live anywhere
SCRIPT_DIR="$(cd -- "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P)"
SECRETS_FILE="$SCRIPT_DIR/secrets.env"
VARIABLES_FILE="$SCRIPT_DIR/variables.env"
ENVIRONMENTS="live staging develop"

# Check if GitHub CLI is available
if ! command -v gh &> /dev/null; then
    echo -e "${red}Error: GitHub CLI (gh) is not installed or not in the PATH.${no_color}"
    exit 1
fi

# Default initialization of repository name and organization using `gh`
REPOSITORY=$(gh repo view --json name --jq .name 2>/dev/null)
ORGANISATION=$(gh repo view --json owner --jq .owner.login 2>/dev/null)

# Script help text
TEXT_HELPER="\nThis script initializes a new GitHub repository by providing default variables & secrets in live, staging & develop environments. You'll need to provide two files to populate variables & secrets.

Available flags:

  -s  Secrets file (default: $SECRETS_FILE)

  -v  Variables file (default: $VARIABLES_FILE)

  -r  Repository to initialize (default: current Git repository)

  -g  Global variables file (optional)

  -o  Organization (default: current Git repository's organization)

  -e  Environments (default: live staging develop)

  -h  Print this help message.\n"

print_help() {
  printf "%b" "$TEXT_HELPER"
}

# Parse options
while getopts s:v:o:r:g:e:h flag; do
  case "${flag}" in
    s) SECRETS_FILE="${OPTARG}";;
    v) VARIABLES_FILE="${OPTARG}";;
    o) ORGANISATION="${OPTARG}";;
    g) GLOBAL_VARIABLES_FILE="${OPTARG}";;
    r) REPOSITORY="${OPTARG}";;
    e) ENVIRONMENTS="${OPTARG}";;
    h | *) print_help; exit 0;;
  esac
done

# Validate repository and organization names
if [ -z "$REPOSITORY" ]; then
    echo -e "${red}Error: Unable to determine the repository. Please specify with -r.${no_color}"
    exit 1
fi

if [ -z "$ORGANISATION" ]; then
    echo -e "${red}Error: Unable to determine the organization. Please specify with -o.${no_color}"
    exit 1
fi

# The .env files are gitignored, so a fresh clone only ships the .example
# ones. Fail with a useful message instead of letting gh error out.
for file in "$VARIABLES_FILE" "$SECRETS_FILE"; do
    if [ ! -f "$file" ]; then
        echo -e "${red}Error: file not found: $file${no_color}"
        echo -e "Copy the matching .example file, or pass -s / -v."
        exit 1
    fi
done

# Set variables and secrets for each environment
for env in $ENVIRONMENTS; do
    echo -e "${no_color}Setting variables and secrets for environment: $env"
    gh variable set --repo "${ORGANISATION}/${REPOSITORY}" --env "$env" --env-file "$VARIABLES_FILE"
    gh secret set --repo "${ORGANISATION}/${REPOSITORY}" --env "$env" --env-file "$SECRETS_FILE"
done

# Set global variables if provided
if [ -n "$GLOBAL_VARIABLES_FILE" ]; then
    echo -e "${no_color}Setting global variables for repository: $REPOSITORY"
    gh variable set --repo "${ORGANISATION}/${REPOSITORY}" --env global --env-file "$GLOBAL_VARIABLES_FILE"
fi
