# T-126: MinIO — Provisionamento de Bucket `my-site` via IaC

- **Status**: ✅ Done
- **Priority**: 🔼 High
- **Owner**: DevOps / Infra
- **Est.**: 1h
- **Created**: 2026-04-15
- **Depends on**: MinIO running (minio-deployment Running — ok)

---

## Contexto

O bucket `my-site` foi criado manualmente em 2026-04-15 durante a validação da
T-123. Sem ele, o nginx retornava `AccessDenied` ao tentar servir os assets
estáticos (`minio-service:9000/my-site/static/index.html`).

Além do bucket, uma policy de leitura pública foi aplicada manualmente via
`aws s3api put-bucket-policy` para permitir acesso anônimo ao prefixo `static/*`:

```json
{
  "Statement": [{
    "Effect": "Allow",
    "Principal": {"AWS": ["*"]},
    "Action": ["s3:GetObject"],
    "Resource": ["arn:aws:s3:::my-site/static/*"]
  }]
}
```

**Problema**: esses dois recursos (bucket + policy) existem apenas em runtime.
Se o MinIO pod for recriado, se o PVC for migrado, ou se o cluster for
re-provisionado, tanto o bucket quanto a policy serão perdidos — e o site para
imediatamente sem erro óbvio no ingress, apenas `AccessDenied` no browser.

O padrão correto para recursos MinIO neste cluster é codificar a inicialização
como um **Kubernetes Job** (ou `initContainer`) que usa o MinIO Client (`mc`) ou
`aws s3api` para garantir estado idempotente. O mesmo padrão já existe para backup
(ver `components/backup/`).

---

## Análise do estado atual

| Recurso | Estado | IaC |
|---------|--------|-----|
| Bucket `k8s-backups` | Existe | ❓ Criado manualmente (histórico antigo) |
| Bucket `nexus` | Existe | ❓ Criado manualmente (histórico antigo) |
| Bucket `my-site` | Existe (criado 2026-04-15) | ❌ Somente runtime |
| Policy `my-site` public-read `/static/*` | Aplicada (2026-04-15) | ❌ Somente runtime |

Outros buckets (`k8s-backups`, `nexus`) também não têm IaC, mas estão fora do
escopo desta task — são cobertos por T-124 (backup retention audit).

---

## Critérios de Aceite

1. Um Job (ou `initContainer`) em `components/minio/` executa na inicialização e garante:
   - Bucket `my-site` existe (idempotente — não falha se já existe)
   - Policy `GET s3://my-site/static/*` pública está aplicada
2. O Job/script pode ser re-executado sem efeitos colaterais
3. `components/minio/minio-resources.yaml` ou arquivo adjacente referencia o Job
4. Documentação do endpoint e credenciais usados (sem hardcode — via secret existente `minio-secret`)
5. Preferência por `mc` (MinIO Client) sobre `aws cli` para evitar dependência externa no Job
6. README ou comentário inline documenta o padrão para outros buckets futuros

---

## Tasks

- [x] Decidir mecanismo: **Job pós-deploy** com imagem `minio/mc:latest`
- [x] Implementar Job de bootstrap do bucket `my-site` usando secret `minio-secret` existente
- [x] Aplicar a policy public-read em `s3://my-site/static/*` no mesmo Job
- [x] Testar re-execução (idempotência: sem erros em bucket/policy já existentes)
- [x] Documentar o padrão em `components/minio/` para reuso em novos buckets
- [x] Commit + push

## Resultado

- Job `minio-bootstrap-buckets` adicionado ao fim de `components/minio/minio-resources.yaml`
- Executado com sucesso em 2026-04-15:
  ```
  Added `local` successfully.
  Bucket created successfully `local/my-site`.
  Access permission for `local/my-site/static/` is set to `download`
  Bootstrap complete.
  ```
- `ttlSecondsAfterFinished: 300` — Job removido automaticamente após 5 min
- `mc mb --ignore-existing` + `mc anonymous set download` garantem idempotência
- Credenciais via `secretKeyRef` no `minio-secret` existente (sem hardcode)

---

## Arquivos Afetados

| Arquivo | Mudança |
|---------|---------|
| `components/minio/minio-resources.yaml` | Adicionar Job ou referência ao script de bootstrap |
| `components/minio/bootstrap-buckets.yaml` *(novo)* | Job k8s de provisionamento idempotente |
| `components/minio/commands.sh` | Documentar o bootstrap como step de instalação |

---

## Notas

- **Credenciais**: usar secret `minio-secret` (namespace `minio`) — campos
  `MINIO_ROOT_USER` / `MINIO_ROOT_PASSWORD`. Não hardcodar.
- **Endpoint interno**: `http://minio-service.minio.svc.cluster.local:9000`
  (Job roda in-cluster, sem necessidade de ingress TLS).
- **mc vs aws cli**: `mc` é preferível em Jobs pois é a imagem oficial MinIO
  (`minio/mc`) e inclui suporte nativo a policy. `aws s3api` requer imagem maior.
- **Policy aplicada atualmente** (estado runtime 2026-04-15):
  `s3://my-site/static/*` → `s3:GetObject` para `Principal: *` (public read).
- Bucket `my-site` foi criado com `aws s3 mb s3://my-site` — equivalente `mc mb`.
