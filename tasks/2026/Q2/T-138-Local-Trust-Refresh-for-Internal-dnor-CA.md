# T-138: Local Trust Refresh for Internal dnor CA

- **Status**: Done
- **Priority**: 🔼 High
- **Epic/Owner**: DevExp / TLS
- **Estimation**: 1h

## Context
O erro de TLS em `reports.dnor.io` não estava no `cert-manager` nem no `Ingress` do cluster.
O diagnóstico mostrou que:

- `reports-ingress-tls` e `my-site-ingress-tls` estão `Ready`, com folhas válidas até julho de 2026
- a CA atual do cluster em `cert-manager/dnor-root-ca-tls` bate com o arquivo versionado
	`oci-k8s-cluster/dnor-ca-issuer.crt`
- a workstation local ainda confiava numa cópia antiga de `dnor-root-ca`, expirada em fevereiro de 2026
- `reports.dnor.io` nem possui DNS público; o acesso do operador acontece via `/etc/hosts` + túnel local

Na prática, o problema real é drift de trust local. Como a correção global do sistema exige `sudo` e o
ambiente atual não oferece `sudo -n`, a solução desta task é consertar o fluxo de trabalho oficial do repo
para sempre exportar um CA bundle combinado (roots do sistema + `dnor-root-ca` atual) ao iniciar
`oci-k8s-cluster/scripts/setup-dev-deploy.sh`.

### Arquivos centrais

- `oci-k8s-cluster/scripts/setup-dev-deploy.sh`
- `oci-k8s-cluster/dnor-ca-issuer.crt`

## Tasks
- [x] Confirmar se a falha vinha de CA local antiga e não de certificado emitido pelo cluster
- [x] Implementar bundle local com roots do sistema + CA interna atual no setup canônico de deploy
- [x] Validar `curl` e OpenSSL usando apenas o ambiente exportado pelo `setup-dev-deploy.sh`
- [x] Registrar resultado final e mover a task para Done

## Entrega

- `oci-k8s-cluster/scripts/setup-dev-deploy.sh` agora detecta o bundle público do sistema,
	concatena esse bundle com `oci-k8s-cluster/dnor-ca-issuer.crt` e exporta o resultado para
	`CURL_CA_BUNDLE`, `SSL_CERT_FILE`, `REQUESTS_CA_BUNDLE` e `AWS_CA_BUNDLE`
- o fluxo também exporta `NODE_EXTRA_CA_CERTS` com a CA interna atual, reduzindo atrito em clientes Node
- o bundle combinado é gerado em `tmp/ca-bundles/system-plus-dnor-ca.pem`, fora do versionamento normal

## Validação

- após `source oci-k8s-cluster/scripts/setup-dev-deploy.sh`, o ambiente passou a expor as variáveis de CA
	apontando para o bundle combinado gerado localmente
- `curl --resolve reports.dnor.io:443:127.0.0.1 https://reports.dnor.io/ -I` respondeu `HTTP 200` sem `-k`
- `curl --resolve dnor.io:443:127.0.0.1 https://dnor.io/ -I` respondeu `HTTP 200` sem `-k`
- `openssl s_client` para `reports.dnor.io` e `dnor.io` passou a retornar `Verification: OK` e
	`Verify return code: 0 (ok)` quando executado no ambiente sourced

## Risco residual

- a trust store global da workstation continua com a raiz antiga e expirada; a correção sistêmica ainda
	exigiria `sudo` ou import explícito na store do SO/browser
- a correção entregue nesta task resolve o fluxo oficial de operação do repo sem depender de privilégio root
