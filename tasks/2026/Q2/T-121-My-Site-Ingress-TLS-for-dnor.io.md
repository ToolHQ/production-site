# T-121 — My Site Ingress: TLS para `dnor.io`

**Status**: ✅ Done  
**Priority**: 🚨 Critical  
**Epic**: DevOps  
**Estimate**: 2h  
**Created**: 2026-04-13  
**Depends on**: T-120 (nginx image novamente deployável)  
**Blocks**: acesso confiável ao site no browser

---

## Contexto

O app `nginx` voltou a responder em `dnor.io`, mas o browser ainda apresenta problema
de certificado. A análise do repositório mostrou dois pontos:

1. O Ingress de `apps/nginx/k8s/my-site-nginx.yaml` publica o host `dnor.io`
2. Esse manifesto não possui `spec.tls` nem annotation `cert-manager.io/cluster-issuer`

Além disso, o bootstrap TLS do cluster em `oci-k8s-cluster/setup_k8s_cluster.sh`
aplica `dnor-ca-issuer` para vários Ingresses conhecidos, porém não inclui
`my-site-ingress`. Ou seja: o site principal ainda não está integrado ao padrão
de certificados internos `*.dnor.io`.

Esta task existe para fechar esse gap e deixar `dnor.io` servido com TLS pelo
`cert-manager`, usando a CA interna do cluster, além de documentar o passo de
confiança da CA no browser local.

---

## Critérios de Aceite

1. `apps/nginx/k8s/my-site-nginx.yaml` passa a declarar TLS para `dnor.io`
2. O Ingress recebe emissão via `cert-manager.io/cluster-issuer: dnor-ca-issuer`
3. O cluster gera `Certificate`/`Secret` válidos para o host do site
4. O site abre por `https://dnor.io` sem erro de certificado após confiar na CA raiz
5. O fluxo de export/import da CA fica registrado no task file ou documentação associada

---

## Tasks

- [x] Mapear o estado atual do `my-site-ingress` e confirmar ausência de `spec.tls` / annotation do cert-manager
- [x] Ajustar `apps/nginx/k8s/my-site-nginx.yaml` para incluir TLS com `dnor-ca-issuer`
- [x] Avaliar se `oci-k8s-cluster/setup_k8s_cluster.sh` também deve passar a patchar `my-site-ingress`
- [x] Aplicar a mudança no cluster e verificar criação de `Certificate`, `Secret` e readiness do Ingress
- [x] Exportar ou reaproveitar a CA raiz `dnor-ca-issuer` para import no browser local
- [x] Validar acesso a `https://dnor.io` e registrar resultado final

---

## Arquivos Afetados

| Arquivo | Mudança esperada |
| --- | --- |
| `apps/nginx/k8s/my-site-nginx.yaml` | adicionar annotation e bloco TLS para `dnor.io` |
| `oci-k8s-cluster/setup_k8s_cluster.sh` | opcionalmente incluir `my-site-ingress` no patch padrão de TLS |
| `tasks/2026/Q2/T-121-My-Site-Ingress-TLS-for-dnor.io.md` | registrar diagnóstico, trust da CA e validação |

---

## Notas

- O cluster usa CA interna (`dnor-ca-issuer`), não ACME público.
- Mesmo com o certificado interno emitido corretamente, o browser só vai parar de alertar após confiar na CA raiz exportada do cluster quando esse certificado for o apresentado ao cliente.
- A TUI já possui fluxo de export da CA em `Security & TLS`.
- O arquivo versionado `oci-k8s-cluster/dnor-ca-issuer.crt` não bate com a CA atual do cluster; para trust local, exportar novamente do secret `cert-manager/dnor-root-ca-tls` ou via TUI.
- Atualização aplicada: `my-site-ingress-tls` foi emitido com sucesso para `DNS:dnor.io`, e o arquivo `oci-k8s-cluster/dnor-ca-issuer.crt` foi refreshado a partir da CA atual do cluster.
- Validação real em 2026-04-15: o Ingress do cluster segue com `cert-manager.io/cluster-issuer: dnor-ca-issuer` e `Certificate` Ready, mas o endpoint publico `https://dnor.io` hoje apresenta certificado valido da cadeia GoDaddy. Ou seja: o acesso confiavel no browser foi resolvido do ponto de vista do usuario, ainda que a borda publica nao esteja expondo a CA interna.
