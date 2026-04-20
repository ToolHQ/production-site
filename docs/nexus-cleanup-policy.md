# Nexus Cleanup Policy Automation

Date: 2026-04-19

## Why this exists

The MinIO bucket `nexus/` is live Nexus blob-store storage, not backup backlog. That means retention must be handled from Nexus itself.

Live audit on 2026-04-19 established:

- `docker-repo`, `npm-repo`, `npm-proxy`, and `npm-group` all currently have `cleanup: null`.
- The internal Nexus cleanup-policy resource `/service/rest/internal/cleanup-policies` responds `200` and supports list/create/update/preview on the current instance.
- The built-in Nexus tasks `repository.cleanup` and `assetBlob.cleanup` already exist.
- No compact blob store task was observed in the task inventory used during the audit.
- The live public REST API supports attaching existing cleanup policies to repositories through `cleanup.policyNames` on repository `PUT` payloads.
- The live public REST API does not expose cleanup-policy creation or task creation endpoints in Swagger.
- The live Script API browse endpoint responds, but script create/update currently returns `410` (`Creating and updating scripts is disable`).

## Safe policy boundary

Current safe stance:

1. `npm-proxy` is the first valid target for cleanup policies because it is cache data backed by the public npm registry.
2. `docker-repo` stays conservative for now; internal container images are rollback material.
3. `npm-repo` stays conservative for now; internal package versions are rollback material.
4. `npm-group` stays conservative; it is an aggregation endpoint, not the place to start retention.
5. No MinIO-side lifecycle, `mc rm`, or raw bucket deletion should be used for Nexus cleanup.

## Repo-side automation available now

The following helpers were added to `oci-k8s-cluster/lib/nexus_init.sh`:

- `nexus_show_cleanup_status`
- `nexus_list_cleanup_policies`
- `nexus_get_cleanup_policy`
- `nexus_get_cleanup_criteria_formats`
- `nexus_apply_cleanup_policy_json`
- `nexus_preview_cleanup_policy_json`
- `nexus_build_npm_proxy_cleanup_policy_json`
- `nexus_ensure_npm_proxy_cleanup_policy`
- `nexus_build_npm_proxy_cleanup_preview_json`
- `nexus_preview_npm_proxy_cleanup`
- `nexus_get_repository_json`
- `nexus_set_repository_cleanup_policies`
- `nexus_clear_repository_cleanup_policies`
- `nexus_set_npm_proxy_cleanup_policies`
- `nexus_set_npm_hosted_cleanup_policies`
- `nexus_set_docker_hosted_cleanup_policies`

The repo also now contains a versioned Groovy fallback at `oci-k8s-cluster/scripts/registry/nexus_cleanup_policy_upsert.groovy`.

These helpers can now audit cleanup attachment, create/update policies through the live internal REST surface,
preview matches, and attach policy names to supported repositories.

## Example usage

With a Nexus tunnel or port-forward active:

```bash
source oci-k8s-cluster/lib/nexus_init.sh
export NEXUS_API_BASE=http://localhost:8081

# Audit current repository cleanup attachment and cleanup-related tasks
nexus_show_cleanup_status

# Create or update the recommended npm-proxy cleanup policy
nexus_ensure_npm_proxy_cleanup_policy npm-proxy-unused-30d 30

# Preview the live impact before or after attachment
nexus_preview_npm_proxy_cleanup npm-proxy npm-proxy-unused-30d 30 | jq '.results'

# Attach the cleanup policy to npm-proxy
nexus_set_npm_proxy_cleanup_policies npm-proxy npm-proxy-unused-30d

# Clear cleanup attachment again if needed
nexus_clear_repository_cleanup_policies npm proxy npm-proxy
```

## First live policy

The first live policy now present in Nexus is:

- `npm-proxy-unused-30d`

Validated live state after applying it:

- format: `npm`
- criterion: `criteriaLastDownloaded = 30`
- attached repository: `npm-proxy`
- live `inUseCount`: `1`
- `nexus_show_cleanup_status` reports the policy attached to `npm-proxy`
- cleanup preview returned `200` with an empty sample (`{"total":-1,"results":[]}`) at validation time

This keeps the first retention boundary limited to cache data rather than rollback material.

## Script API note

The Groovy script fallback is committed, but it is not currently runnable through the live Script API because the
instance rejects script creation and updates with `410`.

Treat `oci-k8s-cluster/scripts/registry/nexus_cleanup_policy_upsert.groovy` as a staged fallback for a future moment
when `nexus.scripts.allowCreation` is deliberately enabled.

## Compact task decision

Do not add a blob-store compact task for `minio` yet.

Reason:

- the first cleanup policy has only just been attached;
- no cleanup run has yet produced an observed backlog of soft-deleted blobs;
- adding compact work before that point increases operational surface without a measured payoff.

Revisit compaction only after a future `repository.cleanup` pass and subsequent `assetBlob.cleanup` runs show actual
reclaimable blob residue.

## References

- `docs/backup-policy.md`
- `oci-k8s-cluster/lib/nexus_init.sh`
- `oci-k8s-cluster/scripts/registry/nexus_cleanup_policy_upsert.groovy`
- `tasks/2026/Q2/T-132-Nexus-Cleanup-Policy-Automation.md`
