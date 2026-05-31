# Tailscale — SSDNodes / ssdnodes-6a12f10c9ef11 (T-320e)

## Estado (2026-05-30)

- **tailscaled**: active
- **Tailscale IP**: `100.92.199.93`
- **Hostname**: `ssdnodes-6a12f10c9ef11`
- Peers visíveis: `dnorio-base`, `k8s-node-1/2/3`

## UFW (via `ufw_manager.sh --apply`)

| Origem | Portas | Uso |
|--------|--------|-----|
| `100.64.0.0/10` | 80, 443 | Ingress nginx (Tailscale clients) |
| `100.64.0.0/10` | 8443 | fleet-ops-gateway (Fleet Copilot T-321) |

## ACL recomendada (admin console Tailscale)

Restringir `:8443` no host SSDNodes a:

- Tag `tag:oci-reports` (pods rs-observability-api) **ou**
- IPs Tailscale dos nós OCI

Deny default para internet → SSDNodes:8443.

## Instalação (referência)

```bash
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up --auth-key=<KEY> --hostname=ssdnodes-6a12f10c9ef11
```

## Teste OCI → SSDNodes

```bash
# De um nó OCI com Tailscale:
curl -k --max-time 5 https://100.92.199.93:8443/health
```

Ollama **nunca** na tailnet — apenas `127.0.0.1:11434`.
