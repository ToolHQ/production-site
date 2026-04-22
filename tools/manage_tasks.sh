#!/usr/bin/env bash
set -euo pipefail

# tools/manage_tasks.sh
# Script to automate creation and movement of tasks in tasks/ and KANBAN.md

TASKS_DIR="tasks"
KANBAN_FILE="tasks/KANBAN.md"

function slugify_title() {
	echo "$1" | sed -E 's/[^A-Za-z0-9]+/-/g; s/^-+//; s/-+$//'
}

function current_task_dir() {
	local year month quarter
	year=$(date +%Y)
	month=$(date +%m)
	quarter=$((((10#$month - 1) / 3) + 1))

	printf "%s/%s/Q%s\n" "$TASKS_DIR" "$year" "$quarter"
}

function find_task_file() {
	local id=$1

	find "$TASKS_DIR" -type f -name "${id}-*.md" | sort | head -n 1
}

function section_status() {
	case "$1" in
	"## 🏎️ In Progress")
		echo "In Progress"
		;;
	"## ✅ Done")
		echo "Done"
		;;
	"## 📅 Backlog (To Do)")
		echo "Backlog"
		;;
	*)
		echo "Unknown"
		;;
	esac
}

function show_usage() {
	echo "Usage: $0 [add|start|done|list] [args...]"
	echo "  add \"Title\" \"Priority\" \"Epic/Owner\" \"Est.\" - Adds a new task"
	echo "  start ID - Moves task to In Progress"
	echo "  done ID - Moves task to Done"
	echo "  list - Lists current tasks"
}

function generate_id() {
	local last_id
	last_id=$(find "$TASKS_DIR" -type f -name 'T-*.md' | grep -o 'T-[0-9]\+' | cut -d'-' -f2 | sort -n | tail -1 || true)
	if [ -z "$last_id" ]; then
		echo "T-001"
	else
		printf "T-%03d\n" $((10#$last_id + 1))
	fi
}

function add_task() {
	local title=$1
	local priority=$2
	local epic=$3
	local est=$4
	local id slug task_dir relative_dir filename backlog_line insert_line
	id=$(generate_id)
	slug=$(slugify_title "$title")
	task_dir=$(current_task_dir)
	relative_dir=${task_dir#"${TASKS_DIR}"/}
	local filename="$task_dir/$id-$slug.md"

	mkdir -p "$task_dir"

	# Create task file
	cat <<EOF >"$filename"
# $id: $title

- **Status**: Backlog
- **Priority**: $priority
- **Epic/Owner**: $epic
- **Estimation**: $est

## Context
# TODO: Explique o contexto técnico, o problema e a solução proposta aqui.
# Use links para arquivos relevantes: [script.sh](path/to/script.sh)

## Tasks
# TODO: Quebre em tarefas menores e marque o progresso.
- [ ] Initial investigation
- [ ] Implement focus area 1
- [ ] Validate and test
EOF

	# Add to KANBAN.md (Backlog section starts at line 10-ish)
	# Finding the line for ## Backlog (To Do)
	backlog_line=$(grep -n "## 📅 Backlog (To Do)" "$KANBAN_FILE" | cut -d: -f1)
	insert_line=$((backlog_line + 4))

	# Check if table header exists there, if not find next
	sed -i "${insert_line}i\\| [$id]($relative_dir/$id-$slug.md) | **$title** | $priority | $epic | $est |" "$KANBAN_FILE"

	echo "Task $id created: $filename"
}

function move_task() {
	local id=$1
	local target_section=$2
	local task_line row_content target_line insert_line target_status task_file
	task_line=$(grep -n -m1 "\[$id\]" "$KANBAN_FILE" | cut -d: -f1)

	if [ -z "$task_line" ]; then
		echo "Task $id not found in KANBAN.md"
		return 1
	fi

	row_content=$(sed -n "${task_line}p" "$KANBAN_FILE")

	# Remove from current location
	sed -i "${task_line}d" "$KANBAN_FILE"

	# Add to target section
	target_line=$(grep -n -m1 "$target_section" "$KANBAN_FILE" | cut -d: -f1)
	insert_line=$((target_line + 4))
	target_status=$(section_status "$target_section")

	# Simple insertion
	sed -i "${insert_line}i\\$row_content" "$KANBAN_FILE"

	# Update task file status
	task_file=$(find_task_file "$id")
	if [ -n "$task_file" ] && [ -f "$task_file" ]; then
		sed -i "s/^- \*\*Status\*\*: .*/- \*\*Status\*\*: $target_status/" "$task_file"
	fi

	echo "Moved $id to $target_section"
}

case "${1:-}" in
add)
	[[ $# -eq 5 ]] || {
		show_usage
		exit 1
	}
	add_task "$2" "$3" "$4" "$5"
	;;
start)
	[[ $# -eq 2 ]] || {
		show_usage
		exit 1
	}
	move_task "$2" "## 🏎️ In Progress"
	;;
done)
	[[ $# -eq 2 ]] || {
		show_usage
		exit 1
	}
	move_task "$2" "## ✅ Done"
	;;
list)
	grep -E "\| \[T-" "$KANBAN_FILE"
	;;
*)
	show_usage
	exit 1
	;;
esac
