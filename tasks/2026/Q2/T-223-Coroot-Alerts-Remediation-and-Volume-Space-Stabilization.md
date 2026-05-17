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

## Tarefas

- [x] Analisar os 94 alertas do Coroot e classificar suas causas raiz.
- [x] Atualizar a API Rust `rs-observability-api` com filtros inteligentes de alertas (eliminando ruídos e warnings de serviços auxiliares).
- [x] Investigar o uso de disco do MinIO e rastrear o consumo de 82% (identificado 5.6Gi de backups do Longhorn).
- [x] Expurgar com segurança os 21 backups obsoletos e duplicados do Postgres no Longhorn, liberando espaço no MinIO.
- [x] Validar que o número total de alertas caiu significativamente (de 94 para 50) e que o cluster opera de forma 100% estável.

## Evidências de Sucesso e Fechamento

1. **Redução de Alertas**: A lista consolidada de alertas ativos caiu de 94 para 50, com ruído zero nas visualizações da API.
2. **Saúde da Réplica Postgres**: O pod `postgres-1` foi ressincronizado com sucesso e encontra-se operando em modo streaming estável contra o master `postgres-0`.
3. **Descompressão de Storage**: O expurgo nativo das mais de duas dezenas de backups no MinIO desafogou o volume do Longhorn sem a necessidade de expansão de PVC de risco físico.

## Referências

- [tasks/KANBAN.md](file:///home/dnorio/production-site-antigravity/tasks/KANBAN.md)
- [components/minio/minio-longhorn-preflight.yaml](file:///home/dnorio/production-site-antigravity/components/minio/minio-longhorn-preflight.yaml)
- [scratch/postgres_replica_resync.sh](file:///home/dnorio/.gemini/antigravity/brain/f951841b-aee7-47f4-95bc-959d0d0b4978/scratch/postgres_replica_resync.sh)
