# DNS — `honeypot.dnor.io` (GoDaddy)

Pré-requisito para **Let's Encrypt** na EC2 `aws-ec2-fleet-01` (T-302 Fase B).

## Contexto

- **Zona:** `dnor.io` — NS `ns75.domaincontrol.com` / `ns76.domaincontrol.com` (GoDaddy)
- **Alvo:** `3.236.249.77` (IP público EC2 honeypot)
- **TTL recomendado:** 600s (10 min) durante cutover; depois 3600s

## Via API (automatizado)

Credenciais em `.env.godaddy` (não commitar — ver `.gitignore`):

```bash
./scripts/aws-fleet/configure-qdbback-dns-godaddy.sh
./scripts/aws-fleet/deploy-qdbback-ec2.sh --phase dns-check
```

## Passos manuais no GoDaddy

1. Acesse [GoDaddy DNS](https://dcc.godaddy.com/control/dnor.io/dns)
2. **Add** → tipo **A**
3. Preencha:
   - **Name / Host:** `honeypot`
   - **Value / Points to:** `3.236.249.77`
   - **TTL:** 600 seconds
4. Salve e aguarde propagação (1–15 min típico)

## Validar

```bash
./scripts/aws-fleet/deploy-qdbback-ec2.sh --phase dns-check
# ou manualmente:
dig +short honeypot.dnor.io A
# esperado: 3.236.249.77
```

## Após DNS OK

```bash
./scripts/aws-fleet/deploy-qdbback-ec2.sh --phase letsencrypt --tls-domain honeypot.dnor.io
curl -sI https://honeypot.dnor.io/ | grep -i issuer
```

## Pós-TLS (opcional)

Atualizar `instance_host` em `config/external-fleet/registry.yaml` de IP → `honeypot.dnor.io`, regenerar artefatos e redeploy `rs-observability-api` para scrape/cards usarem hostname confiável.
