# T-125: Back-End — APM optional + service recovery

- **Status**: 📋 Backlog
- **Priority**: 🚨 Critical
- **Owner**: DevOps
- **Est.**: 1h
- **Created**: 2026-04-15
- **Blocks**: API completamente indisponível (39h+ em CreateContainerConfigError)

---

## Contexto

O pod `my-site-back-end-deployment` está em `CreateContainerConfigError` há mais de
39 horas. O erro é direto:

```
Error: secret "apm-server-quickstart-apm-token" not found
```

O manifesto `apps/back-end/k8s/my-site-back-end.yaml` referencia um `secretKeyRef`
obrigatório para `ELASTIC_APM_SERVER_TOKEN`:

```yaml
- name: ELASTIC_APM_SERVER_TOKEN
  valueFrom:
    secretKeyRef:
      name: apm-server-quickstart-apm-token
      key: secret-token          # ← sem optional: true → bloqueia startup
```

O Elastic APM Server (`apm-server-quickstart-apm-http`) **não está deployado** no
cluster (`elastic-system` namespace vazio). Não existe previsão de re-deploy do stack
Elastic completo a curto prazo — ele foi desativado por restrição de CPU/RAM
(1 vCPU / 6 GB RAM por nó, Stability First).

A instrumentação APM no back-end usa o pacote `elastic-apm-node`, que já trata a
ausência da variável `ELASTIC_APM_SERVER_TOKEN` graciosamente em runtime — o problema
é exclusivamente no Kubernetes que rejeita criar o container antes mesmo de iniciar.

---

## Análise de risco

| Opção | Descrição | Risco |
|-------|-----------|-------|
| **A — `optional: true`** | Adicionar `optional: true` ao `secretKeyRef` | ✅ Zero: k8s passa o env como vazio; APM desativa-se em runtime |
| **B — Secret placeholder** | Criar secret vazio `apm-server-quickstart-apm-token` | ⚠️ Mascara o estado real; APM tentará conectar e falhará em runtime |
| **C — Remover as vars APM** | Remover as 3 envs `ELASTIC_APM_*` do manifesto | ⚠️ Perde o instrumentation hook se APM for reativado no futuro |

**Decisão recomendada: Opção A** — `optional: true` preserva toda a instrumentação
existente, deixa o caminho aberto para reativar o APM sem tocar no manifesto, e é
a forma semântica correta para dependências opcionais de observabilidade.

---

## Critérios de Aceite

1. `my-site-back-end` pod em `Running` / `1/1 Ready`
2. `kubectl logs` do back-end sem erros fatais de startup
3. `GET /health` do back-end respondendo 200
4. Manifesto commitado com `optional: true` documentado em comentário inline
5. APM vars mantidas no manifesto para reativação futura sem mudança de IaC

---

## Tasks

- [ ] Adicionar `optional: true` ao `secretKeyRef` de `ELASTIC_APM_SERVER_TOKEN` em `apps/back-end/k8s/my-site-back-end.yaml`
- [ ] Adicionar comentário inline no yaml explicando que APM server está desativado (sem Elastic Stack no cluster)
- [ ] `kubectl apply -f apps/back-end/k8s/my-site-back-end.yaml` e aguardar pod `Running`
- [ ] Verificar `kubectl logs` — confirmar startup limpo sem APM fatal
- [ ] Verificar `GET /health` via ingress ou port-forward
- [ ] Commit + push do manifesto corrigido

---

## Arquivos Afetados

| Arquivo | Mudança |
|---------|---------|
| `apps/back-end/k8s/my-site-back-end.yaml` | `optional: true` no secretKeyRef do APM token (linhas 70–74) |

---

## Notas

- **Elastic APM desativado**: stack Elastic (`elastic-system`) foi desativado por
  restrição de recursos. Namespace existe mas está vazio. Não reativar sem análise
  de CPU headroom (ver T-103).
- Referência: `elastic-apm-node` docs — quando `ELASTIC_APM_ACTIVE` é falso ou o
  token está ausente, o agente entra em modo no-op sem falhar.
- O token APM ficava antes em `apm-server-quickstart-apm-token/secret-token`,
  criado automaticamente pelo ECK operator quando o ApmServer CRD estava presente.
