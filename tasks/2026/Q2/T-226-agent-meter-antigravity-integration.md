# T-226 — agent-meter: Antigravity integration

**Owner**: Antigravity
**Priority**: 🔼 High
**Estimate**: 1h
**Status**: ✅ Done

## Goal

Integrate Antigravity agent sessions with agent-meter: install CLI, send tool-call events, configure OTEL.

## Tasks

- [x] `apps/agent-meter/scripts/setup-agent.sh` criado — script universal que compila CLI, configura env vars, source no bashrc
- [x] `.agents/skills/agent-meter-integration/SKILL.md` criado — skill reutilizável por qualquer agente
- [x] Env vars: `setup-agent.sh --agent antigravity` define `AGENT_METER_IDE=antigravity`, `AGENT_METER_COLLECTOR_URL=http://agent-meter:3000`
- [x] CLI e wrapper documentados na skill com exemplos de uso
- [x] OTEL documentado em `docs/agent-meter-otel.md` (T-225)

## Como usar

```bash
cd ~/production-site-opencode   # qualquer worktree
apps/agent-meter/scripts/setup-agent.sh --agent antigravity
```

## Dependencies

- T-225 (OTEL docs) — Done
