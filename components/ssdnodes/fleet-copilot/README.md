# Fleet Copilot — Deploy runbook

## SSDNodes (`ssdnodes-6a12f10c9ef11`)

Host dedicado @ `104.225.218.78`. SSH alias ops: `ssdnodes-6a12f10c9ef11`.

```bash
# Ollama (localhost only)
bash components/ssdnodes/install_ollama.sh --host ssdnodes-6a12f10c9ef11

# Gateway read-only (:18443 — NOT 8443, nginx-ingress uses 8443)
bash components/ssdnodes/fleet-copilot/install_fleet_ops_gateway.sh

# UFW sync
bash oci-k8s-cluster/scripts/hardening/ufw_manager.sh --host ssdnodes-6a12f10c9ef11 --apply
```

Verify:

```bash
curl -sf http://104.225.218.78:18443/health
TOKEN=$(ssh ssdnodes-6a12f10c9ef11 'sudo grep FLEET_GATEWAY_TOKEN /etc/fleet-copilot/gateway.env | cut -d= -f2')
curl -H "Authorization: Bearer $TOKEN" http://104.225.218.78:18443/ops/host/disk
```

## Ollama — modelo e warm-up (T-334 / T-335)

Variável no gateway (`/etc/fleet-copilot/gateway.env`):

```bash
FLEET_OLLAMA_MODEL=gemma3:4b   # default
# A/B alternativa (menor, às vezes mais rápido em pt-BR):
# FLEET_OLLAMA_MODEL=qwen2.5:3b
```

Após trocar: `systemctl restart fleet-ops-gateway` e `ollama pull qwen2.5:3b`.

Warm-up pós-boot (evita 1º token lento):

```bash
bash components/ssdnodes/fleet-copilot/warmup_ollama.sh
```

## API Copilot

| Rota | Descrição |
|------|-----------|
| `GET /api/fleet/copilot/status` | Gateway reachability + modelo configurado |
| `GET /api/fleet/copilot/hosts` | Inventário para UI |

Respostas **structured-first** (`fleet-manifest`, `fleet-metrics`, `fleet-structured`) não usam Ollama.

## OCI cluster (reports.dnor.io)

Com túnel kubeconfig ativo:

```bash
export KUBECONFIG=~/production-site/oci-k8s-cluster/kubeconfig_tunnel.yaml
bash components/ssdnodes/fleet-copilot/setup_fleet_copilot_secret.sh
cd apps/rs-observability-api && ./deploy.sh
```

Login (cookie 8h):

```
https://reports.dnor.io/fleet-copilot?key=<FLEET_COPILOT_LOGIN_KEY>
```

Após login → redirect para `https://reports.dnor.io/#fleet-copilot`.

UI:

- Nav **Copilot** no shell DNOR
- Teaser em **Nodes** → “Abrir Copilot”
- Presets: disco/memória, pods/ingress, SSH 24h

## Portas

| Porta | Serviço |
|-------|---------|
| 11434 | Ollama — **127.0.0.1 only**, UFW DENY |
| 18443 | fleet-ops-gateway — OCI + Tailscale allowlist |
