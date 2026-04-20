# T-133: Rust Observability API Thin Slice

**Status**: ✅ Done | **Priority**: 🔼 High | **Owner**: DevExp / Infra | **Est**: 4h

## 🎯 Objective

Implement the first online backend/frontend slice for the report stack inside the cluster, but in
Rust instead of the earlier Python recommendation, keeping the runtime footprint minimal and
reusing the existing report artifacts already generated on disk.

## Scope

- New service: `apps/rs-observability-api`
- Runtime: Rust + Axum
- Data source: bundled `reports/latest` and `reports/latest-catalog`
- Endpoints:
  - `/health`
  - `/api/catalog`
  - `/api/catalog/summary`
  - `/api/reports`
  - `/artifacts/*path`
- UI: static HTML served by the same binary on `/`
- Deploy path: OCI buildx + Nexus + Kubernetes Deployment/Service
- Exposure: dedicated ingress `reports.dnor.io`

## Why this shape

- No new database, queue, or heavy backend runtime
- No collector rewrite during the first slice
- Existing `catalog.json`, `catalog.html`, `inventory.html`, and markdown artifacts remain the
  source of truth
- Fits the cluster's `Stability First` constraints (`10m/16Mi` request, `50m/64Mi` limit)

## Delivered

- [x] Created `apps/rs-observability-api` with deterministic Docker build and OCI deploy script
- [x] Added lightweight Axum API and static UI
- [x] Bundled `reports/latest` and `reports/latest-catalog` into the image at deploy time
- [x] Added Kubernetes `Deployment` and `Service`
- [x] Deployed successfully to the cluster via `oci-builder` and Nexus
- [x] Added dedicated ingress `reports.dnor.io`

## Validation

- `cargo check` succeeded locally
- Local runtime checks succeeded for:
  - `GET /health`
  - `GET /api/catalog/summary`
  - `GET /api/reports`
  - `GET /`
- OCI deployment pushed image `registry.local:31444/repository/docker-repo/rs-observability-api:1776702081`
- Cluster rollout succeeded:
  - pod `rs-observability-api-deployment-b9c5c9848-dqslb` reached `Running`
  - logs showed `rs-observability-api listening on http://0.0.0.0:3000`
  - service endpoint resolved to the running pod
- Ingress validation succeeded through the ingress controller over HTTPS with `Host: reports.dnor.io`:
  - `GET /health` returned `{"status":"ok","service":"rs-observability-api"}`
  - `GET /api/catalog/summary` returned the catalog summary JSON
  - `GET /` returned the HTML UI shell

## Residual Note

- `reports.dnor.io` ingress and certificate are present and ready in-cluster, but external DNS for
  the new hostname was not yet resolving from the workstation during validation. The route itself is
  functional once the hostname points at the existing ingress edge.

## References

- `apps/rs-observability-api/`
- `tasks/2026/Q2/T-129-Observability-Report-Modularization-and-API-Readiness.md`
- `tasks/2026/Q2/T-110-Unified-Catalog-Inventory.md`
