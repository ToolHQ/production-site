# T-319: agent-meter — Multi-tenant + Auth (Orgs / Projects / API Keys)

## Objetivo
Adicionar **multi-tenancy** ao agent-meter (orgs → projects → users + API keys) para permitir onboarding de N clientes na mesma instância hosted, sem mistura de dados.

## Por que (produto / monetização)
- **Pré-requisito de SaaS**. Sem isolamento por org, é impossível vender para um 2º cliente.
- Habilita T-321 (signup + Stripe), T-322 (hosted infra).
- Modelo conceitual igual a Linear/Vercel/Supabase: org > project > member.

## Especificações

### 1. Schema
```sql
CREATE TABLE organizations (
  id UUID PRIMARY KEY,
  slug VARCHAR(64) UNIQUE NOT NULL,
  name VARCHAR(128) NOT NULL,
  plan VARCHAR(32) NOT NULL DEFAULT 'free',  -- free|pro|team|enterprise
  stripe_customer_id VARCHAR(64),
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE projects (
  id UUID PRIMARY KEY,
  org_id UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
  slug VARCHAR(64) NOT NULL,
  name VARCHAR(128) NOT NULL,
  UNIQUE(org_id, slug)
);

CREATE TABLE users (
  id UUID PRIMARY KEY,
  email VARCHAR(255) UNIQUE NOT NULL,
  hashed_password VARCHAR(255),
  github_id BIGINT UNIQUE,
  google_sub VARCHAR(128) UNIQUE,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE memberships (
  org_id UUID REFERENCES organizations(id) ON DELETE CASCADE,
  user_id UUID REFERENCES users(id) ON DELETE CASCADE,
  role VARCHAR(16) NOT NULL,  -- owner|admin|member|viewer
  PRIMARY KEY (org_id, user_id)
);

CREATE TABLE api_keys (
  id UUID PRIMARY KEY,
  project_id UUID NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
  hashed_key VARCHAR(64) NOT NULL,  -- argon2 ou sha256
  prefix VARCHAR(12) NOT NULL,      -- "amk_live_..."
  name VARCHAR(64),
  last_used_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  revoked_at TIMESTAMPTZ
);
```

Adicionar `project_id` em `events`, `conversations` (backfill: criar org/project default `personal`).

### 2. Auth
- **Sessão web**: cookie httpOnly + JWT curto (15min) + refresh
- **Provedores**: Email/password (argon2), GitHub OAuth, Google OAuth
- **Ingest**: header `Authorization: Bearer amk_live_xxx` ou query `?api_key=`
- **Rate limit**: por API key, configurável por plano

### 3. Endpoints
- `POST /auth/signup` `/login` `/logout` `/refresh`
- `GET /auth/oauth/github` `/auth/oauth/google`
- `GET /api/orgs` `/api/orgs/:id` `POST /api/orgs`
- `GET/POST /api/orgs/:id/projects`
- `POST /api/projects/:id/api-keys` `DELETE /api/projects/:id/api-keys/:key_id`
- `GET /api/projects/:id/members` `POST .../invite`

### 4. UI
- `/login`, `/signup`, `/onboarding` (cria org default)
- Header com switcher de org/project (estilo Linear)
- `/settings/organization`, `/settings/projects`, `/settings/members`, `/settings/api-keys`
- Todos os reports passam a filtrar por `current_project_id` da sessão

### 5. Migração
- Job de backfill: cria org `personal` + project `default` para dados existentes
- `wsl-vscode.md` e setup-agent.sh atualizados para usar API key em vez de hostname

## Critérios de Aceitação
- [ ] Schema aplicado em dev e prod via migration
- [ ] Login/signup funcionais (email + GitHub)
- [ ] Ingest valida API key e rejeita 401 sem ela
- [ ] Dois projetos no mesmo banco têm dados 100% isolados (teste end-to-end)
- [ ] Switcher de org/project no header funciona
- [ ] **Browser MCP** validado: signup → criar projeto → gerar key → enviar evento → ver no dashboard

## Estimativas
- Schema + migrations: 2h
- Auth (sessões + OAuth): 4h
- API multi-tenant (CRUD + middleware tenant): 4h
- UI (login, settings, switcher): 4h
- Migração de dados existentes: 1h
- **Total**: ~15h (2 dias)

## Owner
**Copilot/VSCode**

## Dependências
- Habilita: T-320 (alerts por org), T-321 (Stripe checkout), T-322 (hosted infra)
- Bloqueia: qualquer onboarding de cliente externo
