# T-132: Nexus Cleanup Policy Automation

- **Status**: Done
- **Priority**: 🔼 High
- **Owner**: Infra / DevOps
- **Est.**: 3h
- **Created**: 2026-04-19

---

## Context

T-124 closed the MinIO side of the backup retention problem and established that the bucket `nexus/`
is not backup backlog. It is the live Nexus S3 blob store (`minio`) used by:

- `docker-repo`
- `npm-repo`
- `npm-proxy`
- `npm-group`

Live Nexus audit executed on 2026-04-19 confirmed:

- all four repositories currently expose `cleanup: null`;
- built-in cleanup tasks already exist (`repository.cleanup`, `assetBlob.cleanup` for docker and npm);
- no compact-blob-store task was visible in the task inventory used during the audit;
- public REST in the live Swagger supports attaching `cleanup.policyNames` to repositories via `PUT`;
- public REST does not expose cleanup-policy creation or task creation endpoints in this version;
- the internal resource `/service/rest/internal/cleanup-policies` is live and usable for list/create/update/preview;
- the Script API browse endpoint is enabled, but script create/update is currently blocked by Nexus with `410`
  (`Creating and updating scripts is disable`).

This task exists to codify the safe automation boundary:

- enable repo-side audit and attachment of already-existing cleanup policies;
- keep hosted repos conservative until an explicit rollback/deprecation workflow exists;
- treat `npm-proxy` as the first valid cleanup-policy target because it is cache data, not primary source of truth.

---

## Tasks

- [x] Audit live Nexus cleanup status (`docker-repo`, `npm-repo`, `npm-proxy`, `npm-group`)
- [x] Confirm live API surface for cleanup attachment via Swagger
- [x] Confirm whether Script API is enabled on the current Nexus instance
- [x] Add repo-side helpers in `oci-k8s-cluster/lib/nexus_init.sh` to:
  - inspect cleanup attachment status;
  - inspect cleanup-related tasks;
  - attach existing cleanup policy names to supported repositories.
- [x] Document the recommended first safe scope in `docs/nexus-cleanup-policy.md`
- [x] Add a vetted Groovy script for cleanup-policy creation through Script API
- [x] Create the first live cleanup policy for `npm-proxy`
- [x] Attach the first live cleanup policy to `npm-proxy` and validate Nexus behavior
- [x] Decide whether a compact blob store task for blob store `minio` should be added after soft deletes start accumulating

---

## Execution notes

- Added internal cleanup-policy helpers and npm-proxy convenience wrappers to `oci-k8s-cluster/lib/nexus_init.sh`.
- Committed fallback Groovy policy-upsert script at `oci-k8s-cluster/scripts/registry/nexus_cleanup_policy_upsert.groovy`.
- Created live policy `npm-proxy-unused-30d` with `criteriaLastDownloaded = 30`.
- Attached `npm-proxy-unused-30d` to `npm-proxy`; live repo JSON now returns `cleanup.policyNames=["npm-proxy-unused-30d"]`.
- Live policy readback reports `inUseCount = 1`.
- Preview endpoint returned `200` and an empty sample (`{"total":-1,"results":[]}`) at validation time.
- Decision: do not add blob-store compaction yet; revisit only after a future cleanup run produces measurable
  soft-deleted blob residue.

---

## Current decision boundary

- `npm-proxy`: first and only repository with a cleanup policy attached (`npm-proxy-unused-30d`).
- `docker-repo`: keep `cleanup: null` until image promotion / rollback retention is defined.
- `npm-repo`: keep `cleanup: null` until internal package deprecation / rollback retention is defined.
- `npm-group`: keep `cleanup: null`; group remains an aggregation endpoint, not the first retention target.

---

## References

- `docs/backup-policy.md`
- `docs/nexus-cleanup-policy.md`
- `oci-k8s-cluster/lib/nexus_init.sh`
- `oci-k8s-cluster/scripts/registry/nexus_cleanup_policy_upsert.groovy`
- `tasks/2026/Q2/T-124-Backup-Retention-Audit-and-ETCD-Recovery.md`
