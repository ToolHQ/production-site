# T-307: OCI Longhorn disk headroom e política preventiva

- **Status**: Backlog
- **Priority**: 🔼 High
- **Epic/Owner**: Cursor / AI Radar
- **Estimation**: 1d

## Context

O health watchdog reportou headroom baixo nos discos Longhorn: master ~10G livres, node-1 ~11G, node-3 ~14G, todos abaixo do warning de 15G. Não há volumes degradados, mas o histórico do cluster mostra incidentes de DiskPressure e Longhorn sensível a falta de espaço.

Essa tarefa deve transformar o alerta em prevenção: capacity model, threshold consistente, painéis/TUI e ações seguras antes de chegar em DiskPressure.

## Tasks

- [ ] Coletar uso por nó: rootfs, `/var/lib/longhorn`, imagens/containerd, logs e snapshots.
- [ ] Correlacionar volumes Longhorn, réplicas, snapshots e nós com menor headroom.
- [ ] Definir thresholds por nó e por pool: warning/critical e ações recomendadas.
- [ ] Adicionar diagnóstico à TUI/relatório: top consumers, volumes por nó, snapshots antigos e rootfs.
- [ ] Planejar remediações seguras: prune de snapshots, ajuste de retention, realocação de workloads ou expansão controlada.
- [ ] Documentar runbook de triagem antes de qualquer limpeza destrutiva.

## Validação

```bash
kubectl get volumes.longhorn.io -n longhorn-system -o wide
kubectl get nodes
for n in oci-k8s-master oci-k8s-node-1 oci-k8s-node-2 oci-k8s-node-3; do ssh "$n" "df -h / /var/lib/longhorn 2>/dev/null"; done
```

Critério de aceite: relatório/TUI apontando causa do headroom baixo e plano de ação seguro versionado.
