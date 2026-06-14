#!/usr/bin/env bash

# Auto-Loop Orchestrator (Inspired by snarktank/ralph)
# Continuously picks tasks from KANBAN.md and passes them to an AI agent CLI.
# Enhanced: rich context injection, task file content, skill references, deploy instructions.

set -euo pipefail

# --- Configuration ---
# By default, we use 'claude' but it can be overridden, e.g., AI_CLI_COMMAND="aider --message"
AI_CLI_COMMAND="${AI_CLI_COMMAND:-claude}"
MAX_ITERATIONS="${MAX_ITERATIONS:-10}"

# Paths
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_DIR="${WORKSPACE_DIR:-$(cd "$DIR/../.." && pwd)}"
KANBAN_FILE="${WORKSPACE_DIR}/tasks/KANBAN.md"
AGENT_OWNER="${AGENT_OWNER:-}"
WORKFLOW_FILE="${WORKFLOW_FILE:-${WORKSPACE_DIR}/.agents/workflows/auto_loop_execution.md}"
if [[ "$AGENT_OWNER" == "Cursor" ]]; then
	WORKFLOW_FILE="${WORKSPACE_DIR}/.agents/workflows/cursor_loop.md"
elif [[ "$AGENT_OWNER" == "Copilot/VSCode" ]] || [[ "$AGENT_OWNER" == "Copilot" ]]; then
	WORKFLOW_FILE="${WORKSPACE_DIR}/.agents/workflows/copilot_loop.md"
elif [[ "$AGENT_OWNER" == "Codex" ]] || [[ "$AGENT_OWNER" == "Rust Rover" ]]; then
	WORKFLOW_FILE="${WORKSPACE_DIR}/.agents/workflows/codex_loop.md"
fi

# Extra context files to inject (optional, space-separated)
EXTRA_CONTEXT_FILES="${EXTRA_CONTEXT_FILES:-}"

# Deploy mode: if true, agent should deploy after code changes
DEPLOY_AFTER="${DEPLOY_AFTER:-false}"

# CLI arguments
DRY_RUN=false
if [[ "${1:-}" == "--dry-run" ]]; then
    DRY_RUN=true
    echo "⚠️ Running in DRY RUN mode. No AI will be invoked."
fi

# --- Helper Functions ---

get_next_task() {
	# Extracts the first pending task ID from KANBAN.md (In Progress or Backlog).
	# Optional AGENT_OWNER filters rows where the Owner column contains that string.
	awk -v owner_filter="${AGENT_OWNER}" '
        function owner_matches(line, filter) {
            if (filter == "") return 1
            if (filter == "Cursor") return (line ~ /\*\*Cursor \/ AI Radar\*\*/ || line ~ /\| Cursor \/ AI Radar \|/)
            if (filter == "Antigravity") return (line ~ /Antigravity/)
            if (filter ~ /^Copilot/) return (line ~ /Copilot\/VSCode/)
            if (filter == "Codex" || filter == "Rust Rover") return (line ~ /Codex/)
            return (line ~ filter)
        }
        /## 🏎️ In Progress/ { state="in_prog"; next }
        /## 📅 Backlog/ { state="backlog"; next }
        /## ✅ Done/ { exit }
        (state=="in_prog" || state=="backlog") && /\[T-[0-9]+/ {
            if (!owner_matches($0, owner_filter)) next
            match($0, /\[(T-[0-9]+(\.[0-9]+)?)\]/, arr);
            if(arr[1] != "") {
                print arr[1];
                exit;
            }
        }
    ' "$KANBAN_FILE"
}

# --- Main Loop ---

echo "🚀 Starting Auto-Loop Execution (Max Iterations: ${MAX_ITERATIONS})"
if [[ -n "$AGENT_OWNER" ]]; then
	echo "🔒 Owner filter: ${AGENT_OWNER}"
fi

for ((i=1; i<=MAX_ITERATIONS; i++)); do
    echo "------------------------------------------------"
    echo "🔄 Iteration $i / $MAX_ITERATIONS"
    
    NEXT_TASK=$(get_next_task)

    if [[ -z "$NEXT_TASK" ]]; then
        echo "✅ No pending tasks found in KANBAN.md. Auto-loop complete."
        exit 0
    fi
    
    echo "🎯 Picked Task: $NEXT_TASK"
    
    # Check if task file exists just to be safe
    # Using find to search recursively inside tasks/ just in case it sits anywhere
    TASK_FILE=$(find "${WORKSPACE_DIR}/tasks" -name "${NEXT_TASK}*.md" 2>/dev/null | head -n 1)
    
    if [[ -z "$TASK_FILE" ]]; then
        echo "⚠️ Warning: Could not find a markdown file for $NEXT_TASK in tasks/"
    fi

    # --- Build rich context prompt ---
    TASK_CONTENT=""
    if [[ -n "$TASK_FILE" ]]; then
        TASK_CONTENT=$(cat "$TASK_FILE")
    fi

    WORKFLOW_CONTENT=""
    if [[ -f "$WORKFLOW_FILE" ]]; then
        WORKFLOW_CONTENT=$(cat "$WORKFLOW_FILE")
    fi

    AGENTS_EXCERPT=""
    if [[ -f "${WORKSPACE_DIR}/AGENTS.md" ]]; then
        # Extract first 80 lines (core identity + rules)
        AGENTS_EXCERPT=$(head -80 "${WORKSPACE_DIR}/AGENTS.md")
    fi

    EXTRA_CONTENT=""
    if [[ -n "$EXTRA_CONTEXT_FILES" ]]; then
        for ctx_file in $EXTRA_CONTEXT_FILES; do
            if [[ -f "$ctx_file" ]]; then
                EXTRA_CONTENT+="
--- FILE: $(basename "$ctx_file") ---
$(cat "$ctx_file")
"
            fi
        done
    fi

    # Determine relevant skills for agent-meter tasks
    SKILLS_HINT=""
    if [[ "$TASK_FILE" == *"agent-meter"* ]]; then
        SKILLS_HINT="
## Relevant Skills (read before executing)
- Deploy: .agents/skills/deploy-service/SKILL.md (source setup-dev-deploy.sh → ./deploy.sh)
- Cluster: .agents/skills/connect-to-cluster/SKILL.md (ssh tunnel → kubectl)
- Live validation: .agents/skills/live-validation-harness/SKILL.md (mandatory for UI/API changes)
- Tasks: .agents/skills/manage-tasks/SKILL.md (update KANBAN + task file)

## Codebase Architecture (agent-meter)
- Workspace: apps/agent-meter/ (Rust workspace with 4 crates)
- Collector: crates/collector/ — Axum web server, 15 route modules, 10 service modules
- Proxy: crates/proxy/ — HTTPS MITM proxy for IDE→LLM traffic capture
- Router setup: crates/collector/src/app.rs (Router::new().merge(...) x14)
- Config: crates/collector/src/config.rs (env vars, Stripe, GitHub OAuth)
- Services: crates/collector/src/services/ (alert, auth, conversation, cost, event, org, report, stripe, task, token_estimator)
- Routes: crates/collector/src/routes/ (alerts, auth, billing, conversations, cost, dashboard, docs, events, health, orgs, otlp, reports, static_assets, tasks)
- UI: crates/collector/ui/ (static HTML files served via include_str!)
- Migrations: migrations/ (12 files, 20260517-20260607)
- Deploy: ./deploy.sh (build ARM64 → Nexus → kubectl apply)
- DB: PostgreSQL postgres-0 in namespace postgres, db=agent_meter, user=agent_meter
"
    fi

    DEPLOY_INSTRUCTIONS=""
    if [[ "$DEPLOY_AFTER" == "true" ]]; then
        DEPLOY_INSTRUCTIONS="
## Deploy Instructions (MANDATORY after code changes)
1. source oci-k8s-cluster/scripts/setup-dev-deploy.sh
2. export KUBECONFIG=~/production-site/oci-k8s-cluster/kubeconfig_tunnel.yaml
3. cd apps/agent-meter && ./deploy.sh
4. kubectl rollout status deploy/agent-meter -n default
5. Validate: curl https://agent-meter.dnor.io/health
"
    fi

    # Assemble the full prompt
    PROMPT="You are running in an autonomous loop. Execute task ${NEXT_TASK} completely.

## Task Definition
${TASK_CONTENT:-No task file found for $NEXT_TASK. Read KANBAN.md to understand the task.}

## Workflow Rules
${WORKFLOW_CONTENT:-Read $WORKFLOW_FILE for constraints.}
${SKILLS_HINT}${DEPLOY_INSTRUCTIONS}
## Agent Identity (from AGENTS.md)
${AGENTS_EXCERPT:-Read AGENTS.md for agent identity and rules.}
${EXTRA_CONTENT}
## Execution Protocol
1. Read the task file and understand ALL sub-tasks
2. Create a feature branch: git checkout -b feat/${NEXT_TASK}-description
3. Implement each sub-task, verifying as you go (cargo check, cargo clippy)
4. Commit with message: feat(${NEXT_TASK}): <description>
5. Push and create PR: gh pr create --title 'feat(${NEXT_TASK}): ...'
6. Update the task file: mark completed sub-tasks with [x]
7. Update tasks/KANBAN.md: move task to Done section
8. If deploy is required: run deploy.sh and validate

## Important Rules
- NEVER commit to main directly — always use feature branches + PR
- NEVER delete stateful workloads without confirmation
- Run cargo check after every significant change
- Respond in Portuguese (pt-BR) for any user-facing text
"
    
    echo "🤖 Attempting execution via: $AI_CLI_COMMAND"
    echo "📝 Task file: ${TASK_FILE:-none}"
    echo "📋 Workflow: $WORKFLOW_FILE"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "⏭️ [DRY RUN] Skipping actual execution. Assuming success."
        echo "✅ Dry-run selection validated. Stopping after one iteration."
        exit 0
    else
        # Actually invoke the CLI tool here
        # E.g., claude --prompt "$PROMPT"
        if ! $AI_CLI_COMMAND "$PROMPT"; then
            echo "❌ AI CLI exited with an error. Stopping the loop to prevent runaway failures."
            exit 1
        fi
        
        echo "✅ AI agent execution for iteration $i complete."
        
        # Wait a bit before next iteration to avoid rate limits or thrashing
        sleep 5
    fi
done

echo "⚠️ Reached maximum iterations ($MAX_ITERATIONS). Stopping loop."
