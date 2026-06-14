# T-305: OCI logrotate rsyslog-aggressive duplicado em IaC/TUI

- **Status**: Done
- **Priority**: 🚨 Critical
- **Epic/Owner**: Cursor / AI Radar
- **Estimation**: 4h

## Context

A varredura encontrou `logrotate.service` falhando nos 4 nós OCI. No master, o erro é explícito:

```text
error: rsyslog-aggressive:2 duplicate log entry for /var/log/syslog
error: rsyslog-aggressive:2 duplicate log entry for /var/log/auth.log
error: rsyslog-aggressive:2 duplicate log entry for /var/log/kern.log
```

Isso quebra a camada de hardening criada para evitar crescimento de logs e pode reabrir risco de DiskPressure. A correção precisa remover a duplicidade com a configuração padrão do sistema, aplicar em todos os nós e codificar a fonte em IaC/TUI.

Arquivos/caminhos candidatos:

- `oci-k8s-cluster/scripts/hardening/`
- `oci-k8s-cluster/k8s_ops_menu.sh`
- docs/runbooks de hardening e storage

## Tasks

- [x] Comparar `/etc/logrotate.d/rsyslog` e `/etc/logrotate.d/rsyslog-aggressive` em master + workers.
- [x] Decidir padrão: substituir `/etc/logrotate.d/rsyslog` e remover `rsyslog-aggressive` + `.bak` fora de `logrotate.d`.
- [x] Implementar `scripts/hardening/repair_logrotate_rsyslog.sh` idempotente com `--dry-run`.
- [x] Expor na TUI (Hardening → Validate/Repair logrotate rsyslog T-305).
- [x] Aplicar nos 4 nós OCI — master + workers OK (workers via IP público OCI 2026-06-09; `logrotate` inactive, sem duplicate).
- [x] Rodar `logrotate -d` e `systemctl reset-failed logrotate.service` no master.
- [x] Integrar em `configure_log_limits.sh` (chama repair script).

## Validação

```bash
ssh oci-k8s-master "sudo logrotate -d /etc/logrotate.conf"
for n in oci-k8s-master oci-k8s-node-1 oci-k8s-node-2 oci-k8s-node-3; do
  ssh "$n" "systemctl is-failed logrotate.service; sudo logrotate -d /etc/logrotate.conf >/tmp/logrotate.debug 2>&1; echo $?"
done
```

Critério de aceite: `logrotate.service` não falha em nenhum nó, script/TUI idempotente e runbook atualizado.
