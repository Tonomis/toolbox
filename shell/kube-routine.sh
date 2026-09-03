#!/bin/bash

# Colorize terminal
red='\e[0;31m'
green='\e[0;32m'
yellow='\e[0;33m'
blue='\e[0;34m'
cyan='\e[0;36m'
no_color='\033[0m'

# Console step increment
i=1

# Default settings
MODE="daily"
VERBOSE="false"
SUGGEST="false"
OUTPUT_FILE=""
NAMESPACE=""
CONTEXT=""

# Operational thresholds (rules of thumb, not kubelet eviction thresholds)
CPU_THRESHOLD=80              # % CPU used on a node before raising attention
MEM_THRESHOLD=85              # % memory used on a node before raising attention
REQUESTS_THRESHOLD=80         # % of allocatable already reserved by requests
QUOTA_THRESHOLD=90            # % of a ResourceQuota consumed before raising attention
POD_SLOTS_THRESHOLD=80        # % of allocatable pod slots used
ORPHAN_RS_THRESHOLD=50        # empty ReplicaSets before suggesting a revisionHistoryLimit cut
TERMINATED_POD_THRESHOLD=100  # Succeeded/Failed pods before suggesting a TTL policy
RESTART_THRESHOLD=20          # container restarts before raising attention
PENDING_MINUTES=15            # a pod pending longer than this is stuck
STALE_CRONJOB_DAYS=7          # a CronJob not scheduled since then is suspicious
CERT_WARN_DAYS=30             # certificate expiry warning window
CERT_CRIT_DAYS=7              # certificate expiry critical window
EVENT_WINDOW_HOURS=24         # look-back window for Warning events
DETAIL_LINES=20               # max lines listed per check in verbose mode

# Namespaces where privileged/host-level workloads are expected
SYSTEM_NS_PATTERN='^(kube-system|kube-public|kube-node-lease|longhorn-system|metallb-system|cilium|calico-system|tigera-operator|rook-ceph|openebs|kubevirt|cdi|istio-system|linkerd)$'

# Core components whose failure impacts the whole cluster
CORE_PATTERN='coredns|kube-proxy|metrics-server|cilium|calico|flannel|csi-|cloud-controller|konnectivity'

# Findings and their suggested debug commands (same index)
WARNINGS=()
WARNING_CMDS=()
CRITICALS=()
CRITICAL_CMDS=()

# Declare script helper
TEXT_HELPER="\nThis script runs the recurring Kubernetes operations routine (daily, weekly, monthly).
Following flags are available:

  -m    (Optional) Routine to run. Available routines are :
          daily     - Nodes, API server, failing pods, restarts, workloads, storage claims,
                      resource usage, warning events, GitOps sync.
          weekly    - Terminated pods/jobs, orphan ReplicaSets, quotas, node pressure, QoS,
                      disruption budgets, dead services, image and security drift,
                      autoscaling, storage hygiene.
          monthly   - Certificates, deprecated APIs, RBAC, capacity trends, fleet drift.
          all       - Run the three routines in a row.
        Default is '$MODE'.

  -n    (Optional) Restrict namespaced checks to a single namespace.
        Default is all namespaces.

  -c    (Optional) Kubernetes context to use.
        Default is the current context.

  -v    (Optional) Verbose mode - list the offending objects, not only the counters.
        Default is '$VERBOSE'.

  -d    (Optional) Debug mode - print the commands to run to investigate each finding.
        Default is '$SUGGEST'.

  -o    (Optional) Save output to file.
        Example: -o /tmp/kube-routine.txt

  -h    Print script help.

Exit codes: 0 - nothing to report, 1 - warnings found, 2 - critical findings.\n\n"

print_help() {
  printf "$TEXT_HELPER"
}

check_package() {
  if ! command -v "$1" &> /dev/null; then
    printf "${red}Error:${no_color} '$1' could not be found. Please install it to proceed.\n"
    exit 1
  fi
}

# Check dependencies
check_package "kubectl"
check_package "jq"

# Parse options
while getopts m:n:c:o:vdh flag; do
  case "${flag}" in
    m)
      MODE="${OPTARG}";;
    n)
      NAMESPACE="${OPTARG}";;
    c)
      CONTEXT="${OPTARG}";;
    o)
      OUTPUT_FILE="${OPTARG}";;
    v)
      VERBOSE="true";;
    d)
      SUGGEST="true";;
    h | *)
      print_help
      exit 0;;
  esac
done

if [ "$MODE" != "daily" ] && [ "$MODE" != "weekly" ] && [ "$MODE" != "monthly" ] && [ "$MODE" != "all" ]; then
  printf "${red}Error:${no_color} Invalid routine '$MODE'. Available routines are: daily, weekly, monthly, all.\n"
  exit 1
fi

# Build kubectl arguments
[ -n "$CONTEXT" ] && CONTEXT_ARG="--context=$CONTEXT"
if [ -n "$NAMESPACE" ]; then
  NS_ARG="--namespace=$NAMESPACE"
else
  NS_ARG="--all-namespaces"
fi

# kubectl wrapper carrying the context
kc() {
  kubectl $CONTEXT_ARG "$@"
}

# Prefix used in the suggested commands, so they can be copy pasted as is
KCTL="kubectl"
[ -n "$CONTEXT" ] && KCTL="kubectl --context=$CONTEXT"

# One API call per resource, reused by every check of the run
CACHE_DIR=$(mktemp -d -t kube-routine-XXXXXX)
trap 'rm -rf "$CACHE_DIR"' EXIT INT TERM

# Fetch a resource once, cache it as JSON and echo the file path
fetch() {
  local key="$1"; shift
  local file="$CACHE_DIR/$key.json"
  if [ ! -s "$file" ]; then
    kc get "$@" -o json > "$file" 2>/dev/null
    [ -s "$file" ] || printf '{"items":[]}' > "$file"
  fi
  printf '%s' "$file"
}

# Group the suggested debug commands of a finding into a single payload
cmds() {
  local IFS=$'\n'
  echo "$*"
}

# Field $2 of the first line of a TSV payload, used to build an example command
first_field() {
  echo "$1" | head -1 | cut -f"$2"
}

# Function to print section header
print_section() {
  printf "\n${red}${i}.${no_color} ${blue}$1${no_color}\n"
  i=$(($i + 1))
}

# Function to print key-value pair
print_info() {
  printf "  ${cyan}→${no_color} %-30s ${green}%s${no_color}\n" "$1:" "$2"
}

# Function to print a note under a check
print_note() {
  printf "      ${yellow}Note:${no_color} %s\n" "$1"
}

# Function to print a detail line
print_detail() {
  printf "      %s\n" "$1"
}

# Print the debug commands attached to a finding (-d only)
print_commands() {
  [ "$SUGGEST" != "true" ] && return 0
  [ -z "$1" ] && return 0

  while IFS= read -r command; do
    [ -z "$command" ] && continue
    printf "      ${cyan}\$${no_color} %s\n" "$command"
  done < <(echo "$1")
  return 0
}

# Function to print warning (normal priority, fix during the day/week)
print_warning() {
  WARNINGS+=("$1")
  WARNING_CMDS+=("${2:-}")
  printf "  ${yellow}⚠${no_color} %s\n" "$1"
  print_commands "${2:-}"
}

# Function to print critical finding (investigate immediately)
print_critical() {
  CRITICALS+=("$1")
  CRITICAL_CMDS+=("${2:-}")
  printf "  ${red}✖${no_color} %s\n" "$1"
  print_commands "${2:-}"
}

# Align a TSV payload into columns when possible
format_table() {
  if command -v column &> /dev/null; then
    column -t -s "$(printf '\t')"
  else
    cat
  fi
}

# List the details of a check, capped to DETAIL_LINES (verbose mode only)
print_list() {
  local payload="$1" total
  [ "$VERBOSE" != "true" ] && return 0
  [ -z "$payload" ] && return 0

  total=$(echo "$payload" | wc -l)
  echo "$payload" | head -n "$DETAIL_LINES" | format_table | while IFS= read -r line; do
    print_detail "$line"
  done
  if [ "$total" -gt "$DETAIL_LINES" ]; then
    print_detail "... and $((total - DETAIL_LINES)) more"
  fi
  return 0
}

# Count the lines of a payload (0 when empty)
count_lines() {
  [ -z "$1" ] && { echo 0; return; }
  echo "$1" | wc -l
}

# jq prelude converting Kubernetes quantities (100m, 4Gi, 1e3) into plain numbers
JQ_QTY='def qty: if . == null then 0
  elif type == "number" then .
  elif test("^[0-9.]+m$") then (.[:-1] | tonumber) / 1000
  elif test("^[0-9.]+Ki$") then (.[:-2] | tonumber) * 1024
  elif test("^[0-9.]+Mi$") then (.[:-2] | tonumber) * 1048576
  elif test("^[0-9.]+Gi$") then (.[:-2] | tonumber) * 1073741824
  elif test("^[0-9.]+Ti$") then (.[:-2] | tonumber) * 1099511627776
  elif test("^[0-9.]+Pi$") then (.[:-2] | tonumber) * 1125899906842624
  elif test("^[0-9.]+k$") then (.[:-1] | tonumber) * 1000
  elif test("^[0-9.]+M$") then (.[:-1] | tonumber) * 1000000
  elif test("^[0-9.]+G$") then (.[:-1] | tonumber) * 1000000000
  elif test("^[0-9.]+T$") then (.[:-1] | tonumber) * 1000000000000
  else (tonumber? // 0) end;'

# Convert a Kubernetes quantity into a plain number (shell side)
normalize_quantity() {
  awk -v q="$1" 'BEGIN {
    n = q; mult = 1
    if (n ~ /m$/)       { sub(/m$/, "", n);  mult = 0.001 }
    else if (n ~ /Ki$/) { sub(/Ki$/, "", n); mult = 1024 }
    else if (n ~ /Mi$/) { sub(/Mi$/, "", n); mult = 1024^2 }
    else if (n ~ /Gi$/) { sub(/Gi$/, "", n); mult = 1024^3 }
    else if (n ~ /Ti$/) { sub(/Ti$/, "", n); mult = 1024^4 }
    else if (n ~ /Pi$/) { sub(/Pi$/, "", n); mult = 1024^5 }
    else if (n ~ /k$/)  { sub(/k$/, "", n);  mult = 1000 }
    else if (n ~ /M$/)  { sub(/M$/, "", n);  mult = 1000^2 }
    else if (n ~ /G$/)  { sub(/G$/, "", n);  mult = 1000^3 }
    else if (n ~ /T$/)  { sub(/T$/, "", n);  mult = 1000^4 }
    else if (n ~ /P$/)  { sub(/P$/, "", n);  mult = 1000^5 }
    if (n !~ /^[0-9.]+$/) { print "0"; exit }
    printf "%.6f", n * mult
  }'
}

# Percentage of $1 over $2, rounded to one decimal ("-" when the limit is 0)
percent_of() {
  awk -v used="$1" -v hard="$2" 'BEGIN { if (hard + 0 == 0) print "-"; else printf "%.1f", used / hard * 100 }'
}

# Human readable size from a byte count
human_bytes() {
  awk -v b="$1" 'BEGIN {
    split("B KiB MiB GiB TiB PiB", u, " ")
    n = 1
    while (b >= 1024 && n < 6) { b /= 1024; n++ }
    printf "%.1f%s", b, u[n]
  }'
}

# Days left before the RFC3339 date $1 ("-" when unparsable)
days_until() {
  local target
  # GNU date happily parses loose strings such as '-', so only accept a real timestamp
  case "$1" in
    [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T*) ;;
    *) echo "-"; return;;
  esac
  target=$(date -d "$1" +%s 2>/dev/null)
  [ -z "$target" ] && { echo "-"; return; }
  echo $(( (target - $(date +%s)) / 86400 ))
}

# Redirect output if needed
if [ -n "$OUTPUT_FILE" ]; then
  exec > >(tee "$OUTPUT_FILE")
fi

# Check cluster reachability before anything else
if ! kc version -o json --request-timeout=10s 2>/dev/null | jq -e '.serverVersion' > /dev/null 2>&1; then
  printf "${red}Error:${no_color} Unable to reach the cluster. Check your kubeconfig, context and network.\n"
  exit 2
fi

CURRENT_CONTEXT=$(kc config current-context 2>/dev/null || echo "N/A")
CUTOFF=$(date -u -d "${EVENT_WINDOW_HOURS} hours ago" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)

# Available API resources, used to skip checks for absent operators
API_RESOURCES=$(kc api-resources --verbs=list -o name 2>/dev/null)
has_resource() {
  echo "$API_RESOURCES" | grep -qx "$1"
}


# ------------------------------------------------------------------------------
# Daily routine - the 5 minutes morning check
# ------------------------------------------------------------------------------
run_daily() {
  # Nodes health
  print_section "Nodes health"

  NODES=$(jq -r '.items[] | [.metadata.name,
    (((.status.conditions // [])[] | select(.type == "Ready") | .status) // "Unknown"),
    ((.spec.unschedulable // false) | tostring)] | @tsv' "$(fetch nodes nodes)")

  if [ -z "$NODES" ]; then
    print_critical "Unable to list nodes (missing RBAC or unreachable API server)" \
      "$(cmds "$KCTL auth can-i list nodes" "$KCTL cluster-info")"
  else
    NODE_TOTAL=$(count_lines "$NODES")
    NODE_READY=$(echo "$NODES" | awk -F'\t' '$2 == "True"' | wc -l)
    print_info "Nodes Ready" "$NODE_READY / $NODE_TOTAL"

    while IFS=$'\t' read -r name ready unschedulable; do
      [ -z "$name" ] && continue
      if [ "$ready" != "True" ]; then
        print_critical "Node $name is not Ready (status $ready) - check kubelet, connectivity and disk" \
          "$(cmds "$KCTL describe node $name" \
                  "$KCTL get events -A --field-selector involvedObject.name=$name --sort-by=.lastTimestamp" \
                  "$KCTL get pods -A -o wide --field-selector spec.nodeName=$name")"
      fi
      if [ "$unschedulable" = "true" ]; then
        print_warning "Node $name is cordoned - maintenance in progress ?" \
          "$(cmds "$KCTL describe node $name" "$KCTL uncordon $name   # once the maintenance is over")"
      fi
    done < <(echo "$NODES")
  fi

  # API server health
  print_section "API server health"

  READYZ=$(kc get --raw='/readyz?verbose' --request-timeout=10s 2>/dev/null)
  if [ -z "$READYZ" ]; then
    print_warning "Unable to read /readyz (missing RBAC ?) - check the control plane manually" \
      "$(cmds "$KCTL get --raw='/readyz?verbose'" "$KCTL auth can-i get /readyz")"
  else
    FAILED_CHECKS=$(echo "$READYZ" | grep '^\[-\]')
    print_info "Healthy checks" "$(echo "$READYZ" | grep -c '^\[+\]')"
    if [ -n "$FAILED_CHECKS" ]; then
      while IFS= read -r line; do
        COMPONENT=$(echo "$line" | sed 's/^\[-\]//' | awk '{print $1}')
        print_critical "Degraded component: $COMPONENT" \
          "$(cmds "$KCTL get --raw='/readyz/$COMPONENT?verbose'" \
                  "$KCTL -n kube-system get pods -o wide" \
                  "$KCTL -n kube-system logs -l component=$COMPONENT --tail=100")"
      done < <(echo "$FAILED_CHECKS")
    else
      print_info "Overall status" "ok"
    fi
  fi

  # Failing pods
  print_section "Failing pods"

  FAILING_PODS=$(jq -r '.items[]
    | select(.status.phase != "Running" and .status.phase != "Succeeded")
    | [.metadata.namespace, .metadata.name, .status.phase,
       ([(.status.containerStatuses // [])[].state.waiting.reason] | map(select(. != null)) | first // "-"),
       (.status.startTime // .metadata.creationTimestamp // "-")] | @tsv' "$(fetch pods pods $NS_ARG)")

  if [ -z "$FAILING_PODS" ]; then
    print_info "Pods not Running/Succeeded" "0"
  else
    print_info "Pods not Running/Succeeded" "$(count_lines "$FAILING_PODS")"

    while IFS=$'\t' read -r ns name phase reason started; do
      [ -z "$name" ] && continue
      if [ "$ns" = "kube-system" ] && echo "$name" | grep -qE "$CORE_PATTERN"; then
        print_critical "Core component $ns/$name is $phase ($reason) - cluster wide impact" \
          "$(cmds "$KCTL -n $ns describe pod $name" \
                  "$KCTL -n $ns logs $name --previous --tail=100" \
                  "$KCTL -n $ns get events --field-selector involvedObject.name=$name")"
      fi
    done < <(echo "$FAILING_PODS")

    # A pod pending for a while is stuck, not starting
    STUCK=$(echo "$FAILING_PODS" | awk -F'\t' -v cutoff="$(date -u -d "${PENDING_MINUTES} minutes ago" +%Y-%m-%dT%H:%M:%SZ)" \
      '$3 == "Pending" && $5 < cutoff {printf "%s\t%s\t%s\t%s\n", $1, $2, $4, $5}')
    if [ -n "$STUCK" ]; then
      print_warning "$(count_lines "$STUCK") pod(s) Pending for more than ${PENDING_MINUTES}min - check requests, taints and PVC binding" \
        "$(cmds "$KCTL -n $(first_field "$STUCK" 1) describe pod $(first_field "$STUCK" 2)   # events at the bottom" \
                "$KCTL get nodes -o custom-columns=NAME:.metadata.name,TAINTS:.spec.taints")"
      print_list "$STUCK"
    fi

    printf "\n  ${cyan}Breakdown by namespace:${no_color}\n"
    echo "$FAILING_PODS" | awk -F'\t' '{print $1}' | sort | uniq -c | sort -rn | head -10 | \
      while read -r count ns; do
        printf "      %-40s %s pod(s)\n" "$ns" "$count"
      done

    print_list "$(echo "$FAILING_PODS" | awk -F'\t' '{printf "%s\t%s\t%s\t%s\n", $1, $2, $3, $4}')"
  fi

  # Container restarts and OOM kills
  print_section "Container restarts"

  RESTARTS=$(jq -r '.items[]
    | .metadata.namespace as $ns | .metadata.name as $pod
    | (.status.containerStatuses // [])[]
    | select((.restartCount // 0) > 0)
    | [$ns, $pod, .name, (.restartCount | tostring),
       (.lastState.terminated.reason // "-"),
       (.lastState.terminated.finishedAt // "-")] | @tsv' "$(fetch pods pods $NS_ARG)")

  if [ -z "$RESTARTS" ]; then
    print_info "Containers restarted" "0"
  else
    print_info "Containers restarted" "$(count_lines "$RESTARTS")"

    # OOM kills are the silent killer, surface them whatever the count
    OOM=$(echo "$RESTARTS" | awk -F'\t' '$5 == "OOMKilled"')
    if [ -n "$OOM" ]; then
      print_warning "$(count_lines "$OOM") container(s) OOMKilled - raise the memory limit or fix the leak" \
        "$(cmds "$KCTL -n $(first_field "$OOM" 1) logs $(first_field "$OOM" 2) -c $(first_field "$OOM" 3) --previous --tail=100" \
                "$KCTL -n $(first_field "$OOM" 1) get pod $(first_field "$OOM" 2) -o jsonpath='{.spec.containers[*].resources}'" \
                "$KCTL -n $(first_field "$OOM" 1) top pod $(first_field "$OOM" 2) --containers")"
      print_list "$(echo "$OOM" | awk -F'\t' '{printf "%s/%s\t%s\trestarts=%s\t%s\n", $1, $2, $3, $4, $6}')"
    fi

    RECENT=$(echo "$RESTARTS" | awk -F'\t' -v cutoff="$CUTOFF" '$6 >= cutoff')
    [ -n "$RECENT" ] && print_info "Restarted in the last ${EVENT_WINDOW_HOURS}h" "$(count_lines "$RECENT")"

    HOT=$(echo "$RESTARTS" | awk -F'\t' -v t="$RESTART_THRESHOLD" '$4 + 0 >= t')
    if [ -n "$HOT" ]; then
      print_warning "$(count_lines "$HOT") container(s) above $RESTART_THRESHOLD restarts - recurring crash, investigate the logs" \
        "$(cmds "$KCTL -n $(first_field "$HOT" 1) logs $(first_field "$HOT" 2) -c $(first_field "$HOT" 3) --previous --tail=100" \
                "$KCTL -n $(first_field "$HOT" 1) describe pod $(first_field "$HOT" 2)")"
      print_list "$(echo "$HOT" | awk -F'\t' '{printf "%s/%s\t%s\trestarts=%s\t%s\n", $1, $2, $3, $4, $5}')"
    fi
  fi

  # Workload availability
  print_section "Workload availability"

  DEGRADED=$(jq -r '.items[]
    | (.spec.replicas // 0) as $desired | (.status.readyReplicas // 0) as $ready
    | ((((.status.conditions // [])[] | select(.type == "Progressing") | .status) // "True")) as $prog
    | select($ready < $desired or $prog == "False")
    | [.metadata.namespace, .metadata.name, "Deployment", "\($ready)/\($desired) ready",
       (if $prog == "False" then "rollout stuck" else "-" end)] | @tsv' "$(fetch deployments deployments $NS_ARG)")

  DEGRADED_STS=$(jq -r '.items[]
    | (.spec.replicas // 0) as $desired | (.status.readyReplicas // 0) as $ready
    | select($ready < $desired)
    | [.metadata.namespace, .metadata.name, "StatefulSet", "\($ready)/\($desired) ready", "-"] | @tsv' \
    "$(fetch statefulsets statefulsets $NS_ARG)")

  DEGRADED_DS=$(jq -r '.items[]
    | (.status.desiredNumberScheduled // 0) as $desired | (.status.numberReady // 0) as $ready
    | select($ready < $desired)
    | [.metadata.namespace, .metadata.name, "DaemonSet", "\($ready)/\($desired) ready", "-"] | @tsv' \
    "$(fetch daemonsets daemonsets $NS_ARG)")

  ALL_DEGRADED=$(printf '%s\n%s\n%s' "$DEGRADED" "$DEGRADED_STS" "$DEGRADED_DS" | grep -v '^$')

  if [ -z "$ALL_DEGRADED" ]; then
    print_info "Workloads below desired" "0"
  else
    DEGRADED_NS=$(first_field "$ALL_DEGRADED" 1)
    DEGRADED_NAME=$(first_field "$ALL_DEGRADED" 2)
    DEGRADED_KIND=$(first_field "$ALL_DEGRADED" 3 | tr '[:upper:]' '[:lower:]')
    print_warning "$(count_lines "$ALL_DEGRADED") workload(s) below their desired replicas" \
      "$(cmds "$KCTL -n $DEGRADED_NS rollout status $DEGRADED_KIND/$DEGRADED_NAME --timeout=10s" \
              "$KCTL -n $DEGRADED_NS describe $DEGRADED_KIND $DEGRADED_NAME" \
              "$KCTL -n $DEGRADED_NS get pods -o wide")"
    print_list "$ALL_DEGRADED"
    [ "$VERBOSE" != "true" ] && print_note "run with -v to list them"
  fi

  # Storage claims
  print_section "Storage claims"

  UNBOUND=$(jq -r '.items[] | select(.status.phase != "Bound")
    | [.metadata.namespace, .metadata.name, .status.phase, (.spec.storageClassName // "-")] | @tsv' \
    "$(fetch pvc persistentvolumeclaims $NS_ARG)")

  if [ -z "$UNBOUND" ]; then
    print_info "PVC not Bound" "0"
  else
    print_warning "$(count_lines "$UNBOUND") PVC not Bound - pods waiting on them stay Pending" \
      "$(cmds "$KCTL -n $(first_field "$UNBOUND" 1) describe pvc $(first_field "$UNBOUND" 2)" \
              "$KCTL get storageclass" \
              "$KCTL -n $(first_field "$UNBOUND" 1) get events --field-selector involvedObject.name=$(first_field "$UNBOUND" 2)")"
    print_list "$UNBOUND"
  fi

  # Resource consumption
  print_section "Resource consumption"

  TOP_NODES=$(kc top nodes --no-headers 2>/dev/null)
  if [ -z "$TOP_NODES" ]; then
    print_warning "kubectl top nodes returned nothing - is metrics-server installed and ready ?" \
      "$(cmds "$KCTL -n kube-system get pods -l k8s-app=metrics-server" \
              "$KCTL -n kube-system logs -l k8s-app=metrics-server --tail=50")"
  else
    while IFS= read -r line; do
      NODE_NAME=$(echo "$line" | awk '{print $1}')
      NODE_CPU=$(echo "$line" | awk '{print $3}' | tr -d '%')
      NODE_MEM=$(echo "$line" | awk '{print $5}' | tr -d '%')
      printf "  ${cyan}→${no_color} %-40s CPU %3s%%   MEM %3s%%\n" "$NODE_NAME" "$NODE_CPU" "$NODE_MEM"

      if [ "$NODE_CPU" -ge "$CPU_THRESHOLD" ] 2>/dev/null; then
        print_warning "Node $NODE_NAME above ${CPU_THRESHOLD}% CPU (${NODE_CPU}%)" \
          "$(cmds "$KCTL top pods -A --sort-by=cpu | head -10" \
                  "$KCTL describe node $NODE_NAME | grep -A6 'Allocated resources'")"
      fi
      if [ "$NODE_MEM" -ge "$MEM_THRESHOLD" ] 2>/dev/null; then
        print_warning "Node $NODE_NAME above ${MEM_THRESHOLD}% memory (${NODE_MEM}%)" \
          "$(cmds "$KCTL top pods -A --sort-by=memory | head -10" \
                  "$KCTL describe node $NODE_NAME | grep -A6 'Allocated resources'")"
      fi
    done < <(echo "$TOP_NODES")
    print_note "operational markers, kubelet evicts on memory.available / nodefs.available."

    if [ "$VERBOSE" = "true" ]; then
      printf "\n  ${cyan}Top 5 pods by CPU:${no_color}\n"
      print_list "$(kc top pods $NS_ARG --no-headers 2>/dev/null | \
        awk '{cpu = $(NF-1); sub(/m$/, "", cpu); name = (NF == 4 ? $1 "/" $2 : $1); printf "%d\t%s\t%s\t%s\n", cpu + 0, name, $(NF-1), $NF}' | \
        sort -rn | head -5 | cut -f2-)"
    fi
  fi

  # Warning events
  print_section "Warning events (last ${EVENT_WINDOW_HOURS}h)"

  EVENTS=$(kc get events $NS_ARG --field-selector type=Warning -o json 2>/dev/null | \
    jq -r --arg cutoff "$CUTOFF" '.items[]
      | ((.lastTimestamp // .eventTime // .metadata.creationTimestamp) // "") as $ts
      | select($ts >= $cutoff)
      | [$ts, .metadata.namespace, .reason,
         (.involvedObject.kind + "/" + .involvedObject.name),
         (.message // "" | gsub("[\\n\\t]"; " "))] | @tsv' | sort)

  if [ -z "$EVENTS" ]; then
    print_info "Warning events" "0"
  else
    print_info "Warning events" "$(count_lines "$EVENTS")"

    printf "\n  ${cyan}Most frequent reasons:${no_color}\n"
    echo "$EVENTS" | awk -F'\t' '{print $3}' | sort | uniq -c | sort -rn | head -5 | \
      while read -r count reason; do
        printf "      %-30s %s occurrence(s)\n" "$reason" "$count"
      done

    if [ "$SUGGEST" = "true" ]; then
      TOP_REASON=$(echo "$EVENTS" | awk -F'\t' '{print $3}' | sort | uniq -c | sort -rn | head -1 | awk '{print $2}')
      print_commands "$(cmds "$KCTL get events $NS_ARG --field-selector type=Warning,reason=$TOP_REASON --sort-by=.lastTimestamp")"
    fi

    if [ "$VERBOSE" = "true" ]; then
      printf "\n  ${cyan}Last events:${no_color}\n"
      print_list "$(echo "$EVENTS" | tail -n "$DETAIL_LINES" | \
        awk -F'\t' '{printf "%s\t%s\t%s\t%s\n", $1, $2, $3, substr($4 " " $5, 1, 80)}')"
    fi
  fi

  # GitOps drift
  if has_resource "applications.argoproj.io"; then
    print_section "GitOps applications (Argo CD)"

    APPS=$(jq -r '.items[] | [.metadata.namespace, .metadata.name,
      (.status.sync.status // "Unknown"), (.status.health.status // "Unknown")] | @tsv' \
      "$(fetch argoapps applications.argoproj.io $NS_ARG)")

    if [ -z "$APPS" ]; then
      print_info "Applications" "0"
    else
      print_info "Applications" "$(count_lines "$APPS")"
      SYNCED=$(echo "$APPS" | awk -F'\t' '$3 == "Synced" && $4 == "Healthy"' | wc -l)
      print_info "Synced and healthy" "$SYNCED / $(count_lines "$APPS")"

      while IFS=$'\t' read -r ns name sync health; do
        [ -z "$name" ] && continue
        APP_CMDS=$(cmds "$KCTL -n $ns describe application $name" \
                        "$KCTL -n $ns get application $name -o jsonpath='{.status.resources}' | jq" \
                        "argocd app get $name")
        case "$health" in
          Healthy|Progressing) ;;
          Degraded) print_critical "Argo CD application $ns/$name is Degraded" "$APP_CMDS";;
          *) print_warning "Argo CD application $ns/$name health is $health" "$APP_CMDS";;
        esac
        if [ "$sync" = "OutOfSync" ]; then
          print_warning "Argo CD application $ns/$name is OutOfSync - cluster drifted from git" \
            "$(cmds "argocd app diff $name" "$KCTL -n $ns get application $name -o jsonpath='{.status.sync}' | jq")"
        fi
      done < <(echo "$APPS")
    fi
  fi
}


# ------------------------------------------------------------------------------
# Weekly routine - orphan resources, drift and pressure
# ------------------------------------------------------------------------------
run_weekly() {
  # Terminated pods
  print_section "Terminated pods"

  TERMINATED=$(jq -r '.items[] | select(.status.phase == "Succeeded" or .status.phase == "Failed")
    | [.metadata.namespace, .metadata.name, .status.phase, (.status.reason // "-")] | @tsv' \
    "$(fetch pods pods $NS_ARG)")

  SUCCEEDED=$(echo "$TERMINATED" | awk -F'\t' '$3 == "Succeeded"' | grep -c .)
  FAILED=$(echo "$TERMINATED" | awk -F'\t' '$3 == "Failed"' | grep -c .)
  EVICTED_PODS=$(echo "$TERMINATED" | awk -F'\t' '$4 == "Evicted"')
  print_info "Succeeded pods" "$SUCCEEDED"
  print_info "Failed pods" "$FAILED"

  if [ "$((SUCCEEDED + FAILED))" -gt "$TERMINATED_POD_THRESHOLD" ]; then
    print_warning "$((SUCCEEDED + FAILED)) terminated pods still in the API - set ttlSecondsAfterFinished rather than deleting by hand" \
      "$(cmds "$KCTL get pods $NS_ARG --field-selector=status.phase==Succeeded" \
              "$KCTL get jobs $NS_ARG -o custom-columns=NS:.metadata.namespace,NAME:.metadata.name,TTL:.spec.ttlSecondsAfterFinished")"
  fi
  if [ -n "$EVICTED_PODS" ]; then
    print_warning "$(count_lines "$EVICTED_PODS") evicted pod(s) - confirm the node pressure before cleaning them up" \
      "$(cmds "$KCTL -n $(first_field "$EVICTED_PODS" 1) describe pod $(first_field "$EVICTED_PODS" 2)" \
              "$KCTL get nodes -o custom-columns=NAME:.metadata.name,CONDITIONS:.status.conditions[?(@.status==\"True\")].type")"
  fi
  print_list "$(echo "$TERMINATED" | awk -F'\t' '$3 == "Failed"')"

  # Jobs and CronJobs
  print_section "Jobs and CronJobs retention"

  CRONJOBS=$(jq -r '.items[] | [.metadata.namespace, .metadata.name,
    ((.spec.successfulJobsHistoryLimit // 3) | tostring), ((.spec.failedJobsHistoryLimit // 1) | tostring),
    ((.spec.suspend // false) | tostring), (.status.lastScheduleTime // "-"), .spec.schedule] | @tsv' \
    "$(fetch cronjobs cronjobs $NS_ARG)")

  if [ -z "$CRONJOBS" ]; then
    print_info "CronJobs" "0"
  else
    print_info "CronJobs" "$(count_lines "$CRONJOBS")"
    SUSPENDED=$(echo "$CRONJOBS" | awk -F'\t' '$5 == "true"' | grep -c .)
    [ "$SUSPENDED" -gt 0 ] && print_info "Suspended CronJobs" "$SUSPENDED"

    LOOSE_CRON=$(echo "$CRONJOBS" | awk -F'\t' '$3 + 0 > 5 {printf "%s\t%s\tsuccessfulJobsHistoryLimit=%s\n", $1, $2, $3}')
    if [ -n "$LOOSE_CRON" ]; then
      print_warning "$(count_lines "$LOOSE_CRON") CronJob(s) keeping more than 5 successful jobs - lower successfulJobsHistoryLimit" \
        "$(cmds "$KCTL -n $(first_field "$LOOSE_CRON" 1) patch cronjob $(first_field "$LOOSE_CRON" 2) -p '{\"spec\":{\"successfulJobsHistoryLimit\":3}}'")"
      print_list "$LOOSE_CRON"
    fi

    STALE_CRON=$(echo "$CRONJOBS" | awk -F'\t' -v cutoff="$(date -u -d "${STALE_CRONJOB_DAYS} days ago" +%Y-%m-%dT%H:%M:%SZ)" \
      '$5 == "false" && $6 < cutoff {printf "%s\t%s\tlast=%s\tschedule=%s\n", $1, $2, $6, $7}')
    if [ -n "$STALE_CRON" ]; then
      print_warning "$(count_lines "$STALE_CRON") active CronJob(s) not scheduled for ${STALE_CRONJOB_DAYS}d - check the schedule and the controller" \
        "$(cmds "$KCTL -n $(first_field "$STALE_CRON" 1) describe cronjob $(first_field "$STALE_CRON" 2)" \
                "$KCTL -n kube-system logs -l component=kube-controller-manager --tail=50 | grep -i cronjob")"
      print_list "$STALE_CRON"
    fi
  fi

  JOBS_FILE=$(fetch jobs jobs $NS_ARG)
  print_info "Completed Jobs" "$(jq -r '[.items[] | select((.status.succeeded // 0) > 0)] | length' "$JOBS_FILE")"

  FAILED_JOBS=$(jq -r '.items[] | select((.status.failed // 0) > 0)
    | [.metadata.namespace, .metadata.name, "failed=\(.status.failed)"] | @tsv' "$JOBS_FILE")
  if [ -n "$FAILED_JOBS" ]; then
    print_warning "$(count_lines "$FAILED_JOBS") Job(s) with failed pods" \
      "$(cmds "$KCTL -n $(first_field "$FAILED_JOBS" 1) describe job $(first_field "$FAILED_JOBS" 2)" \
              "$KCTL -n $(first_field "$FAILED_JOBS" 1) logs job/$(first_field "$FAILED_JOBS" 2) --tail=100")"
    print_list "$FAILED_JOBS"
  fi

  NO_TTL_JOBS=$(jq -r '.items[] | select(.spec.ttlSecondsAfterFinished == null)
    | select((.metadata.ownerReferences // []) | length == 0)
    | [.metadata.namespace, .metadata.name] | @tsv' "$JOBS_FILE")
  if [ -n "$NO_TTL_JOBS" ]; then
    print_warning "$(count_lines "$NO_TTL_JOBS") standalone Job(s) without ttlSecondsAfterFinished - they will never be garbage collected" \
      "$(cmds "$KCTL -n $(first_field "$NO_TTL_JOBS" 1) patch job $(first_field "$NO_TTL_JOBS" 2) -p '{\"spec\":{\"ttlSecondsAfterFinished\":86400}}'")"
    print_list "$NO_TTL_JOBS"
  fi

  # Orphan ReplicaSets
  print_section "Orphan ReplicaSets"

  ORPHAN_RS=$(jq -r '.items[] | select((.spec.replicas // 0) == 0 and (.status.replicas // 0) == 0)
    | [.metadata.namespace, .metadata.name] | @tsv' "$(fetch replicasets replicasets $NS_ARG)")

  ORPHAN_COUNT=$(count_lines "$ORPHAN_RS")
  print_info "Empty ReplicaSets" "$ORPHAN_COUNT"
  if [ "$ORPHAN_COUNT" -gt "$ORPHAN_RS_THRESHOLD" ]; then
    print_warning "$ORPHAN_COUNT empty ReplicaSets in etcd - lower spec.revisionHistoryLimit to 3 or 5" \
      "$(cmds "$KCTL get rs $NS_ARG --no-headers | awk '\$3 == 0 && \$4 == 0' | head" \
              "$KCTL -n $(first_field "$ORPHAN_RS" 1) patch deployment <name> -p '{\"spec\":{\"revisionHistoryLimit\":3}}'")"
  fi

  LOOSE_DEPLOYS=$(jq -r '.items[] | select((.spec.revisionHistoryLimit // 10) > 5)
    | [.metadata.namespace, .metadata.name, "revisionHistoryLimit=\(.spec.revisionHistoryLimit // 10)"] | @tsv' \
    "$(fetch deployments deployments $NS_ARG)")
  if [ -n "$LOOSE_DEPLOYS" ]; then
    print_info "Deployments history > 5" "$(count_lines "$LOOSE_DEPLOYS")"
    print_list "$LOOSE_DEPLOYS"
  fi

  # Resource quotas
  print_section "Namespace quotas"

  QUOTAS=$(jq -r '.items[] | . as $q | ($q.status.hard // {}) | keys[] as $k
    | [$q.metadata.namespace, $q.metadata.name, $k, $q.status.hard[$k], ($q.status.used[$k] // "0")] | @tsv' \
    "$(fetch quotas resourcequotas $NS_ARG)")

  if [ -z "$QUOTAS" ]; then
    print_info "ResourceQuota" "none defined"
  else
    print_info "Quota entries" "$(count_lines "$QUOTAS")"
    QUOTA_DETAILS=""
    while IFS=$'\t' read -r ns name resource hard used; do
      [ -z "$resource" ] && continue
      PCT=$(percent_of "$(normalize_quantity "$used")" "$(normalize_quantity "$hard")")
      [ "$PCT" = "-" ] && continue

      if awk -v p="$PCT" -v t="$QUOTA_THRESHOLD" 'BEGIN { exit !(p >= t) }'; then
        print_warning "Quota $ns/$name $resource at ${PCT}% ($used / $hard) - next deployments may be rejected" \
          "$(cmds "$KCTL -n $ns describe resourcequota $name" \
                  "$KCTL -n $ns get pods -o custom-columns=NAME:.metadata.name,CPU:.spec.containers[*].resources.requests.cpu,MEM:.spec.containers[*].resources.requests.memory")"
      else
        QUOTA_DETAILS="${QUOTA_DETAILS}${ns}\t${name}\t${resource}\t${PCT}%\t${used} / ${hard}\n"
      fi
    done < <(echo "$QUOTAS")
    print_list "$(printf '%b' "$QUOTA_DETAILS" | grep -v '^$')"
  fi

  print_info "LimitRanges" "$(jq -r '[.items[]] | length' "$(fetch limitranges limitranges $NS_ARG)")"

  # Node pressure
  print_section "Node pressure"

  PRESSURE=$(jq -r '.items[] | [.metadata.name,
    (((.status.conditions // [])[] | select(.type == "DiskPressure") | .status) // "Unknown"),
    (((.status.conditions // [])[] | select(.type == "MemoryPressure") | .status) // "Unknown"),
    (((.status.conditions // [])[] | select(.type == "PIDPressure") | .status) // "Unknown")] | @tsv' \
    "$(fetch nodes nodes)")

  if [ -z "$PRESSURE" ]; then
    print_warning "Unable to read node conditions" "$(cmds "$KCTL get nodes -o yaml | head -50")"
  else
    PRESSURE_FOUND="false"
    while IFS=$'\t' read -r node disk mem pid; do
      [ -z "$node" ] && continue
      NODE_CMDS=$(cmds "$KCTL describe node $node | grep -A10 Conditions" \
                       "$KCTL get pods -A -o wide --field-selector spec.nodeName=$node" \
                       "$KCTL top pods -A --sort-by=memory | head -10")
      if [ "$disk" = "True" ]; then
        print_critical "Node $node has DiskPressure - kubelet is evicting pods, check logs, images and ephemeral volumes" \
          "$(cmds "$KCTL describe node $node | grep -A10 Conditions" \
                  "$KCTL get pods -A -o wide --field-selector spec.nodeName=$node" \
                  "sudo crictl images   # on the node itself, before any targeted cleanup")"
        PRESSURE_FOUND="true"
      fi
      if [ "$mem" = "True" ]; then
        print_critical "Node $node has MemoryPressure - kubelet is evicting pods by QoS class" "$NODE_CMDS"
        PRESSURE_FOUND="true"
      fi
      if [ "$pid" = "True" ]; then
        print_warning "Node $node has PIDPressure" "$NODE_CMDS"
        PRESSURE_FOUND="true"
      fi
    done < <(echo "$PRESSURE")
    [ "$PRESSURE_FOUND" = "false" ] && print_info "Pressure conditions" "none"
  fi

  # QoS and resource requests
  print_section "QoS and resource requests"

  QOS=$(jq -r '.items[] | select(.status.phase == "Running")
    | [.metadata.namespace, .metadata.name, (.status.qosClass // "-"),
       ([.spec.containers[] | select(.resources.requests.cpu == null or .resources.requests.memory == null)] | length | tostring),
       ([.spec.containers[] | select(.resources.limits.memory == null)] | length | tostring)] | @tsv' \
    "$(fetch pods pods $NS_ARG)")

  if [ -z "$QOS" ]; then
    print_info "Running pods" "0"
  else
    print_info "Running pods" "$(count_lines "$QOS")"
    for class in Guaranteed Burstable BestEffort; do
      COUNT=$(echo "$QOS" | awk -F'\t' -v c="$class" '$3 == c' | grep -c .)
      [ "$COUNT" -gt 0 ] && print_info "  QoS $class" "$COUNT"
    done

    BESTEFFORT=$(echo "$QOS" | awk -F'\t' '$3 == "BestEffort" {printf "%s\t%s\n", $1, $2}')
    if [ -n "$BESTEFFORT" ]; then
      print_warning "$(count_lines "$BESTEFFORT") BestEffort pod(s) - they are evicted first under pressure, set requests" \
        "$(cmds "$KCTL get pods $NS_ARG -o custom-columns=NS:.metadata.namespace,NAME:.metadata.name,QOS:.status.qosClass | grep BestEffort" \
                "$KCTL -n $(first_field "$BESTEFFORT" 1) describe pod $(first_field "$BESTEFFORT" 2) | grep -A5 'QoS Class'")"
      print_list "$BESTEFFORT"
    fi

    NO_MEM_LIMIT=$(echo "$QOS" | awk -F'\t' '$5 + 0 > 0 {printf "%s\t%s\t%s container(s) without memory limit\n", $1, $2, $5}')
    if [ -n "$NO_MEM_LIMIT" ]; then
      print_warning "$(count_lines "$NO_MEM_LIMIT") pod(s) without memory limit - one leak can take a node down" \
        "$(cmds "$KCTL -n $(first_field "$NO_MEM_LIMIT" 1) get pod $(first_field "$NO_MEM_LIMIT" 2) -o jsonpath='{.spec.containers[*].resources}'" \
                "$KCTL get limitranges $NS_ARG   # a LimitRange can set defaults namespace wide")"
      print_list "$NO_MEM_LIMIT"
    fi
  fi

  # Disruption budgets
  if has_resource "poddisruptionbudgets.policy"; then
    print_section "Disruption budgets"

    PDB=$(jq -r '.items[] | [.metadata.namespace, .metadata.name,
      ((.status.disruptionsAllowed // 0) | tostring),
      ((.status.currentHealthy // 0) | tostring), ((.status.desiredHealthy // 0) | tostring)] | @tsv' \
      "$(fetch pdb poddisruptionbudgets $NS_ARG)")

    if [ -z "$PDB" ]; then
      print_info "PodDisruptionBudgets" "0"
      print_note "no PDB means a node drain can take a whole workload down at once."
    else
      print_info "PodDisruptionBudgets" "$(count_lines "$PDB")"
      BLOCKING=$(echo "$PDB" | awk -F'\t' '$3 + 0 == 0 {printf "%s\t%s\thealthy=%s/%s\n", $1, $2, $4, $5}')
      if [ -n "$BLOCKING" ]; then
        print_warning "$(count_lines "$BLOCKING") PDB with 0 allowed disruption - a node drain will hang on them" \
          "$(cmds "$KCTL -n $(first_field "$BLOCKING" 1) describe pdb $(first_field "$BLOCKING" 2)" \
                  "$KCTL -n $(first_field "$BLOCKING" 1) get pdb $(first_field "$BLOCKING" 2) -o jsonpath='{.spec.selector}'")"
        print_list "$BLOCKING"
      fi
    fi

    SINGLETONS=$(jq -r '.items[] | select((.spec.replicas // 0) == 1)
      | [.metadata.namespace, .metadata.name] | @tsv' "$(fetch deployments deployments $NS_ARG)")
    if [ -n "$SINGLETONS" ]; then
      print_info "Single replica Deployments" "$(count_lines "$SINGLETONS")"
      print_list "$SINGLETONS"
    fi
  fi

  # Services without endpoints
  if has_resource "endpointslices.discovery.k8s.io"; then
    print_section "Services without endpoints"

    DEAD_SVC=$(jq -rn \
      --slurpfile svc "$(fetch services services $NS_ARG)" \
      --slurpfile es "$(fetch endpointslices endpointslices.discovery.k8s.io $NS_ARG)" '
      ($es[0].items
        | map({k: (.metadata.namespace + "/" + (.metadata.labels["kubernetes.io/service-name"] // "?")),
               n: ([.endpoints[]? | select(.conditions.ready != false) | .addresses[]?] | length)})
        | group_by(.k) | map({key: .[0].k, value: (map(.n) | add)}) | from_entries) as $eps
      | $svc[0].items[]
      | select(.spec.type != "ExternalName" and (.spec.selector // {}) != {})
      | select((($eps[.metadata.namespace + "/" + .metadata.name]) // 0) == 0)
      | [.metadata.namespace, .metadata.name, .spec.type] | @tsv')

    if [ -z "$DEAD_SVC" ]; then
      print_info "Services with endpoints" "all"
    else
      print_warning "$(count_lines "$DEAD_SVC") Service(s) without ready endpoint - selector mismatch or no running pod" \
        "$(cmds "$KCTL -n $(first_field "$DEAD_SVC" 1) describe svc $(first_field "$DEAD_SVC" 2)" \
                "$KCTL -n $(first_field "$DEAD_SVC" 1) get endpointslices -l kubernetes.io/service-name=$(first_field "$DEAD_SVC" 2)")"
      print_list "$DEAD_SVC"
    fi
  fi

  # Image hygiene
  print_section "Image hygiene"

  MUTABLE_IMAGES=$(jq -r '.items[] | select(.status.phase == "Running")
    | .metadata.namespace as $ns | .metadata.name as $pod
    | .spec.containers[]
    | select((.image | split("/") | last) | test(":latest$") or (test(":|@") | not))
    | [$ns, $pod, .image] | @tsv' "$(fetch pods pods $NS_ARG)")

  if [ -z "$MUTABLE_IMAGES" ]; then
    print_info "Mutable image tags" "0"
  else
    print_warning "$(count_lines "$MUTABLE_IMAGES") container(s) running a mutable tag (:latest or none) - pin a version or a digest" \
      "$(cmds "$KCTL -n $(first_field "$MUTABLE_IMAGES" 1) get pod $(first_field "$MUTABLE_IMAGES" 2) -o jsonpath='{.status.containerStatuses[*].imageID}'")"
    print_list "$MUTABLE_IMAGES"
  fi

  # Security drift
  print_section "Security drift"

  HOST_ACCESS=$(jq -r '.items[] | select(.status.phase == "Running")
    | .metadata.namespace as $ns | .metadata.name as $pod
    | [ (if (.spec.hostNetwork // false) then "hostNetwork" else empty end),
        (if (.spec.hostPID // false) then "hostPID" else empty end),
        (if (.spec.hostIPC // false) then "hostIPC" else empty end),
        (if ([.spec.volumes[]? | select(.hostPath != null)] | length) > 0 then "hostPath" else empty end),
        (if ([.spec.containers[] | select(.securityContext.privileged == true)] | length) > 0 then "privileged" else empty end)
      ] as $flags
    | select(($flags | length) > 0)
    | [$ns, $pod, ($flags | join(","))] | @tsv' "$(fetch pods pods $NS_ARG)")

  if [ -z "$HOST_ACCESS" ]; then
    print_info "Pods with host level access" "0"
  else
    print_info "Pods with host level access" "$(count_lines "$HOST_ACCESS")"
    PRIVILEGED_APPS=$(echo "$HOST_ACCESS" | grep 'privileged' | awk -F'\t' -v p="$SYSTEM_NS_PATTERN" '$1 !~ p')
    if [ -n "$PRIVILEGED_APPS" ]; then
      print_warning "$(count_lines "$PRIVILEGED_APPS") privileged pod(s) outside the system namespaces - review the SecurityContext" \
        "$(cmds "$KCTL -n $(first_field "$PRIVILEGED_APPS" 1) get pod $(first_field "$PRIVILEGED_APPS" 2) -o jsonpath='{.spec.containers[*].securityContext}'" \
                "$KCTL -n $(first_field "$PRIVILEGED_APPS" 1) get pod $(first_field "$PRIVILEGED_APPS" 2) -o jsonpath='{.metadata.ownerReferences}'")"
      print_list "$PRIVILEGED_APPS"
    else
      print_note "only system namespaces (CNI, CSI, storage) hold privileged pods, as expected."
    fi
    print_list "$HOST_ACCESS"
  fi

  # Autoscaling
  if has_resource "horizontalpodautoscalers.autoscaling"; then
    print_section "Autoscaling"

    HPA=$(jq -r '.items[] | [.metadata.namespace, .metadata.name,
      ((.status.currentReplicas // 0) | tostring), ((.spec.maxReplicas // 0) | tostring),
      ((((.status.conditions // [])[] | select(.type == "ScalingActive") | .status)) // "Unknown"),
      ((((.status.conditions // [])[] | select(.type == "AbleToScale") | .status)) // "Unknown")] | @tsv' \
      "$(fetch hpa horizontalpodautoscalers $NS_ARG)")

    if [ -z "$HPA" ]; then
      print_info "HorizontalPodAutoscalers" "0"
    else
      print_info "HorizontalPodAutoscalers" "$(count_lines "$HPA")"
      while IFS=$'\t' read -r ns name current max active able; do
        [ -z "$name" ] && continue
        HPA_CMDS=$(cmds "$KCTL -n $ns describe hpa $name" \
                        "$KCTL top pods -n $ns")
        [ "$active" = "False" ] && print_warning "HPA $ns/$name cannot read its metrics (ScalingActive=False)" \
          "$(cmds "$KCTL -n $ns describe hpa $name" "$KCTL -n kube-system logs -l k8s-app=metrics-server --tail=50")"
        [ "$able" = "False" ] && print_warning "HPA $ns/$name is unable to scale (AbleToScale=False)" "$HPA_CMDS"
        if [ "$current" -ge "$max" ] 2>/dev/null && [ "$max" -gt 0 ] 2>/dev/null; then
          print_warning "HPA $ns/$name saturated at maxReplicas ($max) - raise the ceiling or optimise the workload" "$HPA_CMDS"
        fi
      done < <(echo "$HPA")
    fi
  fi

  # Storage hygiene
  print_section "Storage hygiene"

  UNUSED_PVC=$(jq -rn \
    --slurpfile pvc "$(fetch pvc persistentvolumeclaims $NS_ARG)" \
    --slurpfile pods "$(fetch pods pods $NS_ARG)" '
    ($pods[0].items | map(.metadata.namespace as $ns
      | (.spec.volumes[]? | select(.persistentVolumeClaim != null) | $ns + "/" + .persistentVolumeClaim.claimName))
      | unique) as $used
    | $pvc[0].items[] | select(.status.phase == "Bound")
    | (.metadata.namespace + "/" + .metadata.name) as $key
    | select(($used | index($key)) == null)
    | [.metadata.namespace, .metadata.name, (.status.capacity.storage // "-"), (.spec.storageClassName // "-")] | @tsv')

  if [ -z "$UNUSED_PVC" ]; then
    print_info "Bound PVC without pod" "0"
  else
    print_warning "$(count_lines "$UNUSED_PVC") Bound PVC not mounted by any pod - storage paid for nothing" \
      "$(cmds "$KCTL -n $(first_field "$UNUSED_PVC" 1) describe pvc $(first_field "$UNUSED_PVC" 2)" \
              "$KCTL -n $(first_field "$UNUSED_PVC" 1) get pods -o jsonpath='{range .items[*]}{.metadata.name}{\"\\t\"}{.spec.volumes[*].persistentVolumeClaim.claimName}{\"\\n\"}{end}'")"
    print_list "$UNUSED_PVC"
  fi

  if [ -z "$NAMESPACE" ]; then
    LOST_PV=$(jq -r '.items[] | select(.status.phase == "Released" or .status.phase == "Failed")
      | [.metadata.name, .status.phase, (.spec.capacity.storage // "-"),
         ((.spec.claimRef.namespace // "-") + "/" + (.spec.claimRef.name // "-"))] | @tsv' \
      "$(fetch pv persistentvolumes)")

    if [ -z "$LOST_PV" ]; then
      print_info "PV Released/Failed" "0"
    else
      print_warning "$(count_lines "$LOST_PV") PV in Released/Failed - reclaim or delete them" \
        "$(cmds "$KCTL describe pv $(first_field "$LOST_PV" 1)" \
                "$KCTL get pv $(first_field "$LOST_PV" 1) -o jsonpath='{.spec.persistentVolumeReclaimPolicy}'")"
      print_list "$LOST_PV"
    fi
  fi
}


# ------------------------------------------------------------------------------
# Monthly routine - certificates, compliance and capacity trends
# ------------------------------------------------------------------------------
run_monthly() {
  # Control plane certificates
  print_section "Control plane certificates"

  if command -v kubeadm &> /dev/null; then
    if [ "$(id -u)" -eq 0 ]; then
      KUBEADM_CERTS=$(kubeadm certs check-expiration 2>/dev/null)
    else
      KUBEADM_CERTS=$(sudo -n kubeadm certs check-expiration 2>/dev/null)
    fi

    if [ -z "$KUBEADM_CERTS" ]; then
      print_info "kubeadm certs" "not readable (needs root on a control plane node)"
    else
      while IFS= read -r line; do
        CERT_NAME=$(echo "$line" | awk '{print $1}')
        RESIDUAL=$(echo "$line" | grep -oE '[0-9]+d' | head -1 | tr -d 'd')
        [ -z "$RESIDUAL" ] && continue
        if [ "$RESIDUAL" -lt "$CERT_CRIT_DAYS" ]; then
          print_critical "Certificate $CERT_NAME expires in ${RESIDUAL}d - run 'kubeadm certs renew all' now" \
            "$(cmds "sudo kubeadm certs check-expiration" \
                    "sudo kubeadm certs renew $CERT_NAME" \
                    "sudo crictl ps | grep kube-apiserver   # then restart the static pods")"
        elif [ "$RESIDUAL" -lt "$CERT_WARN_DAYS" ]; then
          print_warning "Certificate $CERT_NAME expires in ${RESIDUAL}d - plan the renewal" \
            "$(cmds "sudo kubeadm certs check-expiration" "sudo kubeadm certs renew $CERT_NAME")"
        fi
      done < <(echo "$KUBEADM_CERTS" | grep -E '^[a-z]')
      print_note "after a renewal, restart the control plane static pods, never delete their manifests."
    fi
  else
    print_info "kubeadm" "not available locally (run this part on a control plane node)"
  fi

  # Kubelet client certificates waiting for approval
  PENDING_CSR=$(jq -r '.items[] | select((.status.conditions // []) | length == 0)
    | [.metadata.name, .spec.signerName, (.spec.username // "-")] | @tsv' \
    "$(fetch csr certificatesigningrequests)")
  if [ -n "$PENDING_CSR" ]; then
    print_warning "$(count_lines "$PENDING_CSR") CertificateSigningRequest pending approval - a kubelet may be stuck rotating its certificate" \
      "$(cmds "$KCTL get csr $(first_field "$PENDING_CSR" 1) -o yaml" \
              "$KCTL certificate approve $(first_field "$PENDING_CSR" 1)   # only after checking the requester")"
    print_list "$PENDING_CSR"
  fi

  # cert-manager certificates
  print_section "Ingress certificates (cert-manager)"

  if ! has_resource "certificates.cert-manager.io"; then
    print_info "cert-manager" "not installed"
  else
    CERTS=$(jq -r '.items[] | [.metadata.namespace, .metadata.name,
      ((((.status.conditions // [])[] | select(.type == "Ready") | .status)) // "Unknown"),
      (.status.notAfter // "-")] | @tsv' "$(fetch certs certificates.cert-manager.io $NS_ARG)")

    if [ -z "$CERTS" ]; then
      print_info "Certificates" "0"
    else
      print_info "Certificates" "$(count_lines "$CERTS")"
      while IFS=$'\t' read -r ns name ready expiry; do
        [ -z "$name" ] && continue
        if [ "$ready" != "True" ]; then
          print_critical "Certificate $ns/$name is not Ready ($ready) - check the cert-manager logs and the ACME challenge" \
            "$(cmds "$KCTL -n $ns describe certificate $name" \
                    "$KCTL -n $ns get certificaterequest,order,challenge" \
                    "$KCTL -n cert-manager logs -l app.kubernetes.io/name=cert-manager --tail=100")"
          continue
        fi

        DAYS_LEFT=$(days_until "$expiry")
        [ "$DAYS_LEFT" = "-" ] && continue
        CERT_CMDS=$(cmds "$KCTL -n $ns describe certificate $name" \
                         "$KCTL -n $ns get secret $name -o jsonpath='{.data.tls\\.crt}' | base64 -d | openssl x509 -noout -dates")
        if [ "$DAYS_LEFT" -lt "$CERT_CRIT_DAYS" ]; then
          print_critical "Certificate $ns/$name expires in ${DAYS_LEFT}d - renew immediately" "$CERT_CMDS"
        elif [ "$DAYS_LEFT" -lt "$CERT_WARN_DAYS" ]; then
          print_warning "Certificate $ns/$name expires in ${DAYS_LEFT}d" "$CERT_CMDS"
        fi
      done < <(echo "$CERTS")
    fi
  fi

  if has_resource "ingresses.networking.k8s.io"; then
    NO_TLS=$(jq -r '.items[] | select(((.spec.tls // []) | length) == 0)
      | [.metadata.namespace, .metadata.name, ([.spec.rules[]?.host] | join(","))] | @tsv' \
      "$(fetch ingresses ingresses $NS_ARG)")
    if [ -n "$NO_TLS" ]; then
      print_warning "$(count_lines "$NO_TLS") Ingress without TLS block - traffic served in clear" \
        "$(cmds "$KCTL -n $(first_field "$NO_TLS" 1) describe ingress $(first_field "$NO_TLS" 2)")"
      print_list "$NO_TLS"
    else
      print_info "Ingress without TLS" "0"
    fi
  fi

  # Deprecated APIs
  print_section "Deprecated APIs"

  DEPRECATED=$(kc get --raw /metrics --request-timeout=20s 2>/dev/null | \
    awk '/^apiserver_requested_deprecated_apis/ && $NF + 0 > 0 {
      group = ""; version = ""; resource = ""; removed = ""
      if (match($0, /group="[^"]*"/))           { group = substr($0, RSTART + 7, RLENGTH - 8) }
      if (match($0, /version="[^"]*"/))         { version = substr($0, RSTART + 9, RLENGTH - 10) }
      if (match($0, /resource="[^"]*"/))        { resource = substr($0, RSTART + 10, RLENGTH - 11) }
      if (match($0, /removed_release="[^"]*"/)) { removed = substr($0, RSTART + 17, RLENGTH - 18) }
      printf "%s\t%s\t%s\n", (group == "" ? "core" : group) "/" version, resource, (removed == "" ? "no removal scheduled" : "removed in " removed)
    }' | sort -u)

  if [ -z "$DEPRECATED" ]; then
    print_info "Deprecated API calls" "none recorded"
    print_note "the metric only covers the requests seen by the current API server process."
  else
    SCHEDULED=$(echo "$DEPRECATED" | grep 'removed in')
    print_info "Deprecated APIs in use" "$(count_lines "$DEPRECATED")"
    if [ -n "$SCHEDULED" ]; then
      print_warning "$(count_lines "$SCHEDULED") deprecated API(s) with a removal release - migrate the manifests before upgrading" \
        "$(cmds "$KCTL get --raw /metrics | grep apiserver_requested_deprecated_apis" \
                "$KCTL api-resources | grep $(echo "$SCHEDULED" | head -1 | cut -f2)")"
    fi
    print_list "$DEPRECATED"
  fi

  # RBAC
  print_section "RBAC exposure"

  ADMIN_BINDINGS=$(jq -r '.items[] | select(.roleRef.name == "cluster-admin")
    | select((.metadata.name | startswith("system:")) | not)
    | [.metadata.name, ([.subjects[]? | .kind + ":" + (if .namespace then .namespace + "/" else "" end) + .name] | join(","))] | @tsv' \
    "$(fetch clusterrolebindings clusterrolebindings)")

  if [ -z "$ADMIN_BINDINGS" ]; then
    print_info "cluster-admin bindings" "defaults only"
  else
    print_info "cluster-admin bindings" "$(count_lines "$ADMIN_BINDINGS")"
    SA_ADMINS=$(echo "$ADMIN_BINDINGS" | grep 'ServiceAccount:')
    if [ -n "$SA_ADMINS" ]; then
      print_warning "$(count_lines "$SA_ADMINS") ServiceAccount(s) bound to cluster-admin - scope them down if possible" \
        "$(cmds "$KCTL describe clusterrolebinding $(first_field "$SA_ADMINS" 1)" \
                "$KCTL auth can-i --list --as=system:serviceaccount:<namespace>:<name>")"
    fi
    print_list "$ADMIN_BINDINGS"
  fi

  # Capacity trends
  print_section "Capacity trends"

  NODES_FILE=$(fetch nodes nodes)
  PODS_FILE=$(fetch pods pods --all-namespaces)

  print_info "Nodes" "$(jq -r '[.items[]] | length' "$NODES_FILE")"
  POD_COUNT=$(jq -r '[.items[] | select(.status.phase == "Running" or .status.phase == "Pending")] | length' "$PODS_FILE")
  POD_CAPACITY=$(jq -r "$JQ_QTY"'[.items[] | select((.spec.unschedulable // false) | not) | .status.allocatable.pods | qty] | add // 0' "$NODES_FILE")
  print_info "Pods" "$POD_COUNT / ${POD_CAPACITY:-?} slots"

  if [ "${POD_CAPACITY:-0}" -gt 0 ] 2>/dev/null; then
    POD_PCT=$(percent_of "$POD_COUNT" "$POD_CAPACITY")
    print_info "Pod slots used" "${POD_PCT}%"
    if awk -v p="$POD_PCT" -v t="$POD_SLOTS_THRESHOLD" 'BEGIN { exit !(p >= t) }'; then
      print_warning "Pod capacity above ${POD_SLOTS_THRESHOLD}% - plan node additions before scheduling starts failing" \
        "$(cmds "$KCTL get nodes -o custom-columns=NAME:.metadata.name,PODS:.status.allocatable.pods" \
                "$KCTL get pods -A -o wide --field-selector status.phase=Running | awk '{print \$8}' | sort | uniq -c")"
    fi
  fi

  # Reserved capacity is what really drives scheduling, not the live usage
  ALLOC=$(jq -rn --slurpfile nodes "$NODES_FILE" --slurpfile pods "$PODS_FILE" "$JQ_QTY"'
    ($nodes[0].items | map(select((.spec.unschedulable // false) | not))) as $n
    | ($pods[0].items | map(select(.status.phase == "Running" or .status.phase == "Pending"))) as $p
    | [ ($n | map(.status.allocatable.cpu | qty) | add // 0),
        ($p | map([.spec.containers[].resources.requests.cpu | qty] | add // 0) | add // 0),
        ($n | map(.status.allocatable.memory | qty) | add // 0),
        ($p | map([.spec.containers[].resources.requests.memory | qty] | add // 0) | add // 0) ] | @tsv')

  if [ -n "$ALLOC" ]; then
    IFS=$'\t' read -r CPU_ALLOC CPU_REQ MEM_ALLOC MEM_REQ <<< "$ALLOC"
    CPU_PCT=$(percent_of "$CPU_REQ" "$CPU_ALLOC")
    MEM_PCT=$(percent_of "$MEM_REQ" "$MEM_ALLOC")
    print_info "CPU requests / allocatable" "$(awk -v v="$CPU_REQ" 'BEGIN {printf "%.1f", v}') / $(awk -v v="$CPU_ALLOC" 'BEGIN {printf "%.1f", v}') cores (${CPU_PCT}%)"
    print_info "Memory requests / allocatable" "$(human_bytes "$MEM_REQ") / $(human_bytes "$MEM_ALLOC") (${MEM_PCT}%)"

    for entry in "CPU:$CPU_PCT" "memory:$MEM_PCT"; do
      LABEL="${entry%%:*}"; VALUE="${entry##*:}"
      [ "$VALUE" = "-" ] && continue
      if awk -v p="$VALUE" -v t="$REQUESTS_THRESHOLD" 'BEGIN { exit !(p >= t) }'; then
        print_warning "${LABEL} requests cover ${VALUE}% of the allocatable capacity - little room left to reschedule a node" \
          "$(cmds "$KCTL describe nodes | grep -A6 'Allocated resources'" \
                  "$KCTL top nodes")"
      fi
    done
  fi

  PV_FILE=$(fetch pv persistentvolumes)
  PV_TOTAL=$(jq -r "$JQ_QTY"'[.items[] | .spec.capacity.storage | qty] | add // 0' "$PV_FILE")
  [ "${PV_TOTAL:-0}" != "0" ] && print_info "Provisioned storage" "$(human_bytes "$PV_TOTAL") over $(jq -r '[.items[]] | length' "$PV_FILE") PV"

  TOP_NODES=$(kc top nodes --no-headers 2>/dev/null)
  if [ -n "$TOP_NODES" ]; then
    echo "$TOP_NODES" | awk -v cyan="\033[0;36m" -v nc="\033[0m" \
      '{ cpu += $3; mem += $5; n++ } END { if (n > 0) printf "  %s→%s %-30s CPU %.1f%%  MEM %.1f%%\n", cyan, nc, "Live usage (average):", cpu / n, mem / n }'
    print_note "compare with the previous months, a steady rise means it is time to resize."
  fi

  # Versions and fleet drift
  print_section "Versions and fleet drift"

  VERSIONS=$(kc version -o json 2>/dev/null)
  SERVER_VERSION=$(echo "$VERSIONS" | jq -r '.serverVersion.gitVersion // "N/A"')
  print_info "kubectl" "$(echo "$VERSIONS" | jq -r '.clientVersion.gitVersion // "N/A"')"
  print_info "API server" "$SERVER_VERSION"

  FLEET=$(jq -r '.items[] | [.metadata.name, .status.nodeInfo.kubeletVersion,
    .status.nodeInfo.osImage, .status.nodeInfo.kernelVersion, .status.nodeInfo.containerRuntimeVersion] | @tsv' \
    "$NODES_FILE")

  for column in "kubelet:2" "OS image:3" "kernel:4" "runtime:5"; do
    LABEL="${column%%:*}"; INDEX="${column##*:}"
    DISTINCT=$(echo "$FLEET" | awk -F'\t' -v c="$INDEX" '{print $c}' | sort -u)
    COUNT=$(count_lines "$DISTINCT")
    if [ "$COUNT" -gt 1 ]; then
      print_warning "$COUNT different $LABEL versions across the fleet - align the nodes: $(echo "$DISTINCT" | tr '\n' ' ')" \
        "$(cmds "$KCTL get nodes -o wide")"
    else
      print_info "$LABEL" "$DISTINCT"
    fi
  done

  OUTDATED=$(echo "$FLEET" | awk -F'\t' -v v="$SERVER_VERSION" '$2 != v {printf "%s\t%s\n", $1, $2}')
  if [ -n "$OUTDATED" ]; then
    print_info "Nodes not on $SERVER_VERSION" "$(count_lines "$OUTDATED")"
    print_list "$OUTDATED"
  fi
}


# ------------------------------------------------------------------------------
# Run
# ------------------------------------------------------------------------------
printf "\n${blue}╔════════════════════════════════════════╗${no_color}\n"
printf "${blue}║${no_color}     ${green}Kubernetes Ops Routine${no_color}             ${blue}║${no_color}\n"
printf "${blue}╚════════════════════════════════════════╝${no_color}\n"
printf "Generated: $(date +'%Y-%m-%d %H:%M:%S')\n"
printf "Settings:
  > ROUTINE: ${MODE}
  > CONTEXT: ${CURRENT_CONTEXT}
  > NAMESPACE: $([ -n "$NAMESPACE" ] && echo "${NAMESPACE}" || echo 'all')
  > VERBOSE: ${VERBOSE}
  > DEBUG COMMANDS: ${SUGGEST}\n"

if [ "$MODE" = "daily" ] || [ "$MODE" = "all" ]; then
  printf "\n${blue}── Daily ─────────────────────────────────${no_color}\n"
  run_daily
fi

if [ "$MODE" = "weekly" ] || [ "$MODE" = "all" ]; then
  printf "\n${blue}── Weekly ────────────────────────────────${no_color}\n"
  run_weekly
fi

if [ "$MODE" = "monthly" ] || [ "$MODE" = "all" ]; then
  printf "\n${blue}── Monthly ───────────────────────────────${no_color}\n"
  run_monthly
fi


# Summary
printf "\n${blue}╔════════════════════════════════════════╗${no_color}\n"
printf "${blue}║${no_color}              ${green}Summary${no_color}                   ${blue}║${no_color}\n"
printf "${blue}╚════════════════════════════════════════╝${no_color}\n"

if [ ${#CRITICALS[@]} -gt 0 ]; then
  printf "\n${red}Critical (${#CRITICALS[@]}) - investigate now:${no_color}\n"
  for index in "${!CRITICALS[@]}"; do
    printf "  ${red}✖${no_color} %s\n" "${CRITICALS[$index]}"
    print_commands "${CRITICAL_CMDS[$index]}"
  done
fi

if [ ${#WARNINGS[@]} -gt 0 ]; then
  printf "\n${yellow}Warnings (${#WARNINGS[@]}) - handle during the day/week:${no_color}\n"
  for index in "${!WARNINGS[@]}"; do
    printf "  ${yellow}⚠${no_color} %s\n" "${WARNINGS[$index]}"
    print_commands "${WARNING_CMDS[$index]}"
  done
fi

if [ ${#CRITICALS[@]} -eq 0 ] && [ ${#WARNINGS[@]} -eq 0 ]; then
  printf "\n${green}✓${no_color} Nothing to report.\n"
fi

if [ $(( ${#CRITICALS[@]} + ${#WARNINGS[@]} )) -gt 0 ]; then
  [ "$VERBOSE" != "true" ] && printf "\n${cyan}Tip:${no_color} run again with -v to list the objects behind each finding.\n"
  [ "$SUGGEST" != "true" ] && printf "${cyan}Tip:${no_color} run again with -d to get the commands to investigate each finding.\n"
fi

if [ -n "$OUTPUT_FILE" ]; then
  printf "\n${green}✓${no_color} Report saved to: ${cyan}$OUTPUT_FILE${no_color}\n"
fi

printf "\n"

if [ ${#CRITICALS[@]} -gt 0 ]; then
  exit 2
elif [ ${#WARNINGS[@]} -gt 0 ]; then
  exit 1
fi
exit 0
