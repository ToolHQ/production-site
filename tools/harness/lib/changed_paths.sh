#!/usr/bin/env bash

collect_changed_paths() {
	local include_untracked=1
	local -a explicit_paths=()
	local -a diff_paths=()
	local path

	while [[ $# -gt 0 ]]; do
		case "$1" in
		--paths)
			shift
			while [[ $# -gt 0 ]]; do
				explicit_paths+=("$1")
				shift
			done
			;;
		--no-untracked)
			include_untracked=0
			shift
			;;
		*)
			explicit_paths+=("$1")
			shift
			;;
		esac
	done

	if [[ ${#explicit_paths[@]} -gt 0 ]]; then
		printf '%s\n' "${explicit_paths[@]}" | awk 'NF && !seen[$0]++'
		return 0
	fi

	if ! git rev-parse --show-toplevel >/dev/null 2>&1; then
		return 1
	fi

	while IFS= read -r path; do
		[[ -n "$path" ]] && diff_paths+=("$path")
	done < <(git diff --name-only --diff-filter=ACMRTUXB)

	while IFS= read -r path; do
		[[ -n "$path" ]] && diff_paths+=("$path")
	done < <(git diff --name-only --cached --diff-filter=ACMRTUXB)

	if [[ $include_untracked -eq 1 ]]; then
		while IFS= read -r path; do
			[[ -n "$path" ]] && diff_paths+=("$path")
		done < <(git ls-files --others --exclude-standard)
	fi

	if [[ ${#diff_paths[@]} -eq 0 ]]; then
		return 0
	fi

	printf '%s\n' "${diff_paths[@]}" | awk 'NF && !seen[$0]++'
}
