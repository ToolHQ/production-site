# T-320: Fleet Copilot — Pré-requisitos de segurança (gate de deploy)

- **Status**: In Progress (gate aplicado 2026-05-30)
- **Priority**: 🚨 Critical (bloqueador)
- **Owner**: Cursor / AI Radar
- **Epic**: Fleet Copilot / SSDNodes / reports.dnor.io
- **Est**: 3d (320a–320e)
- **Depends on**: Nenhum (primeiro epic da cadeia)
- **Blocks**: T-321, T-322, T-323, T-324

## Context

Planejamento de um **Fleet Copilot** read-only: chat em `reports.dnor.io` que consulta o host `ssdnodes-monstro` via gateway determinístico + Ollama local (zero custo variável).

**Este epic não entrega o chat.** Ele fecha buracos de segurança que tornariam perigoso expor qualquer endpoint POST/LLM:

| Risco hoje | Impacto |
|------------|---------|
| `reports.dnor.io` sem auth na app | Qualquer IP whitelisted na OCI SL vê dados de cluster + futuro proxy LLM |
| SSH `:22` aberto ao mundo no monstro | Bruteforce contínuo (T-310) |
| Runner CodeQL no mesmo host que MinIO/Dashboard `cluster-admin` | Lateral movement se job malicioso |
| Ollama/Hermes no mesmo kernel sem isolamento | Execução arbitrária + exfil |
| Rede OCI↔monstro só por IP público | Superfície ampla; preferir Tailscale + ACL |

**Gate:** nenhum deploy de Ollama, gateway ou `/api/fleet/chat` até **T-320a + T-320b + T-320e** marcados Done.

Referências:

- `docs/network-access-architecture.md`
- `oci-k8s-cluster/scripts/hardening/ufw_manager.sh`
- `apps/qdbback/services/monitorAuth.js` (padrão login key)
- `config/external-fleet/registry.yaml` (`oci_k8s_public_ips`)
- Epic pai: T-321…T-324

---

## Arquitetura alvo (contexto)

```
Operador → reports.dnor.io (auth cookie)
         → rs-observability-api (rate limit)
         → Tailscale/mTLS → fleet-ops-gateway @ monstro
         → comandos hardcoded read-only
         → Ollama 127.0.0.1 (síntese local, nunca exposto ao browser)
```

---

## T-320a — SSH hardening + fail2ban (extends T-310)

- **Est**: 1d
- **Owner**: Cursor / AI Radar
- **Relacionado**: [T-310](T-310-SSDNodes-SSH-bruteforce-diagn-stico-e-monitoria.md)

### Objetivo

Quantificar brute force, endurecer `sshd`, adicionar fail2ban versionado e confirmar que runner/K8s **não** dependem de SSH `:22` público amplo.

### Checklist

- [x] Baseline 7 dias: **~79.135** eventos SSH failed/invalid user (2026-05-30)
- [x] Auditar `/etc/ssh/sshd_config`:
  - [x] `PasswordAuthentication no` (drop-in `99-fleet-copilot-hardening.conf`)
  - [x] `PermitRootLogin prohibit-password`
  - [x] `PubkeyAuthentication yes`
  - [x] `MaxAuthTries 4`
- [x] Confirmar runner GitHub outbound-only — documentado em ADR T-320c
- [x] Instalar fail2ban (jail `sshd`, bantime 24h) — `fail2ban_ssdnodes.sh --apply`
- [ ] Alerta Prometheus auth failures (backlog opcional)

### Arquivos a criar/alterar

| Path | Ação |
|------|------|
| `oci-k8s-cluster/scripts/hardening/fail2ban_ssdnodes.sh` | Novo — install + jail sshd |
| `oci-k8s-cluster/scripts/hardening/ufw_manager.sh` | Opcional — tier SSH restrito |
| `components/ssdnodes/README.md` | Documentar posture SSH pós-hardening |
| `tasks/2026/Q2/T-310-*.md` | Cross-link; marcar overlap Done quando 320a fechar |

### Validação

```bash
ssh ssdnodes-monstro "sudo sshd -T | grep -E 'passwordauthentication|permitrootlogin|maxauthtries'"
ssh ssdnodes-monstro "sudo fail2ban-client status sshd"
ssh ssdnodes-monstro "journalctl -u ssh --since '1 hour ago' | tail -20"
```

### DoD

- Relatório de brute force (top 10 IPs, tendência)
- fail2ban active + pelo menos 1 ban de teste em lab ou simulação documentada
- Runbook em `components/ssdnodes/` ou `apps/qdbback/docs`-style para resposta a incidente SSH

---

## T-320b — UFW alinhado + node-exporter 9100 allowlist OCI

- **Est**: 4h

### Objetivo

Garantir que o posture **restritivo** do `ufw_manager.sh` está aplicado no monstro e que scrape Prometheus `:9100` segue o mesmo padrão da fleet AWS (só IPs OCI).

### Checklist

- [x] Confirmar no host: `ufw status verbose` alinhado ao IaC
- [x] Aplicar `ufw_manager.sh --host ssdnodes-monstro --apply`
- [x] Regras **9100/tcp** → IPs OCI (`METRICS_IPS` no script)
- [x] **Deny** 11434/tcp (Ollama localhost only)
- [x] Allow **8443** Tailscale + INGRESS (fleet-ops-gateway futuro)
- [x] Alinhar `components/ssdnodes/README.md`
- [x] Validar `cert-renew-ufw.timer` (documentado)

### Arquivos a criar/alterar

| Path | Ação |
|------|------|
| `oci-k8s-cluster/scripts/hardening/ufw_manager.sh` | Regras 9100 + comentários |
| `components/ssdnodes/README.md` | Matriz portas bootstrap vs hardened |
| `config/external-fleet/registry.yaml` | Fonte de IPs (já existe) |

### Validação

```bash
ssh ssdnodes-monstro "sudo ufw status numbered"
# De OCI worker (ou simular):
curl -s --max-time 3 http://104.225.218.78:9100/metrics | head -3
# De IP não allowlisted → timeout/refused
```

### DoD

- 9100 acessível só de IPs OCI documentados
- README reflete estado real pós-`ufw_manager --apply`

---

## T-320c — Decisão runner CodeQL vs AI no mesmo host

- **Est**: 4h

### Objetivo

Documentar blast radius e escolher **uma** estratégia antes de Ollama no monstro.

### Opções (escolher uma — registrar ADR)

| Opção | Prós | Contras |
|-------|------|---------|
| **A — Mover runner off-box** | Melhor isolamento | Precisa outro x86_64 ou voltar CodeQL para Hetzner/ubuntu |
| **B — Runner em VM/container dedicado no monstro** | Mesmo hardware | Complexidade ops |
| **C — Aceitar risco + NetworkPolicy K8s para AI pods** | Rápido | Kernel compartilhado com runner |
| **D — Pausar CodeQL self-hosted no monstro** | Simples | Perde diagnóstico JS/Python no hardware local |

### Checklist

- [x] Inventariar workflows CodeQL → `ssdnodes`
- [x] ADR mergeado: [ADR-runner-ai-colocation.md](../../../components/ssdnodes/ADR-runner-ai-colocation.md) — **Opção C**

### DoD

- ADR mergeado com decisão explícita A/B/C/D
- Se opção C: checklist de NetworkPolicy incluído em T-321

---

## T-320d — Kubernetes Dashboard SSDNodes: RBAC view-only

- **Est**: 4h

### Objetivo

Remover `cluster-admin` do ServiceAccount `admin-user` usado pelo Dashboard em `k8s.ssdnodes.dnor.io`.

### Checklist

- [x] Auditar `deploy_ssdnodes_components.sh` — era `cluster-admin`
- [x] ClusterRoleBinding → **`view`**
- [x] Script `patch_dashboard_view_rbac.sh --apply` aplicado no cluster live
- [x] TUI opção 14

### Arquivos a alterar

| Path | Ação |
|------|------|
| `oci-k8s-cluster/scripts/ssdnodes/deploy_ssdnodes_components.sh` | RBAC mínimo |
| `components/ssdnodes/kubernetes-dashboard-values.yaml` | Se aplicável |
| `tasks/2026/Q2/T-303-*.md` | Nota de follow-up segurança |

### Validação

```bash
kubectl auth can-i delete pods --all-namespaces --as=system:serviceaccount:kubernetes-dashboard:admin-user
# Esperado: no
kubectl auth can-i get pods --all-namespaces --as=system:serviceaccount:kubernetes-dashboard:admin-user
# Esperado: yes
```

### DoD

- SA sem `cluster-admin`
- Dashboard ainda abre com token read-only

---

## T-320e — Tailscale mesh monstro ↔ OCI + ACL Fleet Copilot

- **Est**: 4h

### Objetivo

Canal privado OCI → monstro para `fleet-ops-gateway` sem depender de expor nova porta LLM na internet pública.

### Checklist

- [x] Tailscale active no monstro (`100.92.199.93`)
- [x] UFW allow `100.64.0.0/10` → 80, 443, 8443
- [x] Documentado em [tailscale-setup.md](../../../components/ssdnodes/tailscale-setup.md)
- [ ] ACL Tailscale admin console (manual)

### Arquivos a criar

| Path | Ação |
|------|------|
| `components/ssdnodes/tailscale-setup.md` | Runbook install + ACL |
| `oci-k8s-cluster/scripts/ssdnodes/install_tailscale.sh` | Script idempotente (opcional) |

### Validação

```bash
# De pod rs-observability-api ou jump OCI:
curl -k --max-time 5 https://<monstro-ts-ip>:8443/health
# Ollama NÃO deve responder de fora do host:
curl --max-time 3 http://104.225.218.78:11434/api/tags
# Esperado: timeout/refused
```

### DoD

- Conectividade OCI→monstro via Tailscale testada
- Ollama inacessível externamente (port scan documentado)

---

## Critérios de aceite (epic T-320)

- [x] T-320a, T-320b, T-320e concluídos (gate) — **2026-05-30**
- [x] T-320c ADR mergeado
- [x] T-320d Dashboard sem cluster-admin
- [x] Runbook: [FLEET-COPILOT-SECURITY-PREREQS.md](../../../components/ssdnodes/FLEET-COPILOT-SECURITY-PREREQS.md)

## Sequência

```
T-320a ─┐
T-320b ─┼─► GATE ─► T-321
T-320e ─┘
T-320c ─── (paralelo, decisão documentada)
T-320d ─── (paralelo, recomendado antes de T-321)
```
