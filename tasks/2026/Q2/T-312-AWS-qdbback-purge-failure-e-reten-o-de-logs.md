# T-312: AWS qdbback purge failure e retenção de logs

- **Status**: Backlog
- **Priority**: 🔼 High
- **Epic/Owner**: Cursor / AI Radar
- **Estimation**: 4h

## Context

A EC2 honeypot `aws-ec2-fleet-01` está operacional (`qdbback.service` e `node_exporter.service` Running), mas `qdbback-purge.service` está failed. O disco está em 76% (`6.1G/8G`), ainda aceitável, mas em uma instância pequena sem swap a falha de purge pode virar saturação rapidamente.

A correção deve manter o honeypot observável e o retention de logs/eventos reproduzível via IaC/runbook, alinhado à T-302/T-296.

## Tasks

- [ ] Coletar logs completos de `qdbback-purge.service` e timer associado.
- [ ] Identificar quais diretórios/tabelas/logs deveriam ser purgados e política de retenção esperada.
- [ ] Corrigir script/unit no source versionado de qdbback/AWS fleet.
- [ ] Garantir que purge seja seguro para evidência do honeypot: não apagar dados recentes sem backup/critério.
- [ ] Adicionar validação ao runbook T-302: status de purge, disco e contagem de eventos.
- [ ] Aplicar e validar na EC2, com `systemctl reset-failed` apenas depois da correção.

## Validação

```bash
ssh aws-ec2-fleet-01 "systemctl status qdbback-purge.service --no-pager"
ssh aws-ec2-fleet-01 "df -h /; systemctl --failed --no-pager"
```

Critério de aceite: purge sem failed, disco sob controle e retenção documentada.
