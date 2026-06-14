# Agent Meter — Operational Runbook

## Architecture

```
┌─────────────────┐     OTLP/HTTP (4318)     ┌─────────────────┐
│   IDE / SDK     │ ──────────────────────── → │  agent-meter    │
│   (client)      │     REST/JSON (3000)       │  (Rust/axum)    │
└─────────────────┘                            └────────┬────────┘
                                                        │
                                              ┌─────────▼─────────┐
                                              │   PostgreSQL 16   │
                                              │   (Longhorn PVC)  │
                                              └───────────────────┘
```

- **Ports**: 3000 (HTTP API + UI), 4318 (OTLP receiver)
- **Namespace**: `default`
- **Image**: `nexus.dnor.io/agent-meter:latest` (ARM64)
- **Resources**: 10m–100m CPU, 24–96Mi memory

## Health Checks

| Endpoint | Expected | Purpose |
|---|---|---|
| `GET /health` | 200 `{"status":"ok"}` | Liveness + Readiness |
| `GET /api/status` | 200 `{"collector":"up","db":"up"}` | Status page data |

## Common Issues

### Pod CrashLoopBackOff

1. Check logs: `kubectl logs deploy/agent-meter --tail=50`
2. Common causes:
   - **DATABASE_URL** wrong or Postgres unreachable → check Secret `agent-meter-db`
   - **OOM** → check if memory limit (96Mi) is enough, bump to 128Mi if needed
   - **Migration failure** → manual: `kubectl exec -it deploy/agent-meter -- /app/agent-meter migrate`

### High latency on /v1/traces

1. Check DB connection pool: `kubectl exec -it deploy/agent-meter -- curl localhost:3000/health`
2. Check Postgres CPU: `kubectl top pod -l app=postgres`
3. If Postgres is saturated: check for missing indexes, run `VACUUM ANALYZE agent_tool_calls`

### Disk pressure (Longhorn)

1. Check PVC usage: `kubectl exec -it deploy/postgres-0 -- df -h /var/lib/postgresql/data`
2. If > 80%: run the retention cleanup:
   ```sql
   DELETE FROM agent_tool_calls WHERE started_at < now() - interval '90 days';
   VACUUM FULL agent_tool_calls;
   ```

### OTLP not receiving spans

1. Verify port-forward or Ingress: `curl -X POST https://agent-meter.dnor.io/v1/traces -d '{}'`
2. Should return `[]` (empty array, no error)
3. Check firewall: OCI security lists must allow 4318/tcp on node ports

## Deployment

```bash
source oci-k8s-cluster/scripts/setup-dev-deploy.sh
cd apps/agent-meter && ./deploy.sh
kubectl rollout status deploy/agent-meter
```

## Backup

- **Database**: pg_dump via CronJob `agent-meter-backup` (daily, 7d retention)
- **PVC**: Longhorn automatic snapshots (configurable via StorageClass)

## Scaling

Current: 1 replica (sufficient for < 100K events/day).

To scale:
1. Increase replicas: `kubectl scale deploy/agent-meter --replicas=2`
2. PostgreSQL is the bottleneck — consider read replicas for dashboard queries
3. For > 1M events/day: implement write-ahead buffer (tokio mpsc → batch INSERT)

## Secrets

| Secret | Keys | Purpose |
|---|---|---|
| `agent-meter-db` | `url` | PostgreSQL connection string |
| `stripe-keys` | `secret-key`, `webhook-secret`, `price-pro`, `price-team` | Stripe billing |
| `agent-meter-github-oauth` | `client-id`, `client-secret` | GitHub OAuth login |

## Alerting

- Built-in: `/alerts` page with Slack/webhook/email channels
- External: Coroot monitors HTTP error rate + latency P95

## Contact

- **Maintainer**: Copilot/VSCode agent (automated operations)
- **Escalation**: @dnorio via GitHub Issues
