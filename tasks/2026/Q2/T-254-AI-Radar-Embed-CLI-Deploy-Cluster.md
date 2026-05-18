# T-254: AI Radar — Deploy CLI com embed + smoke semântico no cluster

- **Status**: Done
- **Priority**: 🔼 High
- **Epic/Owner**: Cursor / AI Radar
- **Estimation**: 2h

## Context

Fase 19 entregou o subcomando `ai-radar embed` e CronJob `ai-radar-embed`, mas o cluster ainda rodava imagem CLI antiga sem o comando. Deploy com `AI_RADAR_DEPLOY_CLI=1` exigiu correção no `deploy.sh` (stdout do `docker push` quebrava `validate_image_ref`) e normalização do `model` persistido vs `EMBEDDING_MODEL` no secret.

## Tasks

- [x] `./deploy.sh` com `AI_RADAR_DEPLOY_CLI=1` — tags API/CLI `1779070701`
- [x] Job manual `ai-radar-embed-manual-1779070895` → `embedded=20`, `failed=0`
- [x] Smoke: `GET /search?q=agent` com `mode=semantic` e hits
- [x] Remover pin temporário `nodeSelector: k8s-node-3` (API + cronjob embed)
- [x] Fix: gravar `model` do config no embed (não alias da API OpenRouter)

## Dependências

- Nexus/registry (`registry.local:31444`) operacional
- **k8s-node-2** Ready

## Validação

- `SELECT COUNT(*) FROM ai_radar.item_embeddings` = **20**
- Console Explorer busca semântica com % de similaridade
- Deploy produção: API/CLI `1779070701`
