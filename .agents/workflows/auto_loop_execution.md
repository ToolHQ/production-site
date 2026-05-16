---
description: Auto-Loop Execution (Headless Autonomous Loop)
---

# Auto-Loop Execution Workflow

**Goal**: Execute a single priority task autonomously while completely isolating execution from other agents (Cursor/Copilot).
**Context**: You have been invoked headlessly or manually by the user to process specific tasks assigned to `Antigravity`.

## Phase 1: Context Loading & Task Discovery

1. **Worktree Isolation**: You MUST operate exclusively within the designated git worktree (e.g., `../production-site-antigravity`) to prevent file conflicts with Cursor/Copilot. Do not modify files in the main `production-site` directory.
2. Read `tasks/KANBAN.md` to discover tasks. Look specifically for tasks in `## 🏎️ In Progress` or `## 📅 Backlog (To Do)` where the **Owner** column contains **`Antigravity`**. DO NOT pick up tasks owned by others.
3. Identify the highest priority task assigned to you (e.g., `T-040`).
4. Read the corresponding task definition file recursively under `tasks/` (e.g., `tasks/2026/Q1/{TASK_ID}-*.md`).
   - Break the task into small execution steps within the T-XXX file.
   - If the task is too large, split the task file into sub-tasks and update `KANBAN.md` accordingly, maintaining `Antigravity` as the Owner. Focus only on the first small chunk.
5. Read `AGENTS.md` to remind yourself of the environment, cluster constraints, and fundamental rules.

## Phase 2: Action & Verification

1. **GitFlow Strict**: Before making any code changes, create a new branch from `main` inside your worktree (e.g., `git checkout -b feat/{TASK_ID}-description`).
2. Perform the necessary system or codebase changes. Restrict changes strictly to the scope of this single task.
3. **Verify** your changes immediately without waiting for human feedback:
   - Run syntax tests (`bash -n`, `python -m py_compile`).
   - Run deployment dry-runs (`kubectl apply --dry-run=client -f <file>`).
   - Check infrastructure state (e.g., read logs, check service status if modifying systemd/k8s).
4. If verification fails, fix it within this same execution context. You must leave the codebase/cluster in a **Green / Stable** state.

## Phase 3: State Management & Delivery (Critical)

1. Once fully verified, commit your changes: `git add . && git commit -m "feat: complete {TASK_ID}"`.
2. Push your branch and **open a Pull Request** via the GitHub CLI: `gh pr create --title "feat: {TASK_ID}" --body "Automated delivery by Antigravity."`.
3. Update the task file marking it `✅ Done`.
4. Move the task in `tasks/KANBAN.md` to the `## ✅ Done` section (ensuring you keep `Antigravity` as the Owner for tracking).
5. Commit the KANBAN/Task status changes to your branch.

## Phase 4: Knowledge Handoff

1. Append your learnings (gotchas, newly established patterns, file locations) to `.agents/progress.txt` or `AGENTS.md`.
2. Say exactly what the _next_ loop iteration needs to know.

**Exit Strategy**: Finish up quickly and exit with a code `0`. Wait for the user or the auto_loop orchestrator to trigger the next execution.
