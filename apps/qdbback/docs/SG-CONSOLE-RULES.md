# Security Group — regras qdbback (Fase 2)

**SG:** `sg-06a97865399016318` (`securitygroup-dnorio-us`)  
**Instância:** `i-0e8ca7a9b50e474a9` (`3.236.249.77`)

A app escuta **80/443** em produção (portas HTTP/HTTPS padrão — onde scanners batem).

| Porta app | Função |
|-----------|--------|
| 80 | HTTP → redirect 301 para HTTPS |
| 443 | HTTPS honeypot (logging SQLite) |
| 3500 | Admin dashboard (HTTPS, restrito ao operador) |

## Via Console AWS

[Editar SG `sg-06a97865399016318`](https://us-east-1.console.aws.amazon.com/ec2/home?region=us-east-1#SecurityGroup:groupId=sg-06a97865399016318) → **Edit inbound rules**:

| Type | Port | Source | Description |
|------|------|--------|-------------|
| HTTP | 80 | `0.0.0.0/0` | qdbback-http-honeypot |
| HTTPS | 443 | `0.0.0.0/0` | qdbback-https-honeypot |
| Custom TCP | 3500 | `189.62.149.233/32` | qdbback-admin-https |

Manter regras existentes (`:22`, `:9100` OCI).

## Validar

```bash
curl -s -o /dev/null -w '%{http_code}\n' http://3.236.249.77/      # 301
curl -sk -o /dev/null -w '%{http_code}\n' https://3.236.249.77/   # 200
./scripts/aws-fleet/validate-qdbback-logging.sh
```
