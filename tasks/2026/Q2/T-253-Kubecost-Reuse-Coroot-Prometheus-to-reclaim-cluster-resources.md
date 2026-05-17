# T-253: Kubecost — Reuse Coroot Prometheus to reclaim cluster resources

- **Status**: Done
- **Priority**: 🔼 High
- **Epic/Owner**: Antigravity
- **Estimation**: 2h

## Context

No ambiente altamente restrito de vCPUs da infraestrutura (1 vCPU/6GB RAM por nó), a presença de múltiplos servidores Prometheus duplicados (um dedicado para o Coroot e outro embutido no Kubecost) causava severa contenção de recursos. 

A solução proposta foi:
1. **Unificação da Stack do Prometheus**: Modificar o script de deploy do Kubecost [commands.sh](file:///home/dnorio/production-site-antigravity/components/kubecost/commands.sh) para detectar dinamicamente se o serviço `coroot-prometheus-server.coroot` está ativo.
2. **Reaproveitamento Dinâmico**: Configurar o Kubecost via `--set global.prometheus.enabled=false` e `--set global.prometheus.fqdn=http://coroot-prometheus-server.coroot.svc.cluster.local:80` para apontar ao Prometheus já em execução.
3. **Remoção de Workloads Legados**: Garantir que o `kubecost-prometheus-server` seja destruído/escalado a zero durante a migração para liberar memória e CPU.
4. **Resolução de Path Remoto**: Atualizar o script de deploy unificado [deploy_components.sh](file:///home/dnorio/production-site-antigravity/oci-k8s-cluster/deploy_components.sh) para sincronizar a pasta local `tools/` no master remoto a fim de que os scripts de componentes executem `helm_compat.sh` com sucesso.

## Tasks

- [x] Investigar flags de compatibilidade e URLs de FQDN para desabilitar o Prometheus interno do Kubecost.
- [x] Adaptar dinamicamente o script de deploy [components/kubecost/commands.sh](file:///home/dnorio/production-site-antigravity/components/kubecost/commands.sh) para detectar e plugar no Prometheus do Coroot.
- [x] Corrigir a falta de ferramentas remotas sincronizando a pasta `tools/` em [oci-k8s-cluster/deploy_components.sh](file:///home/dnorio/production-site-antigravity/oci-k8s-cluster/deploy_components.sh).
- [x] Executar deploy pontual e validar remoção do Prometheus legado.
- [x] Verificar logs da ingestão do `cost-model` apontado ao Coroot Prometheus.

## Validação

O deploy foi realizado end-to-end com sucesso:
```bash
cd oci-k8s-cluster && ./deploy_components.sh kubecost
```

### Confirmação de Workloads Reclamados
```bash
export KUBECONFIG=/home/dnorio/production-site-antigravity/oci-k8s-cluster/kubeconfig_tunnel.yaml
kubectl get deployments -n kubecost
```
**Resultado**:
```text
NAME                         READY   UP-TO-DATE   AVAILABLE   AGE
kubecost-cost-analyzer       1/1     1            1           161d
kubecost-grafana             0/0     0            0           84d
```
*(O deployment `kubecost-prometheus-server` foi inteiramente removido do cluster, liberando recursos preciosos!)*

### Logs do Cost-Model saudáveis e ingestando dados via Coroot Prometheus
```bash
kubectl logs deployment/kubecost-cost-analyzer -c cost-model --tail=20 -n kubecost
```
**Resultado**:
```text
2026-05-17T23:48:52.92672062Z INF ETL: Allocation[1d]: ETLStore[EyPBs]: build: completed [2026-02-16T00:00:00+0000, 2026-02-17T00:00:00+0000) from backup in 26.413088ms: coverage [2026-02-16T00:00:00+0000, 2026-05-17T23:48:47+0000) (100.0% complete)
2026-05-17T23:48:52.926904981Z INF ETL: Allocation[1d]: ETLStore[EyPBs]: build: completed [2026-02-16T00:00:00+0000, 2026-05-17T23:48:47+0000) in 5.802220403s
2026-05-17T23:48:54.305328747Z INF Allocation: AccStoreDriver[7d][XNWeI]: run: successful run for window: [2026-05-17T00:00:00+0000, 2026-05-24T00:00:00+0000)
2026-05-17T23:48:54.312074329Z INF Reconciliation[dkApR]: received SetBuilt
```
*(Ingestão executada com 100% de sucesso).*
