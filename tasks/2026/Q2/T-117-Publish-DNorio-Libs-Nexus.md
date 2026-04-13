# T-117 — Publicar @dnorio/* no Nexus npm-repo + Atualizar js-libs

**Status**: ✅ Done  
**Priority**: 🚨 Critical  
**Epic**: DevOps  
**Estimate**: 1h  
**Created**: 2026-04-13  
**Depends on**: T-116 (npm-repo criado no Nexus)  
**Blocks**: deploy de back-end, py-back-end e qualquer app que use @dnorio/*  
**Scope**: Apenas publish mecânico — integração TUI está em T-118  

---

## Contexto

8 libs `@dnorio/*` (monorepo Lerna em `~/js-libs`, v0.0.175) nunca foram
publicadas no Nexus local. O `back-end` e outros apps dependem delas durante
`npm ci` no build ARM64. Sem elas no `npm-repo`, o build falha com 404.

```
@dnorio/logger
@dnorio/httpclient
@dnorio/db-wrapper
@dnorio/models-core
@dnorio/models-toolhq
@dnorio/models-generator
@dnorio/pg-query-binding
@dnorio/swagger-router
```

Adicionalmente, o `js-libs` está parado em v0.0.175 e toda a config de registry
aponta para `nexus.localhost` sem porta — precisa atualizar para `:31081`.

---

## Critérios de Aceite

1. `~/js-libs/.npmrc` atualizado com porta `:31081` + token válido de publish
2. Todos os `publishConfig` em `packages/*/package.json` com porta `:31081`
3. `lerna publish` com `--registry` correto executa sem erro
4. `curl` no npm-group confirma os 8 pacotes presentes
5. `docker buildx build` do back-end completa sem 404 no npm ci

---

## Implementação

### 1. Atualizar js-libs para apontar para Nexus com porta correta

```bash
cd ~/js-libs

# .npmrc
cat > .npmrc << 'EOF'
//nexus.localhost:31081/repository/:_authToken=NpmToken.<TOKEN_GERADO_EM_T116>
registry=http://nexus.localhost:31081/repository/npm-group
EOF

# publishConfig em cada package.json
for pkg in packages/*/package.json; do
  sed -i 's|"registry": "http://nexus.localhost/repository/npm-repo/"|"registry": "http://nexus.localhost:31081/repository/npm-repo/"|g' "$pkg"
done
```

### 2. Build + Publish via Lerna

```bash
cd ~/js-libs

# Instalar deps (usa npm-group → npm-proxy → npmjs.org, após T-116)
npm install

# Build todos os pacotes
npm run publish
# ou se quiser forçar sem bump de versão:
npx lerna run tsc && npx lerna publish from-package --yes
```

> **Nota**: Se a versão 0.0.175 já existir no Nexus (re-run), usar
> `--force-publish` ou bumpar versão.

### 3. Verificar publicação

```bash
NEXUS="http://nexus.localhost:31081"
AUTH="admin:2511f551-7c17-4793-b058-adae6ecc0619"
curl -s -u "$AUTH" "$NEXUS/service/rest/v1/search?repository=npm-repo&format=npm" \
  | jq '[.items[].name]'
# Esperado: ["@dnorio/db-wrapper", "@dnorio/httpclient", ...]
```

### 4. Testar build do back-end

```bash
cd ~/production-site/apps/back-end
./deploy.sh
```

---

## Arquivos Afetados

| Arquivo | Mudança |
|---|---|
| `~/js-libs/.npmrc` | porta `:31081` + token de publish |
| `~/js-libs/packages/*/package.json` | `publishConfig.registry` com porta |

> `~/js-libs` não está no repositório `production-site` — alterações são locais.

---

## Notas

- Confirmar que `npm-proxy` tem egress para `registry.npmjs.org` antes de
  tentar instalar deps do js-libs; se não, instalar as deps do node do host
  local primeiro com registry público.
- Versão atual: `0.0.175` (lerna.json). Não bumpar versão neste task —
  apenas garantir que 0.0.175 está publicado.
- Se necessário re-publicar a mesma versão: `allow-republish` no `npm-repo`
  (Storage → Write Policy: `ALLOW_ONCE` → `ALLOW`).
