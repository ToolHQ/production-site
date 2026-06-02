# T-331: SSDNodes — SSH alias canônico no ~/.ssh/config

- **Status**: Done (2026-06-01)
- **Priority**: Medium
- **Epic**: T-330 follow-up
- **Estimation**: 30min

## Contexto

T-330 usa hostname `ssdnodes-6a12f10c9ef11` em UI/registry. Scripts ops ainda resolvem SSH via alias legado `ssdnodes-monstro`.

## Tasks

- [x] Snippet `components/ssdnodes/ssh-config.snippet` + `install_ssdnodes_ssh_config.sh`
- [x] `Host ssdnodes-6a12f10c9ef11` em `~/.ssh/config` (idempotente)
- [x] `ssdnodes-monstro` mantido no snippet (compat)
- [x] Remover `_ssh_alias_for` de `ufw_manager.sh`
- [x] Defaults `REMOTE_HOST` / `TARGET_HOST` → hostname canônico nos scripts fleet/ssdnodes
- [x] Documentar em `components/ssdnodes/README.md`

## DoD

- `ssh ssdnodes-6a12f10c9ef11 hostname -f` → `ssdnodes-6a12f10c9ef11`
- Nenhum script default `REMOTE_HOST=ssdnodes-monstro` (legado só em inventário UFW / comentários)
