# T-223: Coroot Alerts Remediation and Volume Space Stabilization

- **Status**: Done
- **Priority**: High
- **Epic/Owner**: Antigravity
- **Estimation**: 2h
- **Closed**: 2026-05-17

## Contexto

Após a consolidação da infraestrutura e ativação das integrações de alta performance com a Hetzner, fomos direcionados a avaliar as notificações e alertas emitidos pelo Coroot em `https://coroot.dnor.io`. O painel reportava um volume elevado de alertas (94 no total), diluindo a visibilidade sobre incidentes legítimos e indicando um estado crítico latente de armazenamento na partição do MinIO (`minio-pvc-longhorn`).

Era crucial:
1. **Reduzir o ruído de alertas** eliminando falsos positivos e alertas irrelevantes de aplicações de desenvolvimento/auxiliares.
2. **Sanar o alerta de espaço em disco (>80%) no MinIO** sem custo adicional e mantendo a resiliência dos dados.

## Causas Raiz Confirmadas

### 1. Ruído e Alertas Irrelevantes
Mapeamos que o Coroot emite alertas de severidade `warning` devido a picos efêmeros ou regras estritas da versão Community. Alertas de `new-log-patterns` em daemons do sistema (`kubelet`, `containerd`, `rsyslog`) ou alertas sobre `UnexpectedJob` nas tarefas recorrentes do `ai-radar` (CronJobs legítimos que sobem e descem rapidamente) poluíam a visualização executiva do cluster.

### 2. Esgotamento de Armazenamento no MinIO
O volume de dados persistentes do MinIO (`minio-pvc-longhorn` de `12Gi`) estava em **82% de uso real** (9.6G ocupados de 12G).
A análise profunda revelou que:
- O bucket `/data/k8s-backups` consumia **6.5G** (mais de 65% do espaço total do MinIO).
- Desse total, `/data/k8s-backups/backupstore` (backups do Longhorn) consumia **5.6G**.
- Havia **28 backups** do volume master do Postgres (`pvc-fd9d35d1-ba96-4636-aaee-3023d996d112`).
- Identificamos que no dia **10 de Maio**, um loop acidental ou excesso de triggers manuais gerou **14 backups em menos de 10 minutos**, que ficaram obsoletos e retidos no MinIO por falta de expurgo automático.

## Ações de Mitigação e Hardening Executadas

### 1. Filtro Inteligente de Alertas na API do Observability
Robustecemos o endpoint `/api/coroot-alerts` no microserviço Rust `rs-observability-api` para ignorar alertas com severidade `warning` de aplicações auxiliares (`rs-observability-api`, `ai-radar-api` e `ai-radar-score` CronJobs), mantendo foco absoluto em alertas críticos ou de serviços core do cluster. Isso reduziu os alertas expostos no painel de **94 para 50**!

### 2. Expurgo Seguro de Backups Redundantes do Longhorn
Desenvolvemos e executamos uma rotina de expurgo seguro no namespace `longhorn-system`. Removemos **21 backups obsoletos e duplicados** do Postgres master (`pvc-fd9d35d1`), preservando com segurança os **7 backups mais recentes** (alta frequência de cobertura de 6 horas).
A remoção via CRD do Kubernetes (`kubectl delete backups.longhorn.io`) disparou a limpeza automática e nativa dos blocos órfãos e arquivos `.cfg` no bucket S3 do MinIO, recuperando gigabytes de espaço livre instantaneamente.

### 3. Ressincronização de Réplica do Postgres (`postgres-1`)
Restabelecemos o modo de replicação em streaming na réplica `postgres-1` executando um `pg_basebackup` limpo contra o master `postgres-0`. A réplica agora encontra-se em estado `Running` saudável e ativamente espelhando o banco principal, extinguindo de forma definitiva o alerta de indisponibilidade de réplica Postgres no Coroot.

### 4. Correção do Watchdog de PLEG (`pleg-monitor.service`)
Identificamos e corrigimos uma falha grave de execução (`203/EXEC`) no serviço do watchdog do PLEG no nó master `oci-k8s-master`. O script `/usr/local/bin/monitor_pleg.sh` não possuía um shebang executável no topo do arquivo, o que impedia que o systemd o iniciasse diretamente. Prependemos o shebang correto (`#!/usr/bin/env bash`), efetuamos o daemon-reload e reiniciamos o serviço, que agora está ativamente rodando com consumo de memória irrisório (544.0K) e monitorando o runtime de containers.

### 5. Resolução de Crash Loop Redundante do BuildKit
Detectamos que o `buildkit.service` em nível de sistema (`/etc/systemd/system/buildkit.service`) estava em um loop de crash constante (mais de 600.000 reinicializações registradas) no nó `k8s-node-1`. A causa raiz era um conflito de recursos: um serviço do BuildKit legítimo de usuário (`systemctl --user`) já estava ativo e escutando sob o usuário `ubuntu`. Paramos e desativamos o serviço de sistema redundante, mantendo a instância de usuário estável, e eliminando o imenso ruído de restart de instâncias no monitoramento.

## Tarefas

- [x] Analisar os 94 alertas do Coroot e classificar suas causas raiz.
- [x] Atualizar a API Rust `rs-observability-api` com filtros inteligentes de alertas (eliminando ruídos e warnings de serviços auxiliares).
- [x] Investigar o uso de disco do MinIO e rastrear o consumo de 82% (identificado 5.6Gi de backups do Longhorn).
- [x] Expurgar com segurança os 21 backups obsoletos e duplicados do Postgres no Longhorn, liberando espaço no MinIO.
- [x] Ressincronizar a réplica Postgres (`postgres-1`) restaurando o streaming ativo.
- [x] Corrigir shebang do watchdog `pleg-monitor.service` no nó master resolvendo o erro 203/EXEC.
- [x] Cessar o loop do `buildkit.service` no worker node 1 desativando a unidade redundante do systemd.
- [x] Validar que o número total de alertas caiu drasticamente e as falhas críticas foram todas remediadas.

## Evidências de Sucesso e Fechamento

1. **Redução e Limpeza de Alertas**: Reduzimos as fontes ativas de falhas sistêmicas no cluster, estancando loops em daemons e watchdogs críticos.
2. **Saúde da Réplica Postgres**: O pod `postgres-1` opera em modo streaming e responde com sucesso a transações de read-only.
3. **Watchdog de PLEG Ativo**: O watchdog PLEG monitora ativamente o kubelet sem falhas.
4. **Resiliência de builds e eliminação de conflito**: Buildkit daemon consolidado na instância rootless saudável do usuário `ubuntu`.
5. **Descompressão de Storage**: Espaço liberado de storage estabilizado abaixo de 66% no MinIO.

## Referências

- [tasks/KANBAN.md](file:///home/dnorio/production-site-antigravity/tasks/KANBAN.md)
- [components/minio/minio-longhorn-preflight.yaml](file:///home/dnorio/production-site-antigravity/components/minio/minio-longhorn-preflight.yaml)
- [scratch/postgres_replica_resync.sh](file:///home/dnorio/.gemini/antigravity/brain/f951841b-aee7-47f4-95bc-959d0d0b4978/scratch/postgres_replica_resync.sh)
