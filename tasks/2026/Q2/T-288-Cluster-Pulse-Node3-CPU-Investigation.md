# T-288: Cluster Pulse — Investigação e Mitigação de Alta CPU (100%) no Nó k8s-node-3

- **Status**: Backlog
- **Priority**: 🚨 Critical
- **Owner**: Antigravity
- **Epic**: Cluster Pulse / Observability
- **Est**: 4h

## Context

O nó `k8s-node-3` do cluster OCI (ARM64, 1 vCPU e 6GB RAM) está operando no limite máximo de CPU (100% de uso sustentado), gerando lentidão e alertas críticos de CPU no painel Cluster Pulse. Precisamos isolar os processos causadores e readequar os workloads para estabilizar o nó.

## Tasks

- [ ] Acessar o nó `k8s-node-3` via SSH (`ssh oci-k8s-node-3`) e rodar `htop` ou `top` para identificar os processos consumidores na máquina host
- [ ] Rodar `kubectl get pods -A -o wide | grep k8s-node-3` de dentro do master para listar todos os pods agendados no nó 3
- [ ] Inspecionar logs e uso de recursos dos pods suspeitos no namespace `observability`, `default` e `ai-radar` agendados no nó 3
- [ ] Verificar se há ocorrência de swapping severo devido a limites de memória estourados
- [ ] Readequar os limites/requests de CPU no deployment dos workloads causadores ou rodar `kubectl drain k8s-node-3` temporariamente para aliviar o nó
- [ ] Validar no dashboard se a CPU do nó 3 estabilizou abaixo de 80%
