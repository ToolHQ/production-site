# T-116 — Nexus: Bootstrap NPM Registry (hosted + proxy + group)

**Status**: 🚨 Blocker  
**Priority**: 🚨 Critical  
**Epic**: DevOps  
**Estimate**: 2h  
**Created**: 2026-04-13  
**Blocks**: T-117 (publish @dnorio/*), deploy do back-end  

---

## Contexto

O Nexus atualmente só tem `docker-repo`. Nenhum repositório npm foi criado.  
O `.npmrc` dos apps aponta para `npm-group` (que não existe), causando 404 em
todos os pacotes durante `npm ci` no build ARM64.

```
# Estado atual: apenas docker
docker-repo  hosted  docker
# Falta:
npm-repo     hosted  npm    ← publica @dnorio/* (privado)
npm-proxy    proxy   npm    ← espelha https://registry.npmjs.org
npm-group    group   npm    ← une npm-repo + npm-proxy (endpoint único p/ apps)
```

---

## Critérios de Aceite

1. Repositório `npm-repo` (hosted) criado no Nexus — blob store: `minio`
2. Repositório `npm-proxy` (proxy) criado — upstream: `https://registry.npmjs.org`
3. Repositório `npm-group` (group) criado — members: `[npm-repo, npm-proxy]`
4. `npm-group` acessível via `http://nexus.localhost:31081/repository/npm-group/`
5. Bearer token gerado para publish: `NpmToken.*` salvo no credstore como `nexus-npm`
6. `nexus_init.sh` atualizado com funções `nexus_create_npm_*`
7. Fluxo integrado na TUI: menu `Initialize Nexus` inclui setup npm

---

## Implementação

### Passo 1 — Criar repositórios via REST API

```bash
NEXUS="http://localhost:31081"
AUTH="admin:2511f551-7c17-4793-b058-adae6ecc0619"

# 1a. npm-repo (hosted, armazena @dnorio/* no minio)
curl -s -u "$AUTH" -X POST "$NEXUS/service/rest/v1/repositories/npm/hosted" \
  -H "Content-Type: application/json" -d '{
    "name": "npm-repo",
    "online": true,
    "storage": {"blobStoreName": "minio", "strictContentTypeValidation": true, "writePolicy": "ALLOW"},
    "component": {"proprietaryComponents": false}
  }'

# 1b. npm-proxy (upstream: npmjs.org)
curl -s -u "$AUTH" -X POST "$NEXUS/service/rest/v1/repositories/npm/proxy" \
  -H "Content-Type: application/json" -d '{
    "name": "npm-proxy",
    "online": true,
    "storage": {"blobStoreName": "minio", "strictContentTypeValidation": true},
    "proxy": {"remoteUrl": "https://registry.npmjs.org", "contentMaxAge": 1440, "metadataMaxAge": 1440},
    "negativeCache": {"enabled": true, "timeToLive": 1440},
    "httpClient": {"blocked": false, "autoBlock": true, "connection": {"useTrustStore": false}},
    "routingRuleName": null,
    "npmAttributes": {"removeQuarantined": true}
  }'

# 1c. npm-group (une os dois acima)
curl -s -u "$AUTH" -X POST "$NEXUS/service/rest/v1/repositories/npm/group" \
  -H "Content-Type: application/json" -d '{
    "name": "npm-group",
    "online": true,
    "storage": {"blobStoreName": "minio", "strictContentTypeValidation": true},
    "group": {"memberNames": ["npm-repo", "npm-proxy"]}
  }'
```

### Passo 2 — Gerar token de publish

Via UI: Security → Realms → ativar `npm Bearer Token Realm`  
Ou via API:

```bash
curl -s -u "$AUTH" -X PUT "$NEXUS/service/rest/v1/security/realms/active" \
  -H "Content-Type: application/json" \
  -d '["NexusAuthenticatingRealm","NexusAuthorizingRealm","NpmToken"]'
```

Depois `npm login`:
```bash
npm login --registry=http://nexus.localhost:31081/repository/npm-repo/
# → gera token, salvar no .npmrc como //nexus.localhost:31081/repository/:_authToken=NpmToken.xxx
```

### Passo 3 — Atualizar `nexus_init.sh`

Adicionar funções:
- `nexus_create_npm_hosted()` — cria `npm-repo`
- `nexus_create_npm_proxy()` — cria `npm-proxy`
- `nexus_create_npm_group()` — cria `npm-group`
- `nexus_enable_npm_realm()` — ativa Bearer Token Realm
- Integrar em `nexus_initialize()` como steps 5–8

### Passo 4 — Atualizar porta no `.npmrc` de js-libs e back-end

```
# Antes
registry=http://nexus.localhost/repository/npm-group
# Depois
registry=http://nexus.localhost:31081/repository/npm-group
```

---

## Arquivos Afetados

| Arquivo | Mudança |
|---|---|
| `oci-k8s-cluster/lib/nexus_init.sh` | +4 funções npm + integrar em `nexus_initialize` |
| `apps/back-end/.npmrc` | porta `:31081` explícita |
| `~/js-libs/.npmrc` | porta `:31081` + auth token atualizado |
| `~/js-libs/packages/*/package.json` | `publishConfig.registry` com porta `:31081` |

---

## Notas

- O blob store `minio` deve estar criado antes (parte do `nexus_initialize` existente)
- `npm-proxy` pode falhar se o cluster não tiver acesso à internet — validar egress
- Após T-116, executar T-117 para publicar as libs
