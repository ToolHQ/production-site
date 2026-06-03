# T-306: OCI health watchdog env permission e semântica de alertas

- **Status**: Done
- **Priority**: 🔼 High
- **Epic/Owner**: Cursor / AI Radar
- **Estimation**: 6h

## Context

`k8s-health-check.service` falha repetidamente no master. O script executa e gera relatório, mas retorna exit `1` por warnings. Também aparece:

```text
/opt/k8s-ops/cluster_health_check.sh: line 16: /opt/k8s-ops/watchdog.env: Permission denied
```

O relatório atual mostra warnings reais (headroom Longhorn e chain incompleta aguardando repair), mas o timer systemd fica marcado como failed. Isso reduz confiança no alarme: um warning esperado vira falha de unidade.

A correção deve ficar conectada ao source da TUI/IaC, pois o health watchdog é parte do produto de gestão do cluster.

## Tasks

- [x] Auditar owner/permissions de `/opt/k8s-ops/watchdog.env` (600 root; provisionado só no nó, não no repo).
- [x] Semântica: exit `0` para warnings, `2` para critical; `SuccessExitStatus=0 2` no unit.
- [x] `watchdog.env.example` + install com `chmod 640`; `cluster_health_check.sh` usa `-r` antes do source.
- [x] TUI Hardening opção 3 corrigida → `install_health_watchdog.sh`.
- [x] Deploy no master; `systemctl start k8s-health-check.service` → `status=0/SUCCESS`.
- [ ] Documentar matriz de severidade em runbook (follow-up curto no PR).

## Validação

```bash
ssh oci-k8s-master "/opt/k8s-ops/cluster_health_check.sh --no-color; echo exit:$?"
ssh oci-k8s-master "systemctl status k8s-health-check.service --no-pager"
ssh oci-k8s-master "systemctl list-timers | grep k8s-health-check"
```

Critério de aceite: watchdog sem `Permission denied`, timer não fica failed em warning, e falha crítica ainda retorna sinal forte.
