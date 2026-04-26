# T-151: Ingress Edge Decoupling from Master

- **Status**: In Progress
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
- [x] Mapear o path de entrada atual para `*.dnor.io`: DNS, Tailscale/CoreDNS, IP publico, listeners
	locais e qualquer dependencia oculta do master.
- [x] Confirmar se existe ou nao um `LoadBalancer` funcional de verdade na borda, em vez de assumir
	que o `Service type=LoadBalancer` esta entregando trafego.
- [x] Definir a topologia alvo do ingress fora do master: workers-only, worker-preferred com fallback
	ou edge separado dedicado.
- [x] Versionar a mudanca de IaC do ingress com rollback explicito.
- [ ] Validar a topologia nova com drill simples: listeners em worker, readiness do deployment,
	acesso funcional a um host `*.dnor.io` e watchdog sem regressao.

## Execution Notes (2026-04-26)

- Path atual confirmado:
	- `ingress-nginx-controller` original permanece em `hostNetwork: true`, pinned no `k8s-master`.
	- DNS publico dos hosts `*.dnor.io` resolve para `3.33.130.190` e `15.197.148.33`.
	- Service `ingress-nginx-controller` segue `type=LoadBalancer` com `EXTERNAL-IP <pending>` (sem OCI LB funcional).
- Topologia alvo adotada para mitigacao sem downtime: `worker-preferred com fallback`.
- IaC versionada em `components/ingress-nginx/deploy.yaml`:
	- adicionado deployment canario `ingress-nginx-controller-workers` com `replicas: 1`.
	- `hostNetwork: true` mantido para preservar bind em `80/443`.
	- `nodeAffinity` com `NotIn: k8s-master` para forcar worker.
	- rollback explicito no comentario do manifesto:
		- `kubectl -n ingress-nginx delete deploy ingress-nginx-controller-workers`
- Validacao concluida ate aqui:
	- rollout `ingress-nginx-controller-workers` `1/1 Available`.
	- pod worker em `k8s-node-2` com IP `10.0.1.50`.
	- Service endpoints incluem master e worker.
	- listeners `:80/:443` presentes em `k8s-master` e `k8s-node-2`.

## Remaining to Close

- Drill funcional fim-a-fim de host `*.dnor.io` no novo caminho de edge.
- Validacao de watchdog/observability sem regressao apos a mudanca.

## References
- [T-150](T-150-Master-Rootfs-Dependency-Reduction.md)
- [components/ingress-nginx/deploy.yaml](../../../components/ingress-nginx/deploy.yaml)
