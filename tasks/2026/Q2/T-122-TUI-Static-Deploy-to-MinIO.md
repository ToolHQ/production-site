# T-122 — TUI: Static Deploy para MinIO

**Status**: 🏎️ In Progress  
**Priority**: 🔼 High  
**Epic**: DevOps / TUI  
**Estimate**: 3h  
**Created**: 2026-04-13  
**Depends on**: T-115 (App Deploy Menu), T-119 (logs persistidos)  
**Blocks**: fluxo operacional simples para atualizar frontend estático

---

## Contexto

O frontend servido pelo `apps/nginx` lê os assets estáticos a partir do bucket
`s3://my-site/static/` no MinIO, via `STATIC_SERVICE=http://minio-service.minio.svc.cluster.local:9000`.

Hoje o fluxo existe, mas está espalhado:

- `apps/static/package.json` expõe `npm run build-and-upload`
- `apps/static/upload.sh` faz `aws --endpoint-url http://minio.localhost s3 sync ...`

Ou seja: o deploy do static depende de lembrar manualmente como buildar o `dist`
e sincronizar para o bucket do MinIO. Esta task existe para trazer esse fluxo para
a TUI, com descoberta clara, execução guiada e logs persistidos no host.

---

## Critérios de Aceite

1. A TUI passa a oferecer uma ação explícita para deploy do app static
2. O fluxo builda os assets e sincroniza `./dist` para `s3://my-site/static/`
3. O endpoint MinIO/credenciais pré-requisito são checados antes da execução
4. stdout/stderr ficam persistidos em log local, no mesmo padrão dos deploys recentes
5. Ao final, a TUI informa sucesso/falha e o caminho do log gerado

---

## Tasks

- [x] Mapear o fluxo atual do `apps/static` (`build`, `copy-assets`, `upload`) e os pré-requisitos locais
- [x] Definir onde o static entra na TUI: novo submenu dedicado ou integração no App Deploy existente
- [x] Implementar execução guiada para `npm run build-and-upload` ou equivalente seguro
- [x] Garantir que o upload use o bucket `s3://my-site/static/` via endpoint MinIO correto
- [x] Integrar logs persistidos no host para build/upload do static
- [ ] Validar uma publicação real e confirmar que o nginx passa a servir os novos assets

---

## Arquivos Afetados

| Arquivo | Mudança esperada |
| --- | --- |
| `oci-k8s-cluster/k8s_ops_menu.sh` | novo fluxo TUI para deploy do static |
| `apps/static/package.json` | revisar scripts existentes apenas se necessário |
| `apps/static/upload.sh` | possivelmente ajustar endpoint/robustez para uso operacional |
| `tasks/2026/Q2/T-122-TUI-Static-Deploy-to-MinIO.md` | registrar fluxo, pré-requisitos e validação |

---

## Notas

- O destino correto é o bucket `my-site`, prefixo `static/`.
- O MinIO local historicamente aparece como `minio.localhost` no fluxo de upload manual.
- O objetivo é reduzir dependência de memória operacional: o deploy do static deve ficar descobrível dentro da TUI.
- Implementação aplicada em `k8s_ops_menu.sh`: `apps/static` agora aparece no App Deploy Menu com ação dedicada **Build + Upload Static**, pré-checagens (`node`, `npm`, `aws`, `jq`, resolução de `minio.localhost`) e log persistido no host.
- Nesta sessão, a validação real ficou bloqueada por ambiente local: `aws` não está instalado no `PATH` e `minio.localhost` não resolve neste host do agente.
