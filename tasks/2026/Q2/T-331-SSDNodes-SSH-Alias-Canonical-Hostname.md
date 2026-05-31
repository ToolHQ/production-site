# T-331: SSDNodes — SSH alias canônico no ~/.ssh/config

- **Status**: Backlog
- **Priority**: Medium
- **Epic**: T-330 follow-up
- **Estimation**: 30min

## Contexto

T-330 usa hostname `ssdnodes-6a12f10c9ef11` em UI/registry. Scripts ops ainda resolvem SSH via alias legado `ssdnodes-monstro`.

## Tasks

- [ ] Adicionar em `~/.ssh/config`:
  ```sshconfig
  Host ssdnodes-6a12f10c9ef11
      HostName 104.225.218.78
      User ubuntu
      IdentityFile ~/.ssh/oci-ssh-key-2025-06-19.key
  ```
- [ ] Opcional: manter `Host ssdnodes-monstro` como `ProxyJump` ou remover após migrar scripts
- [ ] Remover `_ssh_alias_for` de `ufw_manager.sh` quando `ssh ssdnodes-6a12f10c9ef11` funcionar direto
- [ ] Documentar em `components/ssdnodes/README.md`

## DoD

- `ssh ssdnodes-6a12f10c9ef11 hostname -f` → `ssdnodes-6a12f10c9ef11`
- Nenhum script default `REMOTE_HOST=ssdnodes-monstro`
