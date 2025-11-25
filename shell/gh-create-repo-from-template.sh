#!/bin/bash

# Colorize terminal
red='\e[0;31m'
no_color='\033[0m'

# Defaults
ORGANISATION="our-organisation"
TEMPLATE_REPO="starter-web"
INCLUDE_ALL_BRANCHES=false

# Declare script helper
TEXT_HELPER="\nThis script creates a new repository from a template and sets up team permissions.

Following flags are available:

  -n  Name of the new repository (required).

  -o  Organisation.
      Default is $ORGANISATION

  -t  Template repository name.
      Default is $TEMPLATE_REPO

  -d  Description for the new repository (optional).

  -h  Print script help.\n\n"

print_help() {
  printf "$TEXT_HELPER"
}

# Parse options
while getopts n:o:t:d:h flag; do
  case "${flag}" in
    n)
      REPO_NAME="${OPTARG}";;
    o)
      ORGANISATION="${OPTARG}";;
    t)
      TEMPLATE_REPO="${OPTARG}";;
    d)
      DESCRIPTION="${OPTARG}";;
    h | *)
      print_help
      exit 0;;
  esac
done

# Check if repo name is provided
if [ -z "$REPO_NAME" ]; then
  printf "${red}Error: Repository name is required (-n flag)${no_color}\n"
  print_help
  exit 1
fi

# Create repository from template
printf "Creating repository $REPO_NAME from template $TEMPLATE_REPO...\n"

if [ -n "$DESCRIPTION" ]; then
  gh repo create "$ORGANISATION/$REPO_NAME" \
    --template "$ORGANISATION/$TEMPLATE_REPO" \
    --public \
    --description "$DESCRIPTION"
else
  gh repo create "$ORGANISATION/$REPO_NAME" \
    --template "$ORGANISATION/$TEMPLATE_REPO" \
    --public
fi

if [ $? -ne 0 ]; then
  printf "${red}Error: Failed to create repository${no_color}\n"
  exit 1
fi

printf "Repository created successfully!\n\n"

# Wait for repository initialization
printf "Waiting for repository initialization...\n"
sleep 5

# Set up team permissions
printf "Setting up team permissions...\n"

# IT - Team : Maintain
printf "  - Setting 'maintain' permission for 'IT - Team'...\n"
gh api --silent orgs/$ORGANISATION/teams/it-team/repos/$ORGANISATION/$REPO_NAME \
  -X PUT -F permission="maintain"

# Chef de projet : Triage
printf "  - Setting 'triage' permission for 'Chef de projet'...\n"
gh api --silent orgs/$ORGANISATION/teams/chef-de-projet/repos/$ORGANISATION/$REPO_NAME \
  -X PUT -F permission="triage"

# Artists : Read
printf "  - Setting 'pull' permission for 'Artists'...\n"
gh api --silent orgs/$ORGANISATION/teams/artists/repos/$ORGANISATION/$REPO_NAME \
  -X PUT -F permission="pull"

printf "Permissions set successfully!\n\n"

# Configure repository settings
printf "Configuring repository settings...\n"

# Enable squash merge and rebase, disable regular merge
printf "  - Configuring merge strategies (squash & rebase only)...\n"
gh api repos/$ORGANISATION/$REPO_NAME -X PATCH \
  --silent \
  -F allow_squash_merge=true \
  -F allow_merge_commit=false \
  -F allow_rebase_merge=true \
  -F delete_branch_on_merge=true

# Protect main branch (wait for it to exist)
printf "  - Protecting main branch (PR required)...\n"
RETRIES=0
MAX_RETRIES=6
while [ $RETRIES -lt $MAX_RETRIES ]; do
  if gh api repos/$ORGANISATION/$REPO_NAME/branches/main/protection -X PUT \
    --silent \
    -F required_status_checks=null \
    -F enforce_admins=false \
    -F required_pull_request_reviews[required_approving_review_count]=1 \
    -F required_pull_request_reviews[dismiss_stale_reviews]=true \
    -F required_pull_request_reviews[require_code_owner_reviews]=false \
    -F required_pull_request_reviews[require_last_push_approval]=false \
    -F restrictions=null \
    -F required_linear_history=false \
    -F allow_force_pushes=false \
    -F allow_deletions=false \
    -F required_conversation_resolution=false 2>/dev/null; then
    break
  fi
  RETRIES=$((RETRIES+1))
  if [ $RETRIES -lt $MAX_RETRIES ]; then
    printf "    Branch not ready, waiting...\n"
    sleep 5
  else
    printf "    ${red}Warning: Could not protect main branch after $MAX_RETRIES attempts${no_color}\n"
  fi
done

printf "\n"

# Trigger init-project workflow
printf "Triggering init-project workflow...\n"
gh workflow run init-project.yml --repo $ORGANISATION/$REPO_NAME

printf "\n${no_color}All done! Repository $REPO_NAME created, configured and permissions set.\n"
