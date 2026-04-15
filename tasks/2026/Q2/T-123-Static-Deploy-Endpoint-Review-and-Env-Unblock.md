# T-123 — Static Deploy: endpoint review + env unblock

**Status**: ✅ Done  
**Priority**: 🚨 Critical  
**Epic**: DevOps / TUI  
**Estimate**: 2h  
**Created**: 2026-04-13  
**Depends on**: T-122 (primeiro fluxo TUI de static deploy)  
**Blocks**: publicação real do frontend estático pela TUI

---

## Contexto

Após a primeira implementação do deploy do `apps/static` na TUI, a validação real
mostrou que o fluxo ainda carrega premissas antigas de ambiente local/minikube e
por isso falha antes mesmo de executar o upload.

O log persistido `logs/tui-app-deploy/20260414_094701_static_build-and-upload.log`
mostra a quebra atual:

```text
ERROR: minio.localhost is not resolvable on this host
```

O inventário desta revisão confirmou os seguintes gaps:

1. **Endpoint incorreto no fluxo ativo do static**
   - `apps/static/package.json` ainda usa `aws --endpoint-url http://minio.localhost`
   - `oci-k8s-cluster/k8s_ops_menu.sh` exige resolução local de `minio.localhost`
   - porém o cluster já expõe MinIO externamente por **`minio.dnor.io`** em
     `components/minio/minio-resources.yaml`

2. **Ambiguidade de endpoint entre contexto externo e interno**
   - consumidores dentro do cluster usam `minio-service.minio.svc.cluster.local:9000`
   - o operador da TUI roda fora do cluster e precisa de um endpoint operacional
     explícito, com protocolo/TLS definidos

3. **Script legado divergente**
   - `apps/static/upload.sh` ainda aponta para `minio.localhost`
   - além disso, faz sync de `./static`, enquanto o fluxo atual da TUI/package usa
     `./dist`, o que indica drift funcional e não só de hostname

4. **Referências legadas que não devem contaminar OCI**
   - `apps/docker-compose.yaml`
   - `apps/py-back-end/.env`
   - `apps/py-back-end/k8s/minikube/my-site-py-back-end.yaml`
   Esses pontos ainda usam `minio.localhost`, mas pertencem ao contexto local/minikube
   e devem ser separados do fluxo operacional OCI em vez de alterados cegamente

5. **Pré-requisitos operacionais ainda não explicitados**
   - disponibilidade do `aws` CLI
   - resolução DNS do host canônico
   - trust da CA/TLS se o upload passar a usar `https://minio.dnor.io`

Esta task existe para consolidar um endpoint canônico para o deploy estático pela
TUI, remover falsas dependências de laboratório local e deixar claro o que é OCI
real, o que é tráfego in-cluster e o que permanece como compatibilidade minikube.

---

## Critérios de Aceite

1. O endpoint canônico do static deploy fica explicitamente definido para o operador da TUI, incluindo protocolo (`http`/`https`) e rationale
2. `apps/static` e a TUI deixam de depender de `minio.localhost` para o fluxo OCI atual
3. `apps/static/upload.sh` fica alinhado com o artefato correto (`dist`) ou é explicitamente descontinuado
4. O mecanismo de upload valida DNS/URL corretos para o ambiente OCI sem bloquear por checks de ambiente legado
5. Os pré-requisitos operacionais necessários (`aws`, trust TLS/CA, acesso ao endpoint) ficam claros e verificáveis
6. As referências que devem continuar locais/minikube ficam documentadas para evitar regressão
7. O deploy do static volta a ser executável pela TUI no ambiente real

---

## Tasks

- [x] Inventariar as referências atuais a `minio.localhost` e separar impacto OCI vs legado minikube/local
- [x] Decidir o endpoint operacional canônico do upload pela TUI (`https://minio.dnor.io`, `http://minio.dnor.io` ou alternativa validada) e registrar a razão
- [x] Revisar `apps/static/package.json` para usar o endpoint canônico sem depender de host local legado
- [x] Corrigir `apps/static/upload.sh` para o mesmo endpoint e o mesmo diretório artefato do fluxo atual (`dist`), ou aposentar o script se ele não for mais a interface oficial
- [x] Ajustar as pré-checagens do `oci-k8s-cluster/k8s_ops_menu.sh` para validar o endpoint real em vez de `minio.localhost`
- [x] Definir como a TUI lida com trust TLS/CA para `minio.dnor.io` sem workaround frágil nem falso positivo de ambiente
- [x] Documentar explicitamente quais referências a `minio.localhost` permanecem válidas apenas para minikube/local (`docker-compose`, `.env`, manifests de minikube)
- [x] Validar uma publicação real do `apps/static` e confirmar que o nginx serve os assets atualizados

---

## Arquivos Afetados

| Arquivo | Mudança esperada |
| --- | --- |
| `apps/static/package.json` | trocar endpoint antigo por `minio.dnor.io` |
| `apps/static/upload.sh` | alinhar endpoint e diretório sincronizado com o fluxo oficial |
| `oci-k8s-cluster/k8s_ops_menu.sh` | corrigir pré-checagens e mensagens do static deploy |
| `tasks/2026/Q2/T-122-TUI-Static-Deploy-to-MinIO.md` | referenciar o desdobramento do unblock operacional, se necessário |
| `tasks/2026/Q2/T-123-Static-Deploy-Endpoint-Review-and-Env-Unblock.md` | registrar decisão operacional e validação |

---

## Notas

- Evidências desta revisão:
  - `logs/tui-app-deploy/20260414_094701_static_build-and-upload.log`
  - `apps/static/package.json`
  - `apps/static/upload.sh`
  - `oci-k8s-cluster/k8s_ops_menu.sh`
  - `components/minio/minio-resources.yaml`
- `components/minio/minio-resources.yaml` já expõe `minio.dnor.io`, então o fluxo de deploy do static precisa convergir para esse host ou registrar claramente outra rota operacional suportada.
- Parte das referências a `minio.localhost` deve permanecer apenas para ambientes locais/minikube; a task precisa evitar quebrar esses casos por acidente.
- O gap não é só DNS: existe também drift entre o artefato que o fluxo oficial publica (`dist`) e o diretório usado pelo script legado (`static`).
- Decisão aplicada nesta task: o deploy estático operado pela TUI passa a usar `https://minio.dnor.io` por padrão, com fallback automático do `AWS_CA_BUNDLE` para `oci-k8s-cluster/dnor-ca-issuer.crt` quando o operador ainda não exportou a variável no shell.
