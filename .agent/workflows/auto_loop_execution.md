---
description: Auto-Loop Execution (Headless Autonomous Loop)
---

# Auto-Loop Execution Workflow

**Goal**: Execute a single priority task assigned by the `auto_loop.sh` orchestrator.
**Context**: You have been invoked headlessly to process one specific task from the backlog.

## Phase 1: Context Loading & PRD Gathering

1. Identify the task ID you have been assigned (e.g., `T-040`).
2. Read the corresponding task definition file (this will be located recursively under `tasks/`, for example `tasks/2026/Q1/{TASK_ID}-*.md`).
   - If the task requires a PRD (Product Requirements Document) to be broken down, break the task into small execution steps within the T-XXX file first.
   - Keep tasks _small_. If the task is too large for one context window, split the task file into sub-tasks (e.g., `T-040.1`, `T-040.2`) and update `KANBAN.md` accordingly. Focus only on the first small chunk.
3. Read `tasks/KANBAN.md` to see where this task sits.
4. Read `AGENTS.md` to remind yourself of the environment, cluster constraints, and your fundamental rules.
5. Review `AGENTS.md` or `.agent/progress.txt` for any learned context from the previous loop iteration.

## Phase 2: Action & Verification

1. Perform the necessary system or codebase changes.
2. Restrict your changes strictly to the scope of this single task/sub-task.
3. **Verify** your changes immediately without waiting for human feedback:
   - Run syntax tests (`bash -n`, `python -m py_compile`).
   - Run deployment dry-runs (`kubectl apply --dry-run=client -f <file>`).
   - Check infrastructure state (e.g., read logs, check service status if modifying systemd/k8s).
   - If UI changes, ask the browser tool to confirm visual elements if possible, or build the static assets.
4. If the verification fails, you must attempt to fix it within this same execution context.
5. You must leave the codebase/cluster in a **Green / Stable** state before exiting.

## Phase 3: State Management (Critical)

1. Once fully verified, update the task file marking it `✅ Done`.
2. Move the task in `tasks/KANBAN.md` to the `## ✅ Done` section.

## Phase 4: Knowledge Handoff

1. Because the next loop starts with a clean context, append your learnings (gotchas, newly established patterns, file locations) to `.agent/progress.txt` or `AGENTS.md`.
2. Say exactly what the _next_ agent needs to know.

**Exit Strategy**: Finish up quickly and exit with a code `0`. The bash loop script `auto_loop.sh` will then pick up the next task based on the updated `KANBAN.md`.
