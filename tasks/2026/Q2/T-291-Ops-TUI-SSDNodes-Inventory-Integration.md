# T-291: Ops TUI — Integração do Servidor SSD Nodes no Inventário de Infraestrutura e TUI

- **Status**: Backlog
- **Priority**: 🔵 Medium
- **Owner**: Antigravity
- **Epic**: Infrastructure / Operations
- **Est**: 4h

## Context

Precisamos registrar o novo servidor da SSD Nodes (`ssdnodes-6a12f10c9ef11` / `104.225.218.78`) nas ferramentas de operações e TUI locais (`k8s_ops_menu.sh`), chaves SSH e documentação de infraestrutura. Isso garante que qualquer agente ou operador humano possa gerenciar a máquina com a mesma facilidade que os nós da OCI e o runner da Hetzner.

## Tasks

- [ ] Registrar as credenciais do servidor em local seguro e chaves (garantindo que o arquivo `.ssdnodes.creds` seja preservado e ignorado pelo git)
- [ ] Configurar alias e credenciais de acesso SSH no arquivo de configuração do usuário (`~/.ssh/config` ou chaves autorizadas) para habilitar acesso via `ssh ssdnodes-monstro` sem senhas interativas
- [ ] Adicionar o servidor SSD Nodes no script de menu TUI (`oci-k8s-cluster/k8s_ops_menu.sh`), incluindo-o nos testes de conectividade e status de nós do inventário
- [ ] Atualizar o `AGENTS.md` para descrever o novo servidor no mapa de infraestrutura do cluster/frota
- [ ] Executar testes de conectividade pela TUI para validar que o inventário de nós físicos responde como "Green"
