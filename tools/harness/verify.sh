#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(
	CDPATH='' cd -- "$(dirname -- "$0")" && pwd
)
REPO_ROOT=$(
	CDPATH='' cd -- "$SCRIPT_DIR/../.." && pwd
)

# shellcheck source=tools/harness/lib/changed_paths.sh
source "$SCRIPT_DIR/lib/changed_paths.sh"

section() {
	printf '\n==> %s\n' "$1"
}

info() {
	printf '[info] %s\n' "$1"
}

pass() {
	printf '[pass] %s\n' "$1"
}

warn() {
	printf '[warn] %s\n' "$1"
}

fail() {
	printf '[fail] %s\n' "$1" >&2
}

usage() {
	cat <<'EOF'
Usage:
  ./tools/harness/verify.sh verify-changed [--allow-unmapped] [--paths <path> ...]
  ./tools/harness/verify.sh verify-all
  ./tools/harness/verify.sh smoke

Notes:
  - verify-changed uses unstaged, staged and untracked paths by default.
  - verify-changed fails on unmapped code paths unless --allow-unmapped is provided.
  - smoke is reserved for later rollout and intentionally not implemented in T-142.
EOF
}

run_checked() {
	local label=$1
	shift

	section "$label"
	info "$*"
	if "$@"; then
		pass "$label"
	else
		fail "$label"
		return 1
	fi
}

path_requires_shell_syntax() {
	case "$1" in
	tools/*.sh | tools/*.bash | apps/*/deploy.sh | oci-k8s-cluster/*.sh | oci-k8s-cluster/*.bash)
		return 0
		;;
	*)
		return 1
		;;
	esac
}

path_supports_shell_quality_gate() {
	local path="$1"

	if [[ "$path" == "tools/manage_tasks.sh" || "$path" == "tools/shfmt_compat.sh" || "$path" == "tools/helm_compat.sh" ]]; then
		return 0
	fi

	if [[ "$path" == oci-k8s-cluster/run_tests.sh || "$path" == oci-k8s-cluster/testing/setup_bats.sh ]]; then
		return 0
	fi

	if [[ "$path" == tools/harness/lib/*.sh ]]; then
		return 0
	fi

	if [[ "$path" == tools/harness/*.sh && "$path" != tools/harness/lib/* ]]; then
		return 0
	fi

	return 1
}

path_is_non_blocking_meta() {
	case "$1" in
	README.md | IMPLEMENTATION_SUMMARY.md | implementation_plan.md | docs/* | tasks/* | .github/*)
		return 0
		;;
	*)
		return 1
		;;
	esac
}

collect_verify_scope() {
	local path
	local -n shell_ref=$1
	local -n unmapped_ref=$2
	shift 2

	VERIFY_SCOPE_RUST_NEEDED=0
	VERIFY_SCOPE_BATS_NEEDED=0

	for path in "$@"; do
		if path_is_non_blocking_meta "$path"; then
			continue
		fi

		case "$path" in
		apps/rs-observability-api/*)
			VERIFY_SCOPE_RUST_NEEDED=1
			;;
		oci-k8s-cluster/testing/* | oci-k8s-cluster/run_tests.sh | oci-k8s-cluster/k8s_ops_menu.sh | oci-k8s-cluster/scripts/* | oci-k8s-cluster/lib/*)
			VERIFY_SCOPE_BATS_NEEDED=1
			;;
		*)
			if path_requires_shell_syntax "$path"; then
				shell_ref+=("$path")
			else
				unmapped_ref+=("$path")
			fi
			;;
		esac

		if path_requires_shell_syntax "$path"; then
			shell_ref+=("$path")
		fi
	done
}

collect_shell_quality_paths() {
	local path
	for path in "$@"; do
		if path_supports_shell_quality_gate "$path"; then
			printf '%s\n' "$path"
		fi
	done | awk 'NF && !seen[$0]++'
}

resolve_shellcheck_bin() {
	local shellcheck_bin
	shellcheck_bin="${SHELLCHECK_BIN:-shellcheck}"
	if ! command -v "$shellcheck_bin" >/dev/null 2>&1; then
		fail "shellcheck is required for managed shell quality gates but is not available"
		return 1
	fi

	command -v "$shellcheck_bin"
}

run_shell_syntax_checks() {
	local -a paths=("$@")
	local path
	local -a unique_paths=()

	if [[ ${#paths[@]} -eq 0 ]]; then
		warn "No shell scripts selected for syntax validation"
		return 0
	fi

	mapfile -t unique_paths < <(printf '%s\n' "${paths[@]}" | awk 'NF && !seen[$0]++')
	for path in "${unique_paths[@]}"; do
		run_checked "shell syntax: $path" bash -n "$REPO_ROOT/$path"
	done
}

run_shellcheck_checks() {
	local -a paths=("$@")
	local -a managed_paths=()
	local shellcheck_bin path

	mapfile -t managed_paths < <(collect_shell_quality_paths "${paths[@]}")
	if [[ ${#managed_paths[@]} -eq 0 ]]; then
		warn "No shell scripts selected for shellcheck"
		return 0
	fi

	shellcheck_bin="$(resolve_shellcheck_bin)"
	for path in "${managed_paths[@]}"; do
		run_checked "shellcheck: $path" "$shellcheck_bin" -x "$REPO_ROOT/$path"
	done
}

run_shfmt_checks() {
	local -a paths=("$@")
	local -a managed_paths=()
	local shfmt_bin path

	mapfile -t managed_paths < <(collect_shell_quality_paths "${paths[@]}")
	if [[ ${#managed_paths[@]} -eq 0 ]]; then
		warn "No shell scripts selected for shfmt"
		return 0
	fi

	shfmt_bin="$REPO_ROOT/tools/shfmt_compat.sh"
	for path in "${managed_paths[@]}"; do
		run_checked "shfmt: $path" "$shfmt_bin" -d "$REPO_ROOT/$path"
	done
}

run_rust_observability_gate() {
	local app_dir="$REPO_ROOT/apps/rs-observability-api"

	run_checked "rust fmt: rs-observability-api" bash -lc "cd '$app_dir' && cargo fmt --check"
	run_checked "rust clippy: rs-observability-api" bash -lc "cd '$app_dir' && cargo clippy --all-targets --all-features -- -D warnings"
	run_checked "rust test: rs-observability-api" bash -lc "cd '$app_dir' && cargo test"
}

run_cluster_bats_gate() {
	local cluster_dir="$REPO_ROOT/oci-k8s-cluster"
	run_checked "bats: oci-k8s-cluster" bash -lc "cd '$cluster_dir' && ./run_tests.sh"
}

verify_changed() {
	local allow_unmapped=0
	local -a passthrough=()
	local -a changed_paths=()
	local -a shell_paths=()
	local -a unmapped_paths=()
	local rust_needed bats_needed

	while [[ $# -gt 0 ]]; do
		case "$1" in
		--allow-unmapped)
			allow_unmapped=1
			shift
			;;
		*)
			passthrough+=("$1")
			shift
			;;
		esac
	done

	mapfile -t changed_paths < <(collect_changed_paths "${passthrough[@]}")

	if [[ ${#changed_paths[@]} -eq 0 ]]; then
		info "No changed paths detected; nothing to verify"
		return 0
	fi

	section "changed paths"
	printf '%s\n' "${changed_paths[@]}"

	collect_verify_scope shell_paths unmapped_paths "${changed_paths[@]}"
	rust_needed=$VERIFY_SCOPE_RUST_NEEDED
	bats_needed=$VERIFY_SCOPE_BATS_NEEDED

	if [[ ${#unmapped_paths[@]} -gt 0 ]]; then
		section "unmapped paths"
		printf '%s\n' "${unmapped_paths[@]}"
		if [[ $allow_unmapped -ne 1 ]]; then
			fail "Changed paths without a configured gate. Re-run with --allow-unmapped only if this gap is expected in the current rollout."
			return 2
		fi
		warn "Proceeding with unmapped paths because --allow-unmapped was provided"
	fi

	run_shell_syntax_checks "${shell_paths[@]}"
	run_shellcheck_checks "${shell_paths[@]}"
	run_shfmt_checks "${shell_paths[@]}"

	if [[ $rust_needed -eq 1 ]]; then
		run_rust_observability_gate
	else
		warn "Rust gate not selected"
	fi

	if [[ $bats_needed -eq 1 ]]; then
		run_cluster_bats_gate
	else
		warn "BATS gate not selected"
	fi
}

verify_all() {
	local -a shell_paths=()

	mapfile -t shell_paths < <(
		cd "$REPO_ROOT"
		find tools oci-k8s-cluster -type f \( -name '*.sh' -o -name '*.bash' \) -not -path '*/testing/libs/*' | sort
	)

	section "verify-all baseline"
	info "Running shell syntax, shellcheck, shfmt, rs-observability-api Rust gate and oci-k8s-cluster BATS gate"

	run_shell_syntax_checks "${shell_paths[@]}"
	run_shellcheck_checks "${shell_paths[@]}"
	run_shfmt_checks "${shell_paths[@]}"
	run_rust_observability_gate
	run_cluster_bats_gate
}

smoke() {
	fail "smoke is reserved but not implemented in T-142; deploy-aware probes land in subsequent tasks"
	return 2
}

main() {
	local command=${1:-}
	shift || true

	cd "$REPO_ROOT"

	case "$command" in
	verify-changed)
		verify_changed "$@"
		;;
	verify-all)
		verify_all "$@"
		;;
	smoke)
		smoke "$@"
		;;
	-h | --help | help | "")
		usage
		;;
	*)
		fail "Unknown command: $command"
		usage
		return 1
		;;
	esac
}

main "$@"
