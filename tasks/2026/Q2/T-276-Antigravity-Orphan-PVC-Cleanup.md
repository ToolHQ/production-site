# T-276: Antigravity — Orphan PVC Cleanup

- **Status**: Done
- **Priority**: 🔼 High
- **Epic/Owner**: Antigravity
- **Estimation**: 1h

## Context

Durante a auditoria de volumes e consumo de disco no cluster, identificamos que o PVC `postgres-pvc` (de tamanho 2152Mi / ~2.1GB) no namespace `postgres` estava no estado `Bound` mas completamente órfão e desacoplado. O banco de dados PostgreSQL ativo roda em um StatefulSet que utiliza `volumeClaimTemplates` (gerando os PVCs `postgres-data-postgres-0` e `postgres-data-postgres-1`).

Para evitar desperdício de espaço no Longhorn e prevenir que o PVC órfão fosse recriado a cada deploy:
1. **Remoção do Manifesto**: Removemos a definição de `postgres-pvc` do arquivo `components/postgres/postgres-resources.yaml`.
2. **Atualização de Scripts**: Corrigimos os comandos de troubleshooting no arquivo [components/postgres/commands.sh](file:///home/dnorio/production-site-antigravity/components/postgres/commands.sh) para referenciar `postgres-data-postgres-0` e `postgres-data-postgres-1` em vez do PVC legado.
3. **Remoção no Cluster**: Deletamos fisicamente o PVC órfão do cluster para liberar 2.15GB de espaço físico no Longhorn.

## Tasks

- [x] Auditar todos os PVCs do cluster e mapear quais pods os montavam.
- [x] Remover a definição do PVC `postgres-pvc` em [components/postgres/postgres-resources.yaml](file:///home/dnorio/production-site-antigravity/components/postgres/postgres-resources.yaml).
- [x] Corrigir as mensagens/comandos de troubleshooting no script de deploy [components/postgres/commands.sh](file:///home/dnorio/production-site-antigravity/components/postgres/commands.sh).
- [x] Executar a deleção do PVC `postgres-pvc` no live cluster.
- [x] Re-executar o deploy do PostgreSQL para validar que a pilha funciona perfeitamente sem recriar o volume órfão.

## Validação

### Remoção do PVC no cluster
```bash
export KUBECONFIG=/home/dnorio/production-site-antigravity/oci-k8s-cluster/kubeconfig_tunnel.yaml
kubectl delete pvc -n postgres postgres-pvc
```
**Resultado**:
`persistentvolumeclaim "postgres-pvc" deleted`

### Verificação do PV associado
```bash
kubectl get pv | grep pvc-ce9a0163-c093-4cb8-a88a-2edc257ff910 || echo "Gone"
```
**Resultado**:
`Gone` (O PV e os dados físicos no Longhorn foram deletados automaticamente, liberando ~2.15GB).

### Redeploy e status do StatefulSet
Executando:
```bash
cd components/postgres && bash commands.sh
```
**Resultado**:
- O StatefulSet foi atualizado e reiniciado com sucesso.
- `postgres-0` e `postgres-1` estão `Running` e `1/1` saudáveis.
- Nenhum PVC `postgres-pvc` foi recriado.
