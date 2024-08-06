#/bin/bash

# Colorize terminal
red='\e[0;31m'
no_color='\033[0m'


# Defaults
SECRETS_FILE="secrets.env"
VARIABLES_FILE="variables.env"
REPOSITORY="test"
ENVIRONMENTS="live staging develop"

# Declare script helper
TEXT_HELPER="\nThis script aims to a new github repository by providing default variables & secrets in live, staging & develop environments. You'll need to provide two files to populate either variables & secrets.

Following flags are available:

  -s  Secrets file
      Default is $SECRETS_FILE

  -v  Variables file
      Default is $VARIABLES_FILE

  -r  Repo to init

  -g  Global variables file
      no global variables will be set if this flag is not provided

  -o  Organisation

  -e Environments
      Default is live staging develop


  -h  Print script help.\n\n"

print_help() {
  printf "$TEXT_HELPER"
}

# Parse options
while getopts s:v:o:r:g:e:h flag; do
  case "${flag}" in
    s)
      SECRETS_FILE="${OPTARG}";;
    v)
      VARIABLES_FILE="${OPTARG}";;
    o)
      ORGANISATION="${OPTARG}";;
    g)
      GLOBAL_VARIABLES_FILE="${OPTARG}";;
    r)
      REPOSITORY="${OPTARG}";;
    e)
      ENVIRONMENTS="${OPTARG}";;
    h | *)
      print_help
      exit 0;;
  esac
done

for env in $ENVIRONMENTS;
do
    gh variable set --repo "${ORGANISATION}/${REPOSITORY}" --env $env --env-file $VARIABLES_FILE
    gh secret set --repo "${ORGANISATION}/${REPOSITORY}" --env $env --env-file $SECRETS_FILE
done

if [ -n "$GLOBAL_VARIABLES_FILE" ]; then
    gh variable set --repo "${ORGANISATION}/${REPOSITORY}" --env global --env-file $GLOBAL_VARIABLES_FILE
fi