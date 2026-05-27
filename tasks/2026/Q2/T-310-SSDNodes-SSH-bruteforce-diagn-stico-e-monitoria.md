# T-310: SSDNodes SSH bruteforce diagnóstico e monitoria

- **Status**: Backlog
- **Priority**: 🔼 High
- **Epic/Owner**: Cursor / AI Radar
- **Estimation**: 1d

## Context

O host SSDNodes está saudável e sem systemd failures, mas o journal mostra várias tentativas SSH/bruteforce externas (`invalid user ftpuser`, `test1`, `test2`, `ubuntu`, `kex_exchange_identification`). O cluster SSDNodes está exposto publicamente para ingress e também roda runner GitHub Actions, MinIO/Kubecost/Dashboard.

Precisamos entender se o posture está adequado, criar monitoria objetiva e decidir se há ação de hardening adicional (fail2ban, UFW/iptables, allowlist SSH, Tailscale-only SSH, alertas).

## Tasks

- [ ] Quantificar tentativas SSH por origem, usuário, janela de tempo e tendência.
- [ ] Auditar configuração SSH: senha desabilitada, root login, pubkey, rate limiting e portas expostas.
- [ ] Auditar UFW/iptables/security posture sem quebrar ingress público necessário.
- [ ] Avaliar fail2ban ou equivalente leve, com IaC e opção na TUI/hardening.
- [ ] Criar monitoria/alerta: taxa de auth failures, top IPs, bloqueios aplicados.
- [ ] Documentar runbook de resposta e critérios para bloquear IP/range.
- [ ] Confirmar que GitHub runner e Kubernetes não dependem de SSH público amplo.

## Validação

```bash
ssh ssdnodes-monstro "journalctl -u ssh --since '24 hours ago'"
ssh ssdnodes-monstro "ss -tlnp | grep ':22'"
ssh ssdnodes-monstro "systemctl --failed --no-pager"
```

Critério de aceite: diagnóstico claro de exposição SSH, monitoria ativa e hardening versionado se necessário.
