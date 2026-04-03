# T-105: Internal Registry (Nexus) Resilience

**Status**: [ ] Backlog | **Priority**: 🔽 Medium | **Owner**: Infra | **Est**: 2h

## 🎯 Objective
Any workload using images from the internal Nexus registry (`registry.local:31444`) depends
on Nexus being reachable at the moment a pod is scheduled on a node that doesn't have the
image cached. This happened on 2026-04-03: after a scale-down/up cycle, `postgres-1` was
scheduled on a node without the cached image, and Nexus was still initializing → ErrImagePull.

Ensure that critical stateful workloads can restart on any node regardless of Nexus availability,
by guaranteeing images are pre-cached across all worker nodes.

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
Ensure images are cached on all nodes so rescheduling never triggers a pull.

- [ ] Identify all internal-registry image tags for critical stateful workloads (postgres, etc.)
- [ ] **Preferred approach**: add a `pre-pull-images` option to `k8s_ops_menu.sh` under
  "Maintenance" — runs `kubectl create job` per node using `nodeSelector` to force pulls.
  Run this after any Nexus restart or before a planned maintenance window.
- [ ] **Avoid**: a permanent pre-pull DaemonSet — it adds a pod per node, consuming CPU
  on an already saturated cluster, for a benefit that only matters occasionally.
- [ ] Verify: scale postgres to 0 then back to 2 with Nexus at 0 replicas. `postgres-1`
  must start successfully using cached image. ⚠️ Run this test only when `postgres-0` is
  confirmed Running and healthy first (replica handles traffic during the test).

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
