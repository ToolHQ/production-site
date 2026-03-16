#!/usr/bin/env bash

# Auto-Loop Orchestrator (Inspired by snarktank/ralph)
# Continuously picks tasks from KANBAN.md and passes them to an AI agent CLI.

set -euo pipefail

# --- Configuration ---
# By default, we use 'claude' but it can be overridden, e.g., AI_CLI_COMMAND="aider --message"
AI_CLI_COMMAND="${AI_CLI_COMMAND:-claude}"
MAX_ITERATIONS="${MAX_ITERATIONS:-10}"

# Paths
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_DIR="$(cd "$DIR/../.." && pwd)"
KANBAN_FILE="${WORKSPACE_DIR}/tasks/KANBAN.md"
WORKFLOW_FILE="${WORKSPACE_DIR}/.agent/workflows/auto_loop_execution.md"

# CLI arguments
DRY_RUN=false
if [[ "${1:-}" == "--dry-run" ]]; then
    DRY_RUN=true
    echo "⚠️ Running in DRY RUN mode. No AI will be invoked."
fi

# --- Helper Functions ---

get_next_task() {
    # Extracts the first pending task ID from KANBAN.md (In Progress or Backlog)
    # Using awk to parse markdown table formats safely
    awk '
        /## 🏎️ In Progress/ { state="in_prog"; next }
        /## 📅 Backlog/ { state="backlog"; next }
        /## ✅ Done/ { exit }
        (state=="in_prog" || state=="backlog") && /\[T-[0-9]+/ {
            # Extract task ID formatted as [T-123] or [T-123.4]
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
    
    # Prepare the prompt for the AI
    PROMPT="You are running in an autonomous loop. Please execute task $NEXT_TASK. Read the workflow instructions at $WORKFLOW_FILE to understand your constraints and output format."
    
    echo "🤖 Attempting execution via: $AI_CLI_COMMAND"
    echo "💬 Prompt: $PROMPT"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "⏭️ [DRY RUN] Skipping actual execution. Assuming success."
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
