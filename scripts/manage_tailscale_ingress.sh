#!/usr/bin/env bash
# manage_tailscale_ingress.sh — Create, update, list, and validate Tailscale-restricted Ingress resources
#
# Usage:
#   ./scripts/manage_tailscale_ingress.sh create <subdomain> <service-name> <service-port> [--namespace NAMESPACE]
#   ./scripts/manage_tailscale_ingress.sh delete <subdomain>
#   ./scripts/manage_tailscale_ingress.sh list
#   ./scripts/manage_tailscale_ingress.sh validate <subdomain>
#   ./scripts/manage_tailscale_ingress.sh dns <subdomain> <target-ip> [--dry-run]
#
# Examples:
#   ./scripts/manage_tailscale_ingress.sh create grafana grafana-service 3000 --namespace monitoring
#   ./scripts/manage_tailscale_ingress.sh delete grafana
#   ./scripts/manage_tailscale_ingress.sh list
#   ./scripts/manage_tailscale_ingress.sh validate clickhouse
#   ./scripts/manage_tailscale_ingress.sh dns grafana 150.136.67.52 --dry-run
#
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/oci-k8s-cluster/scripts/setup-dev-deploy.sh"
export KUBECONFIG="${KUBECONFIG:-$ROOT_DIR/oci-k8s-cluster/kubeconfig_tunnel.yaml}"

# Constants
DOMAIN="dnor.io"
TAILSCALE_CIDR="100.64.0.0/10"
INGRESS_CLASS="nginx"
COMPONENTS_DIR="$ROOT_DIR/components/observability"
REGISTRY_FILE="$ROOT_DIR/config/external-fleet/registry.yaml"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
GRAY='\033[0;37m'
NC='\033[0m'

info()  { echo -e "${BLUE}[info]${NC} $*"; }
ok()    { echo -e "${GREEN}[ok]${NC} $*"; }
warn()  { echo -e "${YELLOW}[warn]${NC} $*"; }
fail()  { echo -e "${RED}[error]${NC} $*" >&2; exit 1; }

usage() {
  cat <<'EOF'
Manage Tailscale-restricted Ingress resources.

Commands:
  create <subdomain> <svc-name> <svc-port> [--namespace NS]   Create ingress + manifest
  delete <subdomain>                                          Delete ingress + manifest
  list                                                        List all Tailscale-restricted ingresses
  validate <subdomain>                                        Validate ingress connectivity via Tailscale
  dns <subdomain> <target-ip> [--dry-run]                     Show GoDaddy DNS command

Options:
  --namespace NS   Kubernetes namespace (default: default)
  --dry-run        Show command without executing
  -h, --help       Show this help
EOF
}

# ─── CREATE ────────────────────────────────────────────────────────────────────
cmd_create() {
  local subdomain="$1"
  local svc_name="$2"
  local svc_port="$3"
  shift 3

  local namespace="default"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --namespace) namespace="$2"; shift 2 ;;
      *) fail "Unknown option: $1" ;;
    esac
  done

  local host="${subdomain}.${DOMAIN}"
  local manifest="$COMPONENTS_DIR/${subdomain}-ingress.yaml"

  if [[ -f "$manifest" ]]; then
    warn "Manifest already exists: $manifest"
    read -p "Overwrite? (y/N) " confirm
    [[ "$confirm" =~ ^[Yy]$ ]] || fail "Aborted."
  fi

  info "Creating ingress manifest: $manifest"
  cat > "$manifest" <<INGRESS_EOF
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: ${subdomain}-ingress
  namespace: ${namespace}
  annotations:
    nginx.ingress.kubernetes.io/whitelist-source-range: "${TAILSCALE_CIDR}" # Tailscale IPs only
spec:
  ingressClassName: ${INGRESS_CLASS}
  rules:
  - host: ${host}
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: ${svc_name}
            port:
              number: ${svc_port}
INGRESS_EOF

  ok "Manifest created: $manifest"

  info "Applying ingress to cluster..."
  kubectl apply -f "$manifest"
  ok "Ingress applied: ${subdomain}-ingress in namespace ${namespace}"

  info "Waiting for ingress address..."
  for i in $(seq 1 30); do
    local addr
    addr=$(kubectl get ingress -n "$namespace" "${subdomain}-ingress" -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)
    if [[ -n "$addr" ]]; then
      ok "Ingress address: $addr"
      break
    fi
    sleep 2
  done

  echo ""
  echo -e "${GRAY}────────────────────────────────────────${NC}"
  echo -e "${YELLOW}Next steps:${NC}"
  echo "  1. Add DNS record in GoDaddy:"
  echo "     ./scripts/manage_tailscale_ingress.sh dns $subdomain <node-ip>"
  echo "  2. Validate connectivity:"
  echo "     ./scripts/manage_tailscale_ingress.sh validate $subdomain"
  echo "  3. Update KANBAN.md with new service"
  echo -e "${GRAY}────────────────────────────────────────${NC}"
}

# ─── DELETE ────────────────────────────────────────────────────────────────────
cmd_delete() {
  local subdomain="$1"
  local manifest="$COMPONENTS_DIR/${subdomain}-ingress.yaml"

  if [[ ! -f "$manifest" ]]; then
    fail "Manifest not found: $manifest"
  fi

  info "Deleting ingress from cluster..."
  kubectl delete -f "$manifest" --ignore-not-found=true
  ok "Ingress deleted: ${subdomain}-ingress"

  info "Removing manifest: $manifest"
  rm -f "$manifest"
  ok "Manifest removed"

  echo ""
  echo -e "${YELLOW}Remember to:${NC}"
  echo "  - Remove DNS record from GoDaddy"
  echo "  - Update KANBAN.md"
}

# ─── LIST ──────────────────────────────────────────────────────────────────────
cmd_list() {
  info "Scanning for Tailscale-restricted ingresses..."
  echo ""

  local found=0
  for manifest in "$COMPONENTS_DIR"/*-ingress.yaml; do
    [[ -f "$manifest" ]] || continue
    if grep -q "whitelist-source-range" "$manifest" 2>/dev/null; then
      local name namespace host svc svc_port
      name=$(kubectl get -f "$manifest" -o jsonpath='{.metadata.name}' 2>/dev/null || basename "$manifest" .yaml)
      namespace=$(kubectl get -f "$manifest" -o jsonpath='{.metadata.namespace}' 2>/dev/null || echo "unknown")
      host=$(kubectl get -f "$manifest" -o jsonpath='{.spec.rules[0].host}' 2>/dev/null || echo "unknown")
      svc=$(kubectl get -f "$manifest" -o jsonpath='{.spec.rules[0].http.paths[0].backend.service.name}' 2>/dev/null || echo "unknown")
      svc_port=$(kubectl get -f "$manifest" -o jsonpath='{.spec.rules[0].http.paths[0].backend.service.port.number}' 2>/dev/null || echo "unknown")
      addr=$(kubectl get -f "$manifest" -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "pending")

      printf "  %-25s ns=%-15s svc=%-20s port=%-6s addr=%s\n" "$host" "$namespace" "$svc" "$svc_port" "$addr"
      found=$((found + 1))
    fi
  done

  if [[ $found -eq 0 ]]; then
    warn "No Tailscale-restricted ingresses found."
  else
    echo ""
    ok "$found Tailscale-restricted ingress(es) found."
  fi
}

# ─── VALIDATE ──────────────────────────────────────────────────────────────────
cmd_validate() {
  local subdomain="$1"
  local host="${subdomain}.${DOMAIN}"

  info "Validating ingress: $host"

  # Check if ingress exists in cluster
  local exists
  exists=$(kubectl get ingress -A -o jsonpath="{.items[?(@.spec.rules[0].host=='${host}')].metadata.name}" 2>/dev/null || true)
  if [[ -z "$exists" ]]; then
    fail "Ingress not found in cluster: $host"
  fi

  ok "Ingress exists in cluster: $exists"

  # Get Tailscale IP
  local ts_ip
  ts_ip=$(ip -4 addr show tailscale0 2>/dev/null | grep -oP 'inet \K[0-9.]+' || true)
  if [[ -z "$ts_ip" ]]; then
    ts_ip=$(tailscale ip -4 2>/dev/null || true)
  fi
  if [[ -z "$ts_ip" ]]; then
    warn "Tailscale not active — cannot validate from this machine."
    warn "Try: tailscale up"
    return 1
  fi

  info "Tailscale IP: $ts_ip"

  # Get ingress address (node IP)
  local ingress_addr
  ingress_addr=$(kubectl get ingress -A -o jsonpath="{.items[?(@.spec.rules[0].host=='${host}')].status.loadBalancer.ingress[0].ip}" 2>/dev/null || true)

  if [[ -n "$ingress_addr" ]]; then
    info "Testing HTTP via Tailscale node ($ingress_addr)..."
    local http_code
    http_code=$(curl -s -o /dev/null -w "%{http_code}" "http://${ingress_addr}:80/" -H "Host: ${host}" 2>/dev/null || echo "000")

    if [[ "$http_code" == "200" || "$http_code" == "301" || "$http_code" == "302" || "$http_code" == "403" ]]; then
      ok "HTTP response: $http_code (accessible via Tailscale)"
    else
      warn "HTTP response: $http_code (may need service to be ready)"
    fi
  else
    warn "Ingress address not yet assigned."
  fi

  # Check whitelist annotation
  local whitelist
  whitelist=$(kubectl get ingress -A -o jsonpath="{.items[?(@.spec.rules[0].host=='${host}')].metadata.annotations.nginx\.ingress\.kubernetes\.io/whitelist-source-range}" 2>/dev/null || true)
  if [[ "$whitelist" == "$TAILSCALE_CIDR" ]]; then
    ok "Whitelist correctly set: $whitelist"
  else
    warn "Whitelist not set or different: $whitelist"
  fi

  echo ""
  ok "Validation completed for $host"
}

# ─── DNS ───────────────────────────────────────────────────────────────────────
cmd_dns() {
  local subdomain="$1"
  local target_ip="$2"
  shift 2

  local dry_run=false
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --dry-run) dry_run=true; shift ;;
      *) fail "Unknown option: $1" ;;
    esac
  done

  local host="${subdomain}.${DOMAIN}"
  local zone="$DOMAIN"

  info "DNS record: ${host} → ${target_ip}"

  # Check for GoDaddy credentials
  local env_file="$ROOT_DIR/.env.godaddy"
  if [[ -f "$env_file" ]]; then
    set -a && source "$env_file" && set +a
  fi

  if [[ -n "${GODADDY_API_KEY:-}" && -n "${GODADDY_API_SECRET:-}" ]]; then
    info "GoDaddy credentials found — executing API call..."

    if [[ "$dry_run" == true ]]; then
      info "[dry-run] PUT /v1/domains/${zone}/records/A/${subdomain}"
      info "Payload: [{\"data\":\"${target_ip}\",\"ttl\":600}]"
      return 0
    fi

    local http_code
    http_code=$(curl -sS -o /tmp/godaddy-dns-response.txt -w '%{http_code}' -X PUT \
      -H "Authorization: sso-key ${GODADDY_API_KEY}:${GODADDY_API_SECRET}" \
      -H "Content-Type: application/json" \
      "https://api.godaddy.com/v1/domains/${zone}/records/A/${subdomain}" \
      -d "[{\"data\":\"${target_ip}\",\"ttl\":600}]")

    if [[ "$http_code" != "200" ]]; then
      cat /tmp/godaddy-dns-response.txt >&2
      fail "GoDaddy API HTTP ${http_code}"
    fi

    ok "DNS record updated: ${host} → ${target_ip}"
    info "Validate: dig +short ${host} @1.1.1.1"
  else
    warn "GoDaddy credentials not found ($env_file)"
    echo ""
    echo -e "${YELLOW}Manual steps:${NC}"
    echo "  1. Go to https://dcc.godaddy.com/control/dnor.io/dns"
    echo "  2. Add A record: ${subdomain} → ${target_ip} (TTL: 600)"
    echo ""
    echo -e "${YELLOW}Or set credentials in .env.godaddy:${NC}"
    echo "  GODADDY_API_KEY=your_key"
    echo "  GODADDY_API_SECRET=your_secret"
  fi
}

# ─── MAIN ──────────────────────────────────────────────────────────────────────
if [[ $# -lt 1 ]]; then
  usage
  exit 1
fi

command="$1"
shift

case "$command" in
  create)
    [[ $# -ge 3 ]] || fail "Usage: $0 create <subdomain> <svc-name> <svc-port> [--namespace NS]"
    cmd_create "$@"
    ;;
  delete)
    [[ $# -ge 1 ]] || fail "Usage: $0 delete <subdomain>"
    cmd_delete "$@"
    ;;
  list)
    cmd_list
    ;;
  validate)
    [[ $# -ge 1 ]] || fail "Usage: $0 validate <subdomain>"
    cmd_validate "$@"
    ;;
  dns)
    [[ $# -ge 2 ]] || fail "Usage: $0 dns <subdomain> <target-ip> [--dry-run]"
    cmd_dns "$@"
    ;;
  -h|--help)
    usage
    ;;
  *)
    fail "Unknown command: $command"
    ;;
esac
