# T-306: OCI health watchdog env permission e semântica de alertas

- **Status**: Backlog
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

- [ ] Auditar owner/permissions de `/opt/k8s-ops/watchdog.env` e como ele é provisionado no repo.
- [ ] Definir semântica de exit code: `0` para OK/warnings tolerados, `1` apenas critical/failure ou usar `SuccessExitStatus` no unit.
- [ ] Codificar ajuste no script/unit versionado, com instalação idempotente via TUI/hardening.
- [ ] Garantir que warnings continuem visíveis sem sujar `systemctl --failed`.
- [ ] Documentar matriz de severidade: OK, warning, critical, exit codes e ações.
- [ ] Validar `systemctl status k8s-health-check.service` após execução manual e via timer.

## Validação

```bash
ssh oci-k8s-master "/opt/k8s-ops/cluster_health_check.sh --no-color; echo exit:$?"
ssh oci-k8s-master "systemctl status k8s-health-check.service --no-pager"
ssh oci-k8s-master "systemctl list-timers | grep k8s-health-check"
```

Critério de aceite: watchdog sem `Permission denied`, timer não fica failed em warning, e falha crítica ainda retorna sinal forte.
