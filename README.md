# production-site

Trial of pre production and production tools like (minikube, jenkins, sonar, minio, postgres on k8s, backup tools etc)

## Quality Harness

O repositório usa um harness raiz leve e path-aware em [tools/harness/verify.sh](/home/dnorio/production-site/tools/harness/verify.sh).

Comandos principais:

- `./tools/harness/verify.sh verify-changed`
- `./tools/harness/verify.sh verify-all`

Contrato atual de entrega:

- toda alteração de código deve trazer evidência em `## Validação` no task file correspondente
- o mínimo para fechamento de task técnica é passar no `verify-changed` compatível com o escopo alterado
- smoke/deploy fica separado do verify local e só entra quando a task mexe em publicação, manifesto ou contrato exposto
