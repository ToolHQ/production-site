# T-303: SSDNodes — Kubernetes Dashboard + Kubecost HTTPS

- **Status**: ✅ Done
- **Priority**: 🔵 Medium
- **Owner**: Copilot/VSCode
- **Epic**: Infra / ssdnodes-monstro
- **Est**: 2h
- **Criado**: 2026-05-25
- **Concluído**: 2026-05-26

## Objetivo

Expor via HTTPS dois painéis de observabilidade/custos no ssdnodes-monstro:

| Subdomínio | Serviço | Porta |
|---|---|---|
| `k8s.ssdnodes.dnor.io` | Kubernetes Dashboard | 443 |
| `cost.ssdnodes.dnor.io` | Kubecost (Free Tier) | 443 |

TLS via cert-manager (HTTP-01, ClusterIssuer `letsencrypt-prod` já provisionado).

## Resultado

- `https://k8s.ssdnodes.dnor.io` → HTTP 200 ✅ (TLS Let's Encrypt R12, issuer CN=R12)
- `https://cost.ssdnodes.dnor.io` → HTTP 200 ✅ (TLS Let's Encrypt R13)
- Chart: `kubernetes-dashboard-7.14.0.tgz` (kubernetes-retired/dashboard — GitHub Pages fora do ar)
- Kubecost: `2.8.6` (2.9.x é migration-only para 3.0)
- Prometheus + Grafana bundled no kubecost (necessário para o frontend nginx)

## Pré-requisitos

- [x] nginx-ingress DaemonSet hostNetwork rodando (port 80/443)
- [x] cert-manager + ClusterIssuers letsencrypt-prod/staging
- [x] cert-renew-ufw: abre porta 80 temporariamente na renovação
- [x] DNS: `k8s.ssdnodes.dnor.io` → 104.225.218.78
- [x] DNS: `cost.ssdnodes.dnor.io` → 104.225.218.78

## Tasks

- [ ] Criar registros A no DNS (k8s + cost → 104.225.218.78)
- [ ] Deploy Kubernetes Dashboard (helm `kubernetes-dashboard`, namespace `kubernetes-dashboard`)
- [ ] Criar ServiceAccount + ClusterRoleBinding para acesso read-only
- [ ] Criar Ingress `k8s-dashboard-ingress.yaml` com TLS cert-manager
- [ ] Deploy Kubecost Free (helm `cost-analyzer`, namespace `kubecost`)
- [ ] Criar Ingress `kubecost-ingress.yaml` com TLS cert-manager
- [ ] Adicionar manifestos em `components/ssdnodes/`
- [ ] Validar: curl HTTPS + browser nos dois domínios

## Critérios de Aceite

- [ ] `https://k8s.ssdnodes.dnor.io` abre o Kubernetes Dashboard (TLS válido)
- [ ] `https://cost.ssdnodes.dnor.io` abre o Kubecost (TLS válido)
- [ ] Certificados Let's Encrypt READY para ambos
- [ ] Sem impacto no MinIO existente (minio/s3.ssdnodes.dnor.io)

## Manifests

Todos os manifests em `components/ssdnodes/`:
- `kubernetes-dashboard-values.yaml`
- `kubernetes-dashboard-ingress.yaml`
- `kubecost-values.yaml`
- `kubecost-ingress.yaml`
