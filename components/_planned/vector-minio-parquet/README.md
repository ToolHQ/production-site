# Vector → MinIO (Parquet) — planejado

Substituto leve do Elastic Stack arquivado em `_archived/elastic-stack/`.

## Objetivo

- Coletar logs de pods/nós via **Vector**
- Persistir em **Parquet** no MinIO (`s3://logs/...` ou bucket dedicado)
- Consulta ad-hoc: DuckDB, Athena-style, ou jobs batch — sem ES/Kibana no cluster

## Não implementado

Manifests e deploy serão adicionados quando houver task dedicada (headroom Longhorn + sizing).
