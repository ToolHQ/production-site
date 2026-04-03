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

### What actually happened
postgres already uses `imagePullPolicy: IfNotPresent`. The ErrImagePull on `postgres-1` on
2026-04-03 was NOT caused by 19 days of Nexus downtime. The sequence was:

1. To break the volume attach deadlock, postgres was scaled to 0 replicas (both pods deleted)
2. Scaled back to 2 replicas — `postgres-1` was scheduled on `k8s-node-2`
3. The image `registry.local:31444/.../postgres:16-alpine-6d98ea7` was **not cached on node-2**
   (pod was freshly assigned there; `IfNotPresent` only helps if the image was previously pulled
   on that specific node)
4. Nexus had just come back up and was still initializing (Java startup ~2–3 min) → pull failed

The real gap: **images are only cached on nodes where they were previously run**. If a pod
migrates to a new node (after scale-down/up, node drain, rescheduling), it will pull again.

### Dependency Chain (corrected)
```
scale-down → scale-up → pod scheduled on node without cached image
→ Nexus still initializing → ErrImagePull (resolved within ~3 min)
```

### Affected workloads (need verification)
Images from `registry.local:31444` (Nexus Docker registry):
- `postgres` — confirmed, uses internal image with versioned tag ✓
- `back-end`, `py-back-end`, `rs-axum-back-end` — likely use internal registry (verify)
- Any image built locally and pushed to Nexus

### Non-affected
Pods using public images directly (`registry.k8s.io`, `docker.io`) — these pull directly
and don't depend on Nexus availability.

## 📋 Execution Plan

### Phase 1: Audit Image Pull Sources
- [ ] List all running pods and their image sources: `kubectl get pods -A -o jsonpath='{range .items[*]}{.spec.containers[*].image}{"\n"}{end}' | sort -u`
- [ ] Classify each image: public registry vs `registry.local` vs `nexus.dnor.io`
- [ ] Identify critical stateful workloads that use internal images (highest risk)

### Phase 2: `imagePullPolicy` Audit
postgres already uses `IfNotPresent` with versioned tags — correct. Audit remaining workloads.

- [ ] Audit all Deployments/StatefulSets for `imagePullPolicy` setting
- [ ] Confirm all internal-registry images use versioned (non-`latest`) tags — `latest` forces
  `Always` pull by default regardless of the explicit policy setting
- [ ] For any workload still using `imagePullPolicy: Always` with internal images: change to
  `IfNotPresent` and confirm it uses an immutable tag
- [ ] Document findings — expected outcome: no changes needed if all use versioned tags

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
