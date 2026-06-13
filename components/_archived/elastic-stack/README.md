# Elastic Stack (ECK) — arquivado

**Status:** removido do cluster OCI (2026-06). Não entra mais no deploy padrão da TUI.

## Por quê

- Stack pesada para nós OCI (1 vCPU / 6 GiB): ECK operator + ES + Logstash + Filebeat + Kibana
- Consumia headroom Longhorn e gerava alertas recorrentes
- Kibana/ES não eram usados no dia a dia (observabilidade principal: **Coroot**)

## Desinstalação no cluster

```bash
ssh oci-k8s-master 'bash -s' < oci-k8s-cluster/scripts/elastic/uninstall_elastic_stack.sh
```

Ou pela TUI: **Components → Uninstall** (se ainda listar `_archived`, não deve).

## Próximo passo (planejado)

**Vector** coletando logs de pods/nós → **Parquet** no MinIO (`s3://logs/...`), leve e alinhado à política de custo zero.

Manifests futuros: `components/vector/` (ainda não criado).

## Manifests preservados

Referência histórica apenas — não aplicar em produção OCI sem revisão de recursos.
