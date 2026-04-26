# T-151: Ingress Edge Decoupling from Master

- **Status**: Backlog
- **Priority**: High
- **Epic/Owner**: Infra
- **Estimation**: 4h

## Context
Durante a execucao da [T-150](T-150-Master-Rootfs-Dependency-Reduction.md), a borda do cluster foi
validada como dependente do `k8s-master` de forma direta:

- o `ingress-nginx-controller` continua com `hostNetwork: true`, `replicas: 1` e
  `nodeSelector: k8s-master` em [components/ingress-nginx/deploy.yaml](../../../components/ingress-nginx/deploy.yaml);
- o `Service` continua `type: LoadBalancer` com `externalTrafficPolicy: Local`;
- no estado live de 2026-04-25, o `k8s-master` era o unico node ouvindo `80/443` para a borda,
  enquanto os workers nao expunham essas portas do ingress.

Isso significa que a borda atual nao pode ser repinada do master por tentativa e erro. Antes de mover
o `ingress-nginx-controller` para workers, precisamos descobrir qual path externo realmente entrega
trafego para `*.dnor.io` e qual rewire de edge e necessario para preservar disponibilidade.

## Objective
Separar a borda HTTP/TCP do cluster da dependencia hard no `k8s-master`, sem quebrar o acesso atual a
`80/443` e sem assumir um `LoadBalancer` que nao esteja efetivamente presente.

## Tasks
- [ ] Mapear o path de entrada atual para `*.dnor.io`: DNS, Tailscale/CoreDNS, IP publico, listeners
	locais e qualquer dependencia oculta do master.
- [ ] Confirmar se existe ou nao um `LoadBalancer` funcional de verdade na borda, em vez de assumir
	que o `Service type=LoadBalancer` esta entregando trafego.
- [ ] Definir a topologia alvo do ingress fora do master: workers-only, worker-preferred com fallback
	ou edge separado dedicado.
- [ ] Versionar a mudanca de IaC do ingress com rollback explicito.
- [ ] Validar a topologia nova com drill simples: listeners em worker, readiness do deployment,
	acesso funcional a um host `*.dnor.io` e watchdog sem regressao.

## References
- [T-150](T-150-Master-Rootfs-Dependency-Reduction.md)
- [components/ingress-nginx/deploy.yaml](../../../components/ingress-nginx/deploy.yaml)
