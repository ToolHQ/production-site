# T-277: Remove Rootless BuildKit from Cluster Nodes

- **Status**: Done
- **Priority**: 🔼 High
- **Epic/Owner**: Antigravity
- **Estimation**: 2h

## Context

Com a migração do fluxo de build de imagens para uma instância externa dedicada na Hetzner, o BuildKit rootless rodando localmente nos nodes do cluster OCI (especialmente nos nodes 2 e 3) tornou-se obsoleto. Além disso, ele estava gerando erros recorrentes nos logs do systemd (`Active: failed`), degradando a observabilidade e consumindo recursos desnecessários.

Esta tarefa consistiu em:
1. Remover toda a lógica de inicialização e configuração do rootless BuildKit do script de provisionamento da infraestrutura: [setup_k8s_cluster.sh](file:///home/dnorio/production-site-antigravity/oci-k8s-cluster/setup_k8s_cluster.sh).
2. Adicionar uma etapa de limpeza nuclear (`NUCLEAR`) ao script de recuperação do cluster: [full_cluster_heal.sh](file:///home/dnorio/production-site-antigravity/oci-k8s-cluster/full_cluster_heal.sh) para parar, desabilitar e apagar completamente todos os serviços, binários, configurações e namespaces CNI/ghost órfãos do BuildKit em todos os nodes.
3. Executar o script de heal e validar a remoção completa.

## Tasks

- [x] Remover configuração do BuildKit rootless de `setup_k8s_cluster.sh`
- [x] Adicionar o passo de limpeza nuclear de BuildKit no `full_cluster_heal.sh`
- [x] Executar `full_cluster_heal.sh` para purgar o BuildKit de todos os nodes
- [x] Validar que o serviço `buildkit.service` não existe mais e os erros cessaram

## Validação

O script de heal foi executado e todas as operações foram concluídas com sucesso. O DNS e todos os nodes estão verdes:
- Comando de verificação nos nodes:
  `for n in oci-k8s-master oci-k8s-node-1 oci-k8s-node-2 oci-k8s-node-3; do ssh $n "systemctl --user status buildkit.service"; done`
- Resultado:
  `Unit buildkit.service could not be found.` em todos os nodes.

