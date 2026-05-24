#!/usr/bin/env bash
# configure-qdbback-sg.sh — Security Group para honeypot qdbback (Fase 2)
#
# Uso:
#   ./scripts/aws-fleet/configure-qdbback-sg.sh --apply
#   ./scripts/aws-fleet/configure-qdbback-sg.sh --dry-run
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

INSTANCE_ID="${INSTANCE_ID:-i-0e8ca7a9b50e474a9}"
SG_ID="${SG_ID:-sg-06a97865399016318}"
REGION="${AWS_REGION:-us-east-1}"
OPERATOR_IP="${OPERATOR_IP:-}"
DRY_RUN=false
APPLY=false

usage() {
  cat <<'EOF'
Abre portas do honeypot qdbback no Security Group da EC2.

Regras:
  :80    TCP  0.0.0.0/0        — HTTP público (redirect → HTTPS)
  :443   TCP  0.0.0.0/0        — HTTPS honeypot
  :3500  TCP  OPERATOR_IP/32   — admin HTTPS (restrito; não usar 443)

Requisitos: AWS CLI autenticado (aws sso login).

Opções:
  --instance-id i-xxx
  --operator-ip IP    (default: IP público detectado)
  --region us-east-1
  --apply
  --dry-run
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --instance-id) INSTANCE_ID="$2"; shift 2 ;;
    --operator-ip) OPERATOR_IP="$2"; shift 2 ;;
    --region) REGION="$2"; shift 2 ;;
    --apply) APPLY=true; shift ;;
    --dry-run) DRY_RUN=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) fail "Argumento desconhecido: $1" ;;
  esac
done

if [[ -z "$OPERATOR_IP" ]]; then
  OPERATOR_IP="$(curl -sf --max-time 5 ifconfig.me || curl -sf icanhazip.com || true)"
fi
[[ -n "$OPERATOR_IP" ]] || fail "Não foi possível detectar OPERATOR_IP — use --operator-ip"

SG_ID="$(aws ec2 describe-instances \
  --instance-ids "$INSTANCE_ID" \
  --region "$REGION" \
  --query 'Reservations[0].Instances[0].SecurityGroups[0].GroupId' \
  --output text 2>/dev/null)" || SG_ID="${SG_ID:-sg-06a97865399016318}"

[[ -n "$SG_ID" && "$SG_ID" != None ]] || fail "SG_ID inválido — defina SG_ID ou rode: aws sso login"

info "Security Group: $SG_ID | Operator: ${OPERATOR_IP}/32"

authorize() {
  local port="$1" cidr="$2" desc="$3"
  if [[ "$DRY_RUN" == true ]]; then
    info "[dry-run] authorize $port from $cidr ($desc)"
    return 0
  fi
  if [[ "$APPLY" != true ]]; then
    info "Planned: $port ← $cidr ($desc) — use --apply"
    return 0
  fi
  local out rc
  out="$(aws ec2 authorize-security-group-ingress \
    --region "$REGION" \
    --group-id "$SG_ID" \
    --ip-permissions "IpProtocol=tcp,FromPort=$port,ToPort=$port,IpRanges=[{CidrIp=$cidr,Description=\"$desc\"}]" 2>&1)" || rc=$?
  rc="${rc:-0}"
  if [[ "$rc" -eq 0 ]]; then
    ok "Regra $port ← $cidr ($desc)"
  elif [[ "$out" == *InvalidPermission.Duplicate* ]] || [[ "$out" == *already exists* ]]; then
    ok "Regra $port/$cidr já existe"
  elif [[ "$out" == *UnauthorizedOperation* ]]; then
    fail "Sem permissão IAM (ec2:AuthorizeSecurityGroupIngress). Adicione as regras manualmente — ver apps/qdbback/docs/SG-CONSOLE-RULES.md"
  else
    warn "Regra $port/$cidr: $out"
  fi
}

authorize 80 "0.0.0.0/0" "qdbback-http-honeypot"
authorize 443 "0.0.0.0/0" "qdbback-https-honeypot"
authorize 3500 "${OPERATOR_IP}/32" "qdbback-admin-https"

info "SG configure concluído"
