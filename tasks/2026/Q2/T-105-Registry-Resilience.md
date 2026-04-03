# T-105: Internal Registry (Nexus) Resilience

**Status**: [ ] Backlog | **Priority**: 🔽 Medium | **Owner**: Infra | **Est**: 2h

## 🎯 Objective
When Nexus was down for 19 days (stuck in `Init:0/1`), `postgres-1` failed with `ErrImagePull`
because it pulls its image from `registry.local:31444` (the internal Nexus registry). Any
workload using custom-built or proxied images becomes a single-point-of-failure dependency
on Nexus availability.

Reduce the blast radius of Nexus downtime so critical stateful workloads (postgres, etc.)
can restart independently.

## 🔍 Problem Analysis

### Dependency Chain
```
postgres-1 restart → pull image from registry.local:31444 → Nexus down → ErrImagePull
```

### Affected workloads
All pods using images from `registry.local:31444` (the Nexus Docker registry):
- `postgres` (custom Alpine image with extensions)
- `back-end` (Node.js app image)
- `py-back-end` (Python app image)
- `rs-axum-back-end` (Rust app image)
- Any image built locally and pushed to Nexus

### Non-affected
Pods using public images directly (`registry.k8s.io`, `docker.io`) — these were fine during
the outage and should be preferred for infrastructure components.

## 📋 Execution Plan

### Phase 1: Audit Image Pull Sources
- [ ] List all running pods and their image sources: `kubectl get pods -A -o jsonpath='{range .items[*]}{.spec.containers[*].image}{"\n"}{end}' | sort -u`
- [ ] Classify each image: public registry vs `registry.local` vs `nexus.dnor.io`
- [ ] Identify critical stateful workloads that use internal images (highest risk)

### Phase 2: `imagePullPolicy` Audit & Fix
Kubernetes `imagePullPolicy: IfNotPresent` means the node uses a cached image if available,
only pulling when the image is missing. `Always` forces a pull on every pod start.

- [ ] Audit all Deployments/StatefulSets for `imagePullPolicy` setting
- [ ] For stable, versioned images (postgres, infrastructure): change to `IfNotPresent`
  - Once pulled once per node, Nexus downtime won't affect restarts
  - Risk: stale images — mitigated by using explicit image tags (not `latest`)
- [ ] For app images that change frequently: keep `IfNotPresent` but ensure image tags are
  immutable (no reuse of the same tag for different content)
- [ ] Document which images use which policy and why

### Phase 3: Pre-Pull Critical Images on All Nodes
For the most critical stateful workloads (postgres, etc.), ensure the image is pre-pulled
on all worker nodes so restarts never depend on Nexus being up.

- [ ] Identify the postgres image tag currently in use
- [ ] Add a DaemonSet or init Job that pre-pulls critical images on all nodes on cluster startup
- [ ] Alternatively: add a manual pre-pull step to `k8s_ops_menu.sh` under "Maintenance"
- [ ] Verify: with Nexus down, `kubectl delete pod postgres-0 -n postgres` → pod restarts
  successfully using cached image

### Phase 4: Nexus Health Integration
- [ ] Add Nexus pod readiness to T-102 watchdog: alert if Nexus is not ready
- [ ] Add Nexus to TUI "Port Forward" menu with health check URL
- [ ] Verify the Nexus `readinessProbe` in `components/nexus/nexus.yaml` is properly configured
  and actually checks registry API (not just HTTP 200 on root)

## ✅ Definition of Done
- [ ] All stateful workloads use `imagePullPolicy: IfNotPresent` with explicit versioned tags
- [ ] Critical images (postgres, etc.) are pre-pulled on all nodes
- [ ] With Nexus at 0 replicas: `kubectl delete pod postgres-0` → pod restarts successfully
- [ ] Nexus health included in T-102 watchdog output

## 🔗 Context
- `postgres-1` failed with `ErrImagePull` on 2026-04-03 immediately after Nexus came back up
- Nexus was down for 19 days due to the same CPU starvation cascade (T-102, T-103)
- Related: T-102 (Watchdog), T-103 (CPU Headroom)
