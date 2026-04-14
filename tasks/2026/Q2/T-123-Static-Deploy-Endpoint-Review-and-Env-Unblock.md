# T-123 — Static Deploy: endpoint review + env unblock

**Status**: 📋 Backlog  
**Priority**: 🚨 Critical  
**Epic**: DevOps / TUI  
**Estimate**: 2h  
**Created**: 2026-04-13  
**Depends on**: T-122 (primeiro fluxo TUI de static deploy)  
**Blocks**: publicação real do frontend estático pela TUI

---

## Contexto

Após a primeira implementação do deploy do `apps/static` na TUI, apareceu um ajuste
importante de realidade operacional: o endpoint correto já não é mais
`minio.localhost`, e sim **`minio.dnor.io`**.

Hoje ainda existem referências antigas a `minio.localhost` em vários pontos do repo,
inclusive:

- `apps/static/package.json`
- `apps/static/upload.sh`
- pré-checagem do `oci-k8s-cluster/k8s_ops_menu.sh`
- artefatos legados de ambiente local/minikube

Além disso, a validação real do fluxo ficou bloqueada por limitações do ambiente
local do agente: ausência de `aws` no `PATH` e resolução DNS incompatível com o
host esperado. Esta task existe para revisar o endpoint canônico do upload estático,
eliminar dependência indevida de `minio.localhost` e tornar o fluxo TUI realmente
executável no ambiente operacional atual.

---

## Critérios de Aceite

1. O endpoint canônico do static deploy fica padronizado em `minio.dnor.io`
2. `apps/static` e a TUI deixam de depender de `minio.localhost` para o fluxo atual
3. O mecanismo de upload valida DNS/URL corretos para o ambiente OCI
4. Os pré-requisitos operacionais necessários (`aws`, trust TLS, acesso ao endpoint) ficam claros e verificáveis
5. O deploy do static volta a ser executável pela TUI no ambiente real

---

## Tasks

- [ ] Mapear todas as referências atuais a `minio.localhost` e separar o que é legado de minikube do que ainda impacta OCI
- [ ] Definir o endpoint oficial para upload do static (`minio.dnor.io`) e revisar se o protocolo/TLS exigem ajustes no comando `aws s3 sync`
- [ ] Atualizar `apps/static/package.json` e `apps/static/upload.sh` para o endpoint correto
- [ ] Ajustar as pré-checagens do `k8s_ops_menu.sh` para validar `minio.dnor.io` em vez de `minio.localhost`
- [ ] Resolver ou documentar os bloqueios reais do ambiente local para execução do upload (`aws`, DNS, trust da CA)
- [ ] Validar uma publicação real do `apps/static` e confirmar que o nginx serve os assets atualizados

---

## Arquivos Afetados

| Arquivo | Mudança esperada |
| --- | --- |
| `apps/static/package.json` | trocar endpoint antigo por `minio.dnor.io` |
| `apps/static/upload.sh` | alinhar comando de sync ao endpoint atual |
| `oci-k8s-cluster/k8s_ops_menu.sh` | corrigir pré-checagens e mensagens do static deploy |
| `tasks/2026/Q2/T-123-Static-Deploy-Endpoint-Review-and-Env-Unblock.md` | registrar decisão operacional e validação |

---

## Notas

- `components/minio/minio-resources.yaml` já expõe `minio.dnor.io`, então o fluxo de deploy do static precisa convergir para esse host.
- Parte das referências a `minio.localhost` pode continuar existindo apenas para ambientes locais/minikube; a task deve evitar quebrar esses casos sem necessidade.
- O objetivo principal é remover ambiguidade operacional e deixar o deploy estático funcionar no ambiente real atual.
