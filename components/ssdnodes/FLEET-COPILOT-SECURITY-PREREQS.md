# Fleet Copilot — Security prerequisites (T-320)

Gate **obrigatório** antes de deploy Ollama / `/api/fleet/chat`.

## Checklist

| ID | Item | Script / ação |
|----|------|----------------|
| T-320a | SSH hardening + fail2ban | `ssh_harden_ssdnodes.sh --apply`, `fail2ban_ssdnodes.sh --apply` |
| T-320b | UFW 9100 OCI + deny 11434 | `ufw_manager.sh --host ssdnodes-monstro --apply` |
| T-320c | ADR runner colocation | [ADR-runner-ai-colocation.md](ADR-runner-ai-colocation.md) |
| T-320d | Dashboard view-only RBAC | `patch_dashboard_view_rbac.sh --apply` |
| T-320e | Tailscale mesh | [tailscale-setup.md](tailscale-setup.md) |

## Tailscale (T-320e)

Monstro: `100.92.199.93` (`ssdnodes-6a12f10c9ef11`)

UFW allow `100.64.0.0/10` → 80, 443, 8443 (fleet-ops-gateway futuro).

## Validação rápida

```bash
# SSH posture
ssh ssdnodes-monstro "sudo sshd -T | grep -E 'passwordauthentication|permitrootlogin'"

# fail2ban
bash oci-k8s-cluster/scripts/hardening/fail2ban_ssdnodes.sh --host ssdnodes-monstro --status

# Ollama não público (antes e depois do deploy)
curl --max-time 3 http://104.225.218.78:11434/api/tags  # deve falhar

# Dashboard não cluster-admin
kubectl auth can-i delete pods --all-namespaces \
  --as=system:serviceaccount:kubernetes-dashboard:admin-user  # no
```

## Evidência T-320 (2026-05-30)

- SSH 7d brute force attempts: **~79k** (Invalid user / Failed password)
- Pré-hardening: `PasswordAuthentication yes`, `PermitRootLogin yes`
- UFW host já tinha 9100 OCI + Tailscale ingress (drift corrigido no IaC `ufw_manager.sh`)
- Tailscale: **active** no monstro
