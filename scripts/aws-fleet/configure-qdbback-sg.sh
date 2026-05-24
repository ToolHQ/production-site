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
REGION="${AWS_REGION:-us-east-1}"
OPERATOR_IP="${OPERATOR_IP:-}"
DRY_RUN=false
APPLY=false

usage() {
  cat <<'EOF'
Abre portas do honeypot qdbback no Security Group da EC2.

Regras:
  :3000  TCP  0.0.0.0/0        — HTTP público (redirect)
  :3443  TCP  0.0.0.0/0        — HTTPS honeypot
  :3500  TCP  OPERATOR_IP/32   — admin HTTPS (restrito)

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
  --output text 2>/dev/null)" || fail "AWS CLI falhou — rode: aws sso login"

log "Security Group: $SG_ID | Operator: ${OPERATOR_IP}/32"

authorize() {
  local port="$1" cidr="$2" desc="$3"
  if [[ "$DRY_RUN" == true ]]; then
    log "[dry-run] authorize $port from $cidr ($desc)"
    return 0
  fi
  if [[ "$APPLY" != true ]]; then
    log "Planned: $port ← $cidr ($desc) — use --apply"
    return 0
  fi
  aws ec2 authorize-security-group-ingress \
    --region "$REGION" \
    --group-id "$SG_ID" \
    --ip-permissions "IpProtocol=tcp,FromPort=$port,ToPort=$port,IpRanges=[{CidrIp=$cidr,Description=\"$desc\"}]" \
    2>/dev/null || log "Regra $port/$cidr já existe ou conflito ignorado"
}

authorize 3000 "0.0.0.0/0" "qdbback-http-honeypot"
authorize 3443 "0.0.0.0/0" "qdbback-https-honeypot"
authorize 3500 "${OPERATOR_IP}/32" "qdbback-admin-https"

log "SG configure concluído"
