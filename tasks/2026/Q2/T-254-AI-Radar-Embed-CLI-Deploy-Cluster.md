# T-254: AI Radar — Deploy CLI com embed + smoke semântico no cluster

- **Status**: Backlog
- **Priority**: 🔼 High
- **Epic/Owner**: Cursor / AI Radar
- **Estimation**: 2h

## Context

Fase 19 entregou o subcomando `ai-radar embed` e CronJob `ai-radar-embed`, mas o cluster ainda roda imagem CLI antiga (`1779047721`) sem o comando. API já em `1779065738` com busca semântica habilitada no secret.

## Tasks

- [ ] `./deploy.sh` com `AI_RADAR_DEPLOY_CLI=1` após Nexus/registry saudável
- [ ] Job manual: `kubectl create job … --from=cronjob/ai-radar-embed` → `embedded > 0`
- [ ] Smoke: `GET /search?q=…` com `mode=semantic` e hits; related items no detalhe
- [ ] Remover pin temporário `nodeSelector: k8s-node-3` da API se registry normalizado

## Dependências

- Nexus/registry (`registry.local:31444`) operacional
- **k8s-node-2** Ready (Nexus `nodeSelector` atual)

## Validação

- `SELECT COUNT(*) FROM ai_radar.item_embeddings` > 0
- Console Explorer busca semântica com % de similaridade
