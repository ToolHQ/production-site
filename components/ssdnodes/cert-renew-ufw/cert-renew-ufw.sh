#!/usr/bin/env bash
# cert-renew-ufw — Abre porta 80 durante renovação HTTP-01 do cert-manager,
# fecha logo após todos os certificados ficarem Ready.
# Executado diariamente via systemd timer (cert-renew-ufw.timer).
#
# Lógica:
#   1. Se nenhum cert precisar de renovação (todos Ready + >35 dias) → sai sem fazer nada
#   2. Abre porta 80 via ufw (temporariamente)
#   3. Aguarda cert-manager concluir HTTP-01 e todos os certs ficarem Ready
#   4. Fecha porta 80 (via trap EXIT — fecha mesmo em caso de erro)

set -euo pipefail

readonly TIMEOUT_SECONDS=900      # 15 min máximo com porta 80 aberta
readonly RENEW_THRESHOLD_DAYS=35  # Abrir se cert expira em menos de N dias
readonly KUBECONFIG="${KUBECONFIG:-/root/.kube/config}"
export KUBECONFIG

log()  { logger -t "cert-renew-ufw" -- "$*";         echo "$(date -Iseconds) INFO  $*"; }
err()  { logger -t "cert-renew-ufw" -p user.err -- "ERROR: $*"; echo "$(date -Iseconds) ERROR $*" >&2; }

# ─────────────────────────────────────────────────────────────────────────────
port80_open() {
    # Adiciona regra somente se ainda não existir
    if ! ufw status | grep -qP '^80/tcp\s+ALLOW IN\s+Anywhere'; then
        ufw allow 80/tcp comment "cert-renew-temp" >/dev/null
        log "Porta 80 aberta (temporária)"
    else
        log "Porta 80 já estava aberta"
    fi
}

port80_close() {
    # Deleta apenas a regra genérica "allow 80/tcp" — não afeta as regras
    # ip-específicas (from IP to any port 80) dos ADMIN_IPS/INGRESS_IPS.
    ufw delete allow 80/tcp >/dev/null 2>&1 || true
    log "Porta 80 fechada"
}

# ─────────────────────────────────────────────────────────────────────────────
# Retorna 0 (precisa renovar) se:
#   - algum cert tiver READY = False, ou
#   - algum cert expirar em menos de RENEW_THRESHOLD_DAYS dias
needs_renewal() {
    # Certs não-Ready
    local not_ready
    not_ready=$(kubectl get certificate -A --no-headers 2>/dev/null \
        | awk '{print $3}' | grep -c "^False$" || echo "0")
    if [[ "$not_ready" -gt 0 ]]; then
        log "Certificados Not Ready: ${not_ready}"
        return 0
    fi

    # Certs com expiração próxima
    local threshold_epoch
    threshold_epoch=$(date -d "+${RENEW_THRESHOLD_DAYS} days" +%s)

    while IFS= read -r not_after; do
        [[ -z "$not_after" ]] && continue
        local cert_epoch
        cert_epoch=$(date -d "$not_after" +%s 2>/dev/null || echo "0")
        if [[ "$cert_epoch" -lt "$threshold_epoch" ]]; then
            log "Cert expira em breve: ${not_after}"
            return 0
        fi
    done < <(kubectl get certificate -A \
        -o jsonpath='{range .items[*]}{.status.notAfter}{"\n"}{end}' 2>/dev/null)

    return 1
}

# ─────────────────────────────────────────────────────────────────────────────
wait_all_ready() {
    local deadline=$(( $(date +%s) + TIMEOUT_SECONDS ))

    while [[ $(date +%s) -lt $deadline ]]; do
        local not_ready
        not_ready=$(kubectl get certificate -A --no-headers 2>/dev/null \
            | awk '{print $3}' | grep -c "^False$" || echo "0")

        if [[ "${not_ready}" -eq 0 ]]; then
            log "Todos os certificados estão Ready ✓"
            return 0
        fi

        local mins_left=$(( (deadline - $(date +%s)) / 60 ))
        log "Aguardando ${not_ready} certificado(s)... (${mins_left}min restantes)"
        sleep 30
    done

    err "Timeout: certificados não renovados em ${TIMEOUT_SECONDS}s"
    return 1
}

# ─────────────────────────────────────────────────────────────────────────────
main() {
    log "=== cert-renew-ufw: verificando certificados ==="

    if ! needs_renewal; then
        log "Todos os certificados OK. Nenhuma renovação necessária."
        exit 0
    fi

    log "Renovação necessária — abrindo porta 80 temporariamente..."
    trap 'port80_close' EXIT INT TERM
    port80_open

    if wait_all_ready; then
        log "=== Renovação concluída com sucesso ==="
    else
        err "=== Renovação falhou — porta 80 será fechada mesmo assim ==="
        exit 1
    fi
}

main "$@"
