# Runbook Operacional — Triagem e Mitigação de Baixo Headroom de Disco no Longhorn

## 1. Visão Geral

O Longhorn armazena os dados das réplicas dos volumes Persistent Volume Claims (PVCs) no caminho `/var/lib/longhorn` de cada nó do cluster Kubernetes.
*   **Headroom Físico**: Espaço livre real no sistema de arquivos do nó (`storageAvailable` do CRD `nodes.longhorn.io`).
*   **Thresholds Operacionais**:
    *   **Warning (< 15 GiB)**: Indica risco de aproximação do limite de pressão. Ações de limpeza e consolidação de snapshots são recomendadas.
    *   **Critical (< 10 GiB)**: Risco iminente de `DiskPressure` no nó pelo Kubernetes (que causa despejo de Pods e congelamento de gravação do Longhorn). Requer ação imediata.

---

## 2. Diagnóstico Rápido

Para identificar quais nós e volumes estão consumindo o headroom físico:

```bash
# Verificar status do headroom de disco no Longhorn por nó
kubectl get node.longhorn.io -n longhorn-system -o json | jq -r '.items[] | [.metadata.name, (.spec.disks | to_entries[0].value.allowScheduling | tostring), ((.status.diskStatus | to_entries[0].value.storageAvailable | tonumber) / 1024 / 1024 / 1024 | tostring) + " GB free"] | @tsv'

# Listar os volumes Longhorn e seus tamanhos reais em disco
kubectl get volumes.longhorn.io -n longhorn-system -o custom-columns=NAME:.metadata.name,ROBUSTNESS:.status.robustness,SIZE_GB:.spec.size,ACTUAL_SIZE_GB:.status.actualSize
```

---

## 3. Fluxo de Triagem e Remediação

Siga os passos abaixo, do menor para o maior impacto, para liberar espaço físico nos nós afetados.

### Passo 1: Limpeza de Logs e Caches Locais (Não Destrutivo, Rápido)
Se o nó com baixo headroom estiver sofrendo com arquivos temporários, logs do systemd ou caches de build obsoletos, execute o script de limpeza local:

1. Acesse a TUI operando o script `./k8s_ops_menu.sh`
2. Navegue até `Maintenance` -> `Prune Disk Space (Images/Logs)`
3. *Ou execute diretamente via terminal*:
   ```bash
   ssh <nome-do-nó> "sudo /usr/local/bin/clean_node.sh --deep"
   ```

### Passo 2: Pruning de Snapshots Antigos do Longhorn
Snapshots do Longhorn retêm estados passados e podem inflar o espaço em disco de um volume muito além do seu tamanho lógico.

1. Identifique se o volume correspondente possui muitos snapshots acumulados:
   ```bash
   kubectl get snapshots.longhorn.io -n longhorn-system -l longhornvolume=<volume-uuid>
   ```
2. Para expurgar snapshots antigos de forma segura mantendo apenas o estado atual ativo, você pode iniciar o prune do volume. Isso instruirá o Longhorn a consolidar a cadeia de snapshots em disco de volta para o bloco ativo:
   *   O Longhorn consolida snapshots automaticamente quando os Jobs Recorrentes configurados via IaC rodam.
   *   Para forçar a consolidação manual de um volume específico via CLI:
       ```bash
       # Deletar snapshots manuais antigos
       kubectl delete snapshots.longhorn.io -n longhorn-system -l "longhornvolume=<volume-uuid>,!longhorn.io/backup"
       ```

### Passo 3: Rebalanceamento de Réplicas do Longhorn
Se um nó específico (`node-1` ou `node-3`, por exemplo) estiver saturado, você pode desativar temporariamente o agendamento de discos nele e forçar o Longhorn a migrar réplicas para nós com maior headroom.

1. **Desativar o agendamento no nó cheio**:
   ```bash
   kubectl patch node.longhorn.io <nó-cheio> -n longhorn-system --type merge -p '{"spec":{"disks":{"default-disk":{"allowScheduling":false}}}}'
   ```
2. **Identificar réplicas de volumes que podem ser recriadas em outro nó**:
   Selecione um volume degradado ou reduza/aumente a contagem de réplicas desejadas para que o Longhorn reprovisione a réplica no nó livre.
3. **Reativar o agendamento após o rebalanceamento**:
   ```bash
   kubectl patch node.longhorn.io <nó-cheio> -n longhorn-system --type merge -p '{"spec":{"disks":{"default-disk":{"allowScheduling":true}}}}'
   ```

### Passo 4: Redução Física de Volumes Superdimensionados
Se um PVC foi alocado com tamanho excessivo (ex: 20GiB para uso real de 2GiB), use a TUI para encolher o volume com segurança:

1. Acesse o `./k8s_ops_menu.sh` -> `Access & Port Forwarding` -> `Start Tunnel` para a TUI de volumes.
2. Acesse `Volume Manager` no menu principal da TUI.
3. Selecione o PVC e escolha a opção `Shrink Volume`. A TUI guiará o processo realizando backup do snapshot, recriação do PVC e restauração segura dos dados.

---

## 4. Prevenção de Recorrência

*   **Configuração de Retention**: Mantenha a política `Gold Standard` ativa no cluster (`Gold Standard Backup Timer`). Ela garante que backups diários sejam exportados para o MinIO externo e snapshots locais antigos sejam expurgados a cada 24 horas.
*   **Thresholds no Kubernetes (Kubelet)**: O Kubelet de cada nó é configurado com `--eviction-hard=imagefs.available<10%,nodefs.available<10%`. Monitorar o headroom acima de 15 GiB garante que as ações sejam tomadas antes do despejo forçado de workloads.

---

## 5. Matriz de Severidade do Health Watchdog

O script `cluster_health_check.sh` roda diariamente e avalia o cluster gerando alarmes do systemd (`k8s-health-check.service`). A semântica de saída (Exit Status) é definida como:

*   **Exit `0` (Success / Warning)**: O cluster está operando de forma saudável. Alertas não-críticos (como headrooms de disco reduzidos mas não esgotados, ou correntes de backup com falhas parciais) são exibidos no stdout e processados como WARNING. O serviço systemd **não falhará**.
*   **Exit `2` (Critical)**: Falha gravíssima detectada (CrashLoopBackOffs persistentes em namespaces críticos, OOMKills sistemáticos ou discos 100% cheios). O serviço systemd **falhará**, disparando os handlers de alarme configurados.
