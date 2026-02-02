---
name: Deploy Service
description: Padrão "Build & Apply" usando deploy.sh.
---

# Deployment Workflow

Todo serviço em `apps/<service>` possui um `deploy.sh`.

```bash
#!/bin/sh
TAG=$(date +%s)
docker buildx build ... -t image:$TAG
docker push image:$TAG
sed -i "s|image: .*|image: ...:$TAG|" k8s/deploy.yaml
kubectl apply -f k8s/deploy.yaml
```

**Regras**:
1. Sempre use `./deploy.sh` na raiz do serviço.
2. Não comite o arquivo YAML pós-sed (com a tag numérica).
3. O script cuida do `docker push` para o Nexus local (`nexus.localhost`).
