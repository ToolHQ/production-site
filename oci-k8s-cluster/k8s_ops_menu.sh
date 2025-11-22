#!/usr/bin/env bash
set -euo pipefail

# Source common configuration for SSH keys and node info
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# State variables
CURRENT_NS="default"
CURRENT_POD=""

# Helper to run kubectl commands on master
run_kubectl() {
  local cmd="$1"
  ssh -o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
      -q "$MASTER_NODE" "kubectl $cmd"
}

# Helper for interactive SSH sessions (logs -f, exec)
run_interactive_ssh() {
  local cmd="$1"
  ssh -t -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
      "$MASTER_NODE" "kubectl $cmd"
}

# --- MENUS ---

select_namespace() {
  echo -e "\n${BLUE}=== Select Namespace ===${NC}"
  echo "Fetching namespaces..."
  
  # Get namespaces into an array
  mapfile -t NAMESPACES < <(run_kubectl "get ns -o jsonpath='{.items[*].metadata.name}'" | tr ' ' '\n')
  
  if [ ${#NAMESPACES[@]} -eq 0 ]; then
    echo -e "${RED}Error fetching namespaces.${NC}"
    return
  fi

  # Display menu
  local i=1
  for ns in "${NAMESPACES[@]}"; do
    echo "$i) $ns"
    ((i++))
  done
  echo "0) Back"

  read -p "Select namespace number: " choice
  if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "${#NAMESPACES[@]}" ]; then
    CURRENT_NS="${NAMESPACES[$((choice-1))]}"
    echo -e "${GREEN}Selected namespace: $CURRENT_NS${NC}"
  elif [ "$choice" -eq 0 ]; then
    return
  else
    echo -e "${RED}Invalid selection.${NC}"
  fi
}

select_pod() {
  echo -e "\n${BLUE}=== Select Pod ($CURRENT_NS) ===${NC}"
  echo "Fetching pods..."
  
  # Get pods into an array
  mapfile -t PODS < <(run_kubectl "-n $CURRENT_NS get pods -o jsonpath='{.items[*].metadata.name}'" | tr ' ' '\n')
  
  if [ ${#PODS[@]} -eq 0 ]; then
    echo -e "${YELLOW}No pods found in namespace $CURRENT_NS.${NC}"
    CURRENT_POD=""
    return
  fi

  # Display menu
  local i=1
  for pod in "${PODS[@]}"; do
    # Get status for display
    status=$(run_kubectl "-n $CURRENT_NS get pod $pod -o jsonpath='{.status.phase}'")
    echo "$i) $pod [$status]"
    ((i++))
  done
  echo "0) Back"

  read -p "Select pod number: " choice
  if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "${#PODS[@]}" ]; then
    CURRENT_POD="${PODS[$((choice-1))]}"
    echo -e "${GREEN}Selected pod: $CURRENT_POD${NC}"
    pod_actions_menu
  elif [ "$choice" -eq 0 ]; then
    return
  else
    echo -e "${RED}Invalid selection.${NC}"
  fi
}

pod_actions_menu() {
  while true; do
    echo -e "\n${BLUE}=== Actions for $CURRENT_POD ($CURRENT_NS) ===${NC}"
    echo "1) View Logs (tail -f)"
    echo "2) View Previous Logs (--previous)"
    echo "3) Describe Pod"
    echo "4) Exec Shell (/bin/sh)"
    echo "5) Delete Pod (Restart)"
    echo "0) Back to Pod List"
    
    read -p "Choose action: " action
    case $action in
      1)
        echo -e "${YELLOW}Streaming logs (Ctrl+C to exit)...${NC}"
        run_interactive_ssh "-n $CURRENT_NS logs -f $CURRENT_POD"
        ;;
      2)
        echo -e "${YELLOW}Fetching previous logs...${NC}"
        run_interactive_ssh "-n $CURRENT_NS logs --previous $CURRENT_POD" || echo -e "${RED}No previous logs found.${NC}"
        read -p "Press Enter to continue..."
        ;;
      3)
        run_interactive_ssh "-n $CURRENT_NS describe pod $CURRENT_POD" | less
        ;;
      4)
        echo -e "${YELLOW}Connecting to shell...${NC}"
        run_interactive_ssh "-n $CURRENT_NS exec -it $CURRENT_POD -- /bin/sh" || \
        run_interactive_ssh "-n $CURRENT_NS exec -it $CURRENT_POD -- /bin/bash"
        ;;
      5)
        read -p "Are you sure you want to delete/restart $CURRENT_POD? (y/N): " confirm
        if [[ "$confirm" =~ ^[Yy]$ ]]; then
          run_kubectl "-n $CURRENT_NS delete pod $CURRENT_POD"
          echo -e "${GREEN}Pod deleted. Returning to list...${NC}"
          return
        fi
        ;;
      0)
        return
        ;;
      *)
        echo -e "${RED}Invalid option.${NC}"
        ;;
    esac
  done
}

main_menu() {
  while true; do
    echo -e "\n${BLUE}=== K8s Ops Menu ===${NC}"
    echo -e "Current Context: ${GREEN}$MASTER_NODE${NC}"
    echo -e "Namespace: ${YELLOW}$CURRENT_NS${NC}"
    echo "----------------"
    echo "1) Change Namespace"
    echo "2) List/Select Pods"
    echo "3) Show All Pods (All Namespaces)"
    echo "4) Check Node Status"
    echo "0) Exit"
    
    read -p "Choose option: " option
    case $option in
      1)
        select_namespace
        ;;
      2)
        select_pod
        ;;
      3)
        echo -e "\n${BLUE}=== All Pods ===${NC}"
        run_kubectl "get pods -A -o wide" | less -S
        ;;
      4)
        echo -e "\n${BLUE}=== Node Status ===${NC}"
        run_kubectl "get nodes -o wide"
        read -p "Press Enter to continue..."
        ;;
      0)
        echo "Bye!"
        exit 0
        ;;
      *)
        echo -e "${RED}Invalid option.${NC}"
        ;;
    esac
  done
}

# Start
main_menu
