# T-053: Resource Optimization V3 (Tuning Requests)

**Status**: In Progress
**Priority**: High
**Assignee**: Antigravity

## Objective
Further optimize CPU requests to balance cluster load, specifically targeting Elastic Stack, Longhorn, and Coroot. Ensure all configurations are versioned in `components/`.

## Requirements
1. **Kubecost Cost-Analyzer**: Reduce to `90m`.
2. **Longhorn Instance Manager**: Reduce to `90m`.
3. **Elastic Kibana**: Reduce to `90m`.
4. **Coroot Clickhouse**: Reduce to `200m`.
5. **Elastic Operator**: Reduce to `50m` (Version `all-in-one.yaml` locally).
6. **Coroot Node Agent**: Verify/Enforce `90m`.
7. **Elasticsearch**: Set request to `100m`.
8. **Logstash**: Set request to `100m`.

## Implementation Plan
- [ ] **Task Setup**: Update Kanban.
- [ ] **Kubecost**: Update `components/kubecost/commands.sh`.
- [ ] **Longhorn**: Update `components/longhorn/longhorn.yaml` or Settings (search for `guaranteed-instance-manager-cpu`).
- [ ] **Coroot**: Update `components/coroot/commands.sh` (ClickHouse) and verify `values.yaml`.
- [ ] **Elastic Stack**:
    - [ ] Download/Version Elastic Operator manifest.
    - [ ] Update Operator resources.
    - [ ] Update `elasticsearch.yaml` (ES).
    - [ ] Update `logstash.yaml` (or relevant config).
    - [ ] Update `kibana.yaml` (or relevant config).
- [ ] **Deploy**: Apply all changes.

## Validation
- Check `kubectl describe nodes` and generate new ranking.
