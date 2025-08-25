#!/bin/bash

# Colorize terminal
red='\e[0;31m'
no_color='\033[0m'

# Get Date
NOW=$(date +'%Y-%m-%dT%H-%M-%S')

# Default
NAMESPACE="$(kubectl config view --minify -o jsonpath='{.contexts[0].context.namespace}')"
EXPORT_DIR="./secrets"
EXPORT_SUBDIR="$NAMESPACE-$NOW"

# Declare script helper
TEXT_HELPER="\nThis script aims to manage Kubernetes secret's :
Following flags are available:

  -m    Mode to run. Available modes are :
          dump              - Dump secrets a namespace.
          restore           - Restore secrets from a folder.
          transfer          - Transfer secrets from one namespace to another.

  -n    Namespace to use. Default is the current namespace.

  -o    Output directory for dump files. Default is './secrets/<namespace>-<date>'.

  -i    Input directory. Required for restore mode.

  -t    Target namespace. Required for transfer or restore mode.

  -h    Print script help.\n\n"

print_help() {
  printf "$TEXT_HELPER"
}

check_package() {
  if ! command -v "$1" &> /dev/null; then
    printf "${red}Error:.${no_color} '$1' could not be found. Please install it to proceed.\n"
    exit 1
  fi
}
# Check dependencies
check_package "kubectl"
check_package "jq"
check_package "kubectl-neat"


# Parse options
while getopts i:m:n:t:o:h: flag; do
  case "${flag}" in
    i)
      IMPORT_DIR="${OPTARG}";;
    m)
      MODE="${OPTARG}";;
    n)
      NAMESPACE="${OPTARG}";;
    t)
      TARGET_NAMESPACE="${OPTARG}";;
    o)
      EXPORT_DIR="${OPTARG}/$NAMESPACE-$NOW";;
    h | *)
      print_help
      exit 0;;
  esac
done

if [ -z "$MODE" ]; then
  printf "${red}Error:.${no_color} Mode is required. Use -m to specify the mode.\n".
  exit 1
elif [ "$MODE" != "dump" ] && [ "$MODE" != "restore" ] && [ "$MODE" != "transfer" ]; then
  printf "${red}Error:.${no_color} Invalid mode '$MODE'. Available modes are: dump, restore, transfer.\n"
  exit 1
elif [ "$MODE" == "restore" ] && [ -z "$IMPORT_DIR" ]; then
  printf "${red}Error:.${no_color} Input directory is required for restore mode. Use -i to specify the input directory.\n"
  exit 1
elif [ "$MODE" == "transfer" ] && [ -z "$TARGET_NAMESPACE" ]; then
  printf "${red}Error:.${no_color} Target namespace is required for transfer mode. Use -t to specify the target namespace.\n"
  exit 1
elif [ "$MODE" == "restore" ] && [ -z "$TARGET_NAMESPACE" ]; then
  printf "${red}Error:.${no_color} Target namespace is required for restore mode. Use -t to specify the target namespace.\n"
  exit 1
fi

# Add namespace if provided
[[ ! -z "$NAMESPACE" ]] && NAMESPACE_ARG="--namespace=$NAMESPACE"

printf "Settings:
  > MODE: ${MODE}
  > EXPORT_DIR: $(([ ${MODE} = 'dump' ] || [ ${MODE} = 'transfer' ]) && echo \"${EXPORT_DIR}\" || echo '-')
  > IMPORT_DIR: $(([ ${MODE} = 'restore' ]) && echo \"${IMPORT_DIR}\" || echo '-')
  > NAMESPACE: ${NAMESPACE}
  > TARGET: $(([ ${MODE} = 'transfer' ] || [ ${MODE} = 'restore' ]) && echo \"${TARGET_NAMESPACE}\" || echo '-')\n"

# Dump secrets
if [ "$MODE" == "dump" ]; then
  [ ! -d "$EXPORT_DIR" ] && mkdir -p "$EXPORT_DIR"

  DESTINATION_DUMP="$EXPORT_DIR/$EXPORT_SUBDIR"
  [ ! -d "$DESTINATION_DUMP" ] && mkdir -p "$DESTINATION_DUMP"
  
  printf "${red}Dumping secrets from namespace '${NAMESPACE}' to '${DESTINATION_DUMP}'...${no_color}\n"
  kubectl get secrets $NAMESPACE_ARG -o json | jq -r '.items[] | .metadata.name' | while read -r secret; do
    kubectl get secret "$secret" $NAMESPACE_ARG -o yaml | kubectl-neat > "$DESTINATION_DUMP/$secret.yaml"
    printf "  - Dumped secret: ${secret}\n"
  done

# Restore secrets
elif [ "$MODE" == "restore" ]; then
  if [ ! -d "$IMPORT_DIR" ]; then
    printf "${red}Error:.${no_color} Input directory '$IMPORT_DIR' does not exist.\n"
    exit 1
  fi
  printf "${red}Restoring secrets ${no_color}from '${IMPORT_DIR}' to namespace '${NAMESPACE}'...\n"
  for file in "$IMPORT_DIR"/*.yaml; do
    if [ -f "$file" ]; then
      secret_name=$(basename "$file" .yaml)
      sed -i "s/namespace: .*/namespace: $TARGET_NAMESPACE/" "$file"
      kubectl apply -f "$file" --namespace="$TARGET_NAMESPACE"
    else
      printf "${red}Warning:.${no_color} No YAML files found in '$IMPORT_DIR'. Skipping restore.\n"
    fi
  done

# Transfer secrets
elif [ "$MODE" == "transfer" ]; then
  if [ -z "$TARGET_NAMESPACE" ]; then
    printf "${red}Error:.${no_color} Target namespace is required for transfer mode. Use -t to specify the target namespace.\n"
    exit 1
  fi
  printf "${red}Transferring secrets ${no_color} from namespace '${NAMESPACE}' to '${TARGET_NAMESPACE}'...\n"
  kubectl get secrets $NAMESPACE_ARG -o json | jq -r '.items[] | .metadata.name' | while read -r secret; do
    kubectl get secret "$secret" $NAMESPACE_ARG -o yaml | kubectl-neat | sed "s/namespace: $NAMESPACE/namespace: $TARGET_NAMESPACE/" | kubectl apply -f - --namespace="$TARGET_NAMESPACE"
    printf "  - Transferred secret: ${secret}\n"
  done
fi