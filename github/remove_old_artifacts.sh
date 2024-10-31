#!/bin/bash

# Terminal colors
red='\e[0;31m'
no_color='\033[0m'

# Defaults
DAYS_OLD=7  # Delete artifacts older than X days
REPO=$(gh repo view --json fullName --jq .fullName 2>/dev/null)

# Help text
TEXT_HELPER="\nThis script deletes GitHub Actions artifacts older than a specified number of days.\n
Available flags:

  -d  Days old threshold for deleting artifacts (default: $DAYS_OLD)
  -r  Repository to target (default: current Git repository)
  -h  Print this help message.\n"

print_help() {
  printf "$TEXT_HELPER"
}

# Parse options
while getopts d:r:h flag; do
  case "${flag}" in
    d) DAYS_OLD="${OPTARG}";;
    r) REPO="${OPTARG}";;
    h | *) print_help; exit 0;;
  esac
done

# Check if GitHub CLI is available
if ! command -v gh &> /dev/null; then
    echo -e "${red}Error: GitHub CLI (gh) is not installed or not in the PATH.${no_color}"
    exit 1
fi

# Validate repository name
if [ -z "$REPO" ]; then
    echo -e "${red}Error: Unable to determine the repository. Please specify with -r.${no_color}"
    exit 1
fi

# Fetch all artifacts older than specified days
ARTIFACTS=$(gh run list --repo "$REPO" --limit 100 --json createdAt,databaseId --jq ".[] | select(.createdAt < \"$(date -d "-$DAYS_OLD days" --iso-8601=seconds)\") | .databaseId")

if [ -z "$ARTIFACTS" ]; then
    echo -e "${no_color}No artifacts older than $DAYS_OLD days found."
    exit 0
fi

# Loop to delete each artifact
for ARTIFACT_ID in $ARTIFACTS; do
    echo -e "${no_color}Deleting artifact with ID: $ARTIFACT_ID..."
    gh run delete "$ARTIFACT_ID" --repo "$REPO" --confirm
done

echo -e "${no_color}Deletion of artifacts older than $DAYS_OLD days completed."
