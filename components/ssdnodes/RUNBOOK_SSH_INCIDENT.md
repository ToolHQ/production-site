# Runbook: Resposta a Incidentes SSH e Brute Force (SSDNodes)

Este runbook define os passos para diagnosticar, mitigar e analisar tentativas de invasão via porta 22 no servidor `ssdnodes-monstro`, que opera exposto para ingress da web e acesso Tailscale.

## 1. Identificando a Ameaça

A monitoria base do cluster já isola o `sshd` do K8s e do runner GitHub Actions (que é outbound-only). No entanto, o `sshd` público pode receber scans pesados.

Para verificar se estamos sob ataque e se o `fail2ban` está mitigando:

```bash
# Conecte ao nó (idealmente via Tailscale ou IP OCI)
ssh ssdnodes-monstro

# Verifique o status da jail do SSH
sudo fail2ban-client status sshd

# Liste os IPs atualmente banidos
sudo fail2ban-client get sshd banned
```

## 2. Analisando os Logs

Para quantificar a taxa de `auth failures` e identificar o padrão de ataque:

```bash
# Top 10 IPs tentando acesso
journalctl -u ssh --since "24 hours ago" | grep "Failed password" | awk '{print $(NF-3)}' | sort | uniq -c | sort -nr | head -10

# Top 10 usuários tentados
journalctl -u ssh --since "24 hours ago" | grep "Invalid user" | awk '{print $(NF-2)}' | sort | uniq -c | sort -nr | head -10
```

## 3. Mitigação Manual (Bloqueio Físico no UFW)

O `fail2ban` age automaticamente com bantime de 24h. No entanto, se uma sub-rede inteira (ex: botnet) estiver atacando em bloco e exaurindo sockets, bloqueie no UFW:

```bash
# Bloquear IP específico
sudo ufw deny from 1.2.3.4 to any port 22

# Bloquear range CIDR (ex: botnet regional)
sudo ufw deny from 185.100.0.0/16 to any port 22

# Recarregar as regras (o ufw_manager.sh preservará bloqueios manuais na base)
sudo ufw reload
```

## 4. O "Nuclear Option" (Tailscale-only SSH)

Se o ataque for volumétrico ao ponto de ameaçar o host (esgotamento de file descriptors ou CPU):

1. Confirme que sua máquina está conectada ao Tailscale (`100.x.x.x`).
2. Acesse o servidor e bloqueie a porta 22 pública no UFW, permitindo apenas a interface Tailscale:

```bash
# O script ufw_manager.sh já tem a porta 22 bloqueada por default se não explicitado.
# Remova a regra global de ALLOW 22.
sudo ufw delete allow 22/tcp

# Garanta acesso via Tailscale
sudo ufw allow in on tailscale0 to any port 22

sudo ufw reload
```

## 5. Critérios de Avaliação

- **Falso Positivo**: Alguém da equipe errando a chave. O `fail2ban` bane após 4 tentativas. Para desbanir: `sudo fail2ban-client set sshd unbanip 1.2.3.4`.
- **Risco Real**: Exploração de CVEs no OpenSSH. Se uma CVE 0-day for anunciada no `sshd`, execute a "Nuclear Option" imediatamente até o patch ser aplicado.
