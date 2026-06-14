# T-309: OCI ingress LoadBalancer pending decisão arquitetural

- **Status**: Done
- **Priority**: 🔼 High
- **Epic/Owner**: Cursor / AI Radar
- **Estimation**: 4h

## Context

O `ingress-nginx-controller` no OCI aparece como `type=LoadBalancer` com `EXTERNAL-IP <pending>`, enquanto a arquitetura atual documentada usa DNS público round-robin nos workers + Security List restrita + `hostNetwork` nos workers + Tailscale overlay.

O estado funciona, mas o `LoadBalancer <pending>` cria ruído operacional e pode confundir agentes, operadores e scripts. Precisamos decidir se o Service deve continuar `LoadBalancer`, virar `ClusterIP`/`NodePort`, ou manter pending como decisão explícita documentada.

Referências:

- `docs/network-access-architecture.md`
- `components/ingress-nginx/`
- `oci-k8s-cluster/docs/ARCHITECTURE.md`
- `oci-k8s-cluster/k8s_ops_menu.sh`

## Tasks

- [ ] Mapear manifesto versionado atual do ingress-nginx e estado live.
- [ ] Confirmar requisitos dos fluxos TUI, túnel, DNS público e Tailscale.
- [ ] Avaliar opções: manter `LoadBalancer`, mudar para `ClusterIP`, mudar para `NodePort`, ou split Service para legacy/tunnel.
- [ ] Registrar decisão arquitetural com tradeoffs de custo zero, UX operacional e compatibilidade.
- [ ] Aplicar mudança em IaC se necessário, com dry-run e validação de acesso `*.dnor.io`.
- [ ] Atualizar docs para impedir regressão ao modelo antigo de túnel obrigatório.

## Validação

```bash
kubectl get svc -n ingress-nginx ingress-nginx-controller -o wide
kubectl get pods -n ingress-nginx -o wide
curl -I https://reports.dnor.io
curl -I https://coroot.dnor.io
```

Critério de aceite: estado do Service reflete a arquitetura escolhida e não gera alerta ambíguo.
