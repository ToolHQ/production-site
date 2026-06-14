# T-343: SSDNodes Jenkins — reverse proxy + security hardening

- **Status**: Done
- **Priority**: 🔼 High
- **Owner**: Cursor / AI Radar
- **Epic**: T-341 SSDNodes CI Platform
- **Est**: 1d
- **Criado**: 2026-06-06

## Research

### Reverse proxy broken (Manage Jenkins)

**Sintoma:** banner vermelho *"It appears that your reverse proxy set up is broken"*.

**Causa raiz (este deploy):**
- Ingress nginx está em `jenkins-ingress.yaml` separado (`controller.ingress.enabled: false`).
- O chart **não** auto-preenche `jenkinsUrl` quando ingress interno está off.
- Jenkins gera redirects com URL interna (`:8080`) ≠ URL pública (`https://jenkins.ssdnodes.dnor.io`).

**Fix IaC (SonarSource/Jenkins docs + helm-charts #15672):**
1. `controller.jenkinsUrl` + JCasC `unclassified.location.url` → mesma URL HTTPS pública (com `/` final).
2. Ingress nginx já tem `use-forwarded-headers: true` (`nginx-ingress-values.yaml`).

### CSP (Content Security Policy)

**Sintoma:** banner azul recomendando CSP.

**Fix:** `initScripts` + CSP nativo Jenkins 2.567 (`Content-Security-Policy-Report-Only` no /login).

### Postura T-341 (checklist)

| Controle | IaC |
|----------|-----|
| Signup desabilitado | JCasC `allowsSignup: false` ✓ |
| Agent listener ClusterIP | `agentListenerServiceType: ClusterIP` ✓ |
| CSRF crumbs | chart default ✓ |
| Markup plain text | `markupFormatter: plainText` |
| Remember-me off | `disableRememberMe: true` |
| API tokens legacy off | JCasC `apiToken.*` |
| Remoting security | JCasC `remotingSecurity.enabled` |
| NetworkPolicy ingress | `ci-network-policies.yaml` ✓ |

## Plan

1. `jenkins-values.yaml` — jenkinsUrl, location JCasC, CSP, tokens, remoting
2. `jenkins-ingress.yaml` — annotations redirect/ssl/websocket
3. `validate_ssdnodes_ci.sh` — versões IaC, redirect sem :8080, CSP header, Sonar version
4. Deploy + harness live
5. PR #394

## Tasks

- [x] Research + task T-343
- [x] IaC jenkins-values + ingress
- [x] Harness estendido
- [x] Deploy live + validação reverse proxy
- [x] Commit/push PR #394
- [x] done T-343 (harness PASS 2026-06-09)

## Validação

```bash
bash scripts/harness/validate_ssdnodes_ci.sh
# UI: Manage Jenkins — sem banner reverse proxy
curl -fsSI https://jenkins.ssdnodes.dnor.io/login | grep -i content-security-policy
```
