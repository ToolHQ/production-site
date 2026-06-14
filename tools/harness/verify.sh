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

# Execution summary state — populated by timed_gate(), printed via print_summary()
HARNESS_RESULTS=()
HARNESS_START=0

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
  ./tools/harness/verify.sh verify-changed [--allow-unmapped] [--paths <path> ...] [--no-untracked]
  ./tools/harness/verify.sh verify-all
  ./tools/harness/verify.sh smoke

Notes:
  - verify-changed uses unstaged, staged and untracked paths by default.
  - Pass --no-untracked for git-diff-only semantics (omit untracked files).
  - verify-changed fails on unmapped code paths unless --allow-unmapped is provided.
  - smoke is reserved for later rollout and intentionally not implemented in T-142.
  - One-line skip summary is printed unless HARNESS_VERBOSE=1 is set (per-gate skip messages).

Environment:
  HARNESS_VERBOSE=1 — print each suppressed “gate skipped” diagnostic.
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

timed_gate() {
	local label=$1
	shift
	local t0=$SECONDS rc=0
	"$@" || rc=$?
	local elapsed=$((SECONDS - t0))
	if [[ $rc -eq 0 ]]; then
		HARNESS_RESULTS+=("$label|PASS|${elapsed}s")
	else
		HARNESS_RESULTS+=("$label|FAIL|${elapsed}s")
	fi
	return $rc
}

print_summary() {
	local elapsed=$((SECONDS - HARNESS_START))
	local pass_count=0 fail_count=0 skip_count=0 overall="SKIP"

	if [[ ${#HARNESS_RESULTS[@]} -eq 0 ]]; then
		printf '\n── HARNESS SUMMARY ── 0 gates ran in %ds ──\n' "$elapsed"
		return 0
	fi

	printf '\n'
	printf '%.0s─' {1..54}
	printf '\n'
	printf ' %-32s %-6s %s\n' "Gate" "Result" "Time"
	printf ' %-32s %-6s %s\n' "────────────────────────────────" "──────" "──────"
	for entry in "${HARNESS_RESULTS[@]}"; do
		IFS='|' read -r label status dur <<<"$entry"
		printf ' %-32s %-6s %s\n' "$label" "$status" "$dur"
		case "$status" in
		PASS) pass_count=$((pass_count + 1)) ;;
		FAIL)
			fail_count=$((fail_count + 1))
			overall="FAIL"
			;;
		SKIP) skip_count=$((skip_count + 1)) ;;
		esac
	done
	printf ' %-32s %-6s %s\n' "────────────────────────────────" "──────" "──────"
	if [[ $fail_count -gt 0 ]]; then
		overall="FAIL"
	elif [[ $pass_count -gt 0 ]]; then
		overall="PASS"
	else
		overall="SKIP"
	fi
	printf ' %-20s %ds   pass=%d fail=%d skip=%d\n' \
		"$overall" "$elapsed" "$pass_count" "$fail_count" "$skip_count"
	printf '%.0s─' {1..54}
	printf '\n'
}

path_requires_shell_syntax() {
	case "$1" in
	*.sh | *.bash)
		case "$1" in
		tools/* | apps/*/deploy.sh | oci-k8s-cluster/* | components/ssdnodes/jenkins/* | scripts/harness/*)
			return 0
			;;
		esac
		;;
	esac
	return 1
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

	if [[ "$path" == components/ssdnodes/jenkins/*.sh || "$path" == components/ssdnodes/jenkins/scripts/*.sh ]]; then
		return 0
	fi

	if [[ "$path" == tools/citools/scripts/*.sh ]]; then
		return 0
	fi

	return 1
}

path_is_non_blocking_meta() {
	case "$1" in
	.gitignore | CHANGELOG.md | sonar-project.properties | \
		README.md | IMPLEMENTATION_SUMMARY.md | implementation_plan.md | \
		docs/* | tasks/* | .github/* | \
		components/ssdnodes/ADR-*.md | components/ssdnodes/README.md | \
		components/ssdnodes/n8n/*.md | components/ssdnodes/n8n/schema/*.sql | \
		components/ssdnodes/jenkins/Jenkinsfile.generic | \
		components/ssdnodes/jenkins/Jenkinsfile.deploy | \
		components/ssdnodes/jenkins/bootstrap-ci-job.groovy | \
		components/ssdnodes/jenkins/bootstrap-deploy-job.groovy | \
		components/ssdnodes/jenkins/pipeline-deploy.yaml | \
		components/ssdnodes/jenkins/README.md | \
		components/ssdnodes/github-webhook-ip-ranges.txt | \
		components/ssdnodes/jenkins-github-webhook-ingress.yaml | \
		tools/citools/README.md | tools/citools/Cargo.lock | \
		oci-k8s-cluster/systemd/* | \
		components/_archived/* | components/_planned/*)
		return 0
		;;
	*)
		return 1
		;;
	esac
}

path_is_yaml_manifest() {
	local p="$1"
	# Match .yaml/.yml under components/ or apps/ (not node_modules or cargo target)
	case "$p" in
	*node_modules* | */target/*) return 1 ;;
	components/*.yaml | components/*.yml) return 0 ;;
	apps/*.yaml | apps/*.yml) return 0 ;;
	esac
	# Subdirectory match via prefix + suffix test
	if [[ "$p" == components/* && ("$p" == *.yaml || "$p" == *.yml) ]]; then
		return 0
	fi
	if [[ "$p" == apps/* && ("$p" == *.yaml || "$p" == *.yml) ]]; then
		return 0
	fi
	return 1
}

collect_verify_scope() {
	local path
	local -n shell_ref=$1
	local -n unmapped_ref=$2
	shift 2

	VERIFY_SCOPE_RUST_NEEDED=0
	VERIFY_SCOPE_RUST_AI_RADAR_NEEDED=0
	VERIFY_SCOPE_RUST_AGENT_METER_NEEDED=0
	VERIFY_SCOPE_BATS_NEEDED=0
	VERIFY_SCOPE_JS_BACKEND_NEEDED=0
	VERIFY_SCOPE_JS_REACT_NEEDED=0
	VERIFY_SCOPE_JS_STATIC_NEEDED=0
	VERIFY_SCOPE_YAML_NEEDED=0
	VERIFY_SCOPE_CITOOLS_NEEDED=0

	for path in "$@"; do
		if path_is_non_blocking_meta "$path"; then
			continue
		fi

		if [[ "$path" == apps/rs-observability-api/* ]]; then
			VERIFY_SCOPE_RUST_NEEDED=1
		elif [[ "$path" == apps/ai-radar/* ]]; then
			VERIFY_SCOPE_RUST_AI_RADAR_NEEDED=1
		elif [[ "$path" == apps/agent-meter/* ]]; then
			VERIFY_SCOPE_RUST_AGENT_METER_NEEDED=1
		elif [[ "$path" == tools/citools/* ]]; then
			VERIFY_SCOPE_CITOOLS_NEEDED=1
		elif [[ "$path" == oci-k8s-cluster/testing/* || "$path" == oci-k8s-cluster/run_tests.sh || "$path" == oci-k8s-cluster/k8s_ops_menu.sh || "$path" == oci-k8s-cluster/scripts/* || "$path" == oci-k8s-cluster/lib/* ]]; then
			VERIFY_SCOPE_BATS_NEEDED=1
		elif [[ "$path" == apps/back-end/* ]]; then
			VERIFY_SCOPE_JS_BACKEND_NEEDED=1
		elif [[ "$path" == apps/react-static/* ]]; then
			VERIFY_SCOPE_JS_REACT_NEEDED=1
		elif [[ "$path" == apps/static/* ]]; then
			VERIFY_SCOPE_JS_STATIC_NEEDED=1
		elif path_is_yaml_manifest "$path"; then
			VERIFY_SCOPE_YAML_NEEDED=1
		else
			if ! path_requires_shell_syntax "$path"; then
				unmapped_ref+=("$path")
			fi
		fi

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

run_js_back_end_gate() {
	local app_dir="$REPO_ROOT/apps/back-end"
	run_checked "js typecheck: back-end" bash -lc "cd '$app_dir' && npm run typecheck"
	run_checked "js lint: back-end" bash -lc "cd '$app_dir' && npm run lint"
}

run_js_react_static_gate() {
	local app_dir="$REPO_ROOT/apps/react-static"
	run_checked "js typecheck: react-static" bash -lc "cd '$app_dir' && npm run typecheck"
	run_checked "js test:ci: react-static" bash -lc "cd '$app_dir' && npm run test:ci"
}

run_js_static_gate() {
	local app_dir="$REPO_ROOT/apps/static"
	run_checked "js typecheck: static" bash -lc "cd '$app_dir' && npm run typecheck"
}

run_yamllint_gate() {
	run_yamllint_paths "$@"
}

run_yamllint_paths() {
	local yamllint_bin path abs
	yamllint_bin="${YAMLLINT_BIN:-yamllint}"
	if ! command -v "$yamllint_bin" >/dev/null 2>&1; then
		yamllint_bin="$HOME/.local/bin/yamllint"
	fi
	if ! command -v "$yamllint_bin" >/dev/null 2>&1; then
		fail "yamllint is required for YAML gate (install: apt install yamllint)"
		return 1
	fi

	local -a yaml_files=()
	for path in "$@"; do
		if path_is_yaml_manifest "$path"; then
			abs="$REPO_ROOT/$path"
			[[ -f "$abs" ]] && yaml_files+=("$abs")
		fi
	done

	if [[ ${#yaml_files[@]} -eq 0 ]]; then
		warn "No YAML manifests in changed scope"
		return 0
	fi

	run_checked "yamllint: changed paths (${#yaml_files[@]} file(s))" \
		"$yamllint_bin" -c "$REPO_ROOT/.yamllint.yaml" \
		"${yaml_files[@]}"
}

run_yamllint_all_manifests() {
	local yamllint_bin
	yamllint_bin="${YAMLLINT_BIN:-yamllint}"
	if ! command -v "$yamllint_bin" >/dev/null 2>&1; then
		yamllint_bin="$HOME/.local/bin/yamllint"
	fi
	if ! command -v "$yamllint_bin" >/dev/null 2>&1; then
		fail "yamllint is required for YAML gate (install: apt install yamllint)"
		return 1
	fi

	local -a yaml_files
	mapfile -t yaml_files < <(
		find "$REPO_ROOT/components" "$REPO_ROOT/apps" \
			-name '*.yaml' -o -name '*.yml' |
			grep -v 'node_modules\|/target/' |
			sort
	)
	run_checked "yamllint: components + apps manifests" \
		"$yamllint_bin" -c "$REPO_ROOT/.yamllint.yaml" \
		"${yaml_files[@]}"
}

run_citools_gate() {
	local dir="$REPO_ROOT/tools/citools" rc=0
	# bash -c (não -lc): login shell no agent Jenkins zera PATH e perde cargo
	run_checked "rust fmt: citools" bash -c "cd '$dir' && cargo fmt --check" || rc=1
	run_checked "rust clippy: citools" bash -c "cd '$dir' && cargo clippy --all-targets -- -D warnings" || rc=1
	run_checked "rust test: citools" bash -c "cd '$dir' && cargo test" || rc=1
	return "$rc"
}

run_rust_observability_gate() {
	local app_dir="$REPO_ROOT/apps/rs-observability-api"

	# bash -c (not -lc): login shell on Jenkins rust agent drops /usr/local/cargo/bin
	run_checked "rust fmt: rs-observability-api" bash -c "cd '$app_dir' && cargo fmt --check"
	run_checked "rust clippy: rs-observability-api" bash -c "cd '$app_dir' && cargo clippy --all-targets --all-features -- -D warnings"
	run_checked "rust test: rs-observability-api" bash -c "cd '$app_dir' && cargo test"
}

run_rust_ai_radar_gate() {
	local app_dir="$REPO_ROOT/apps/ai-radar"

	# bash -c (not -lc): login shell on Jenkins rust agent drops /usr/local/cargo/bin
	run_checked "rust fmt: ai-radar" bash -c "cd '$app_dir' && cargo fmt --check"
	run_checked "rust clippy: ai-radar" bash -c "cd '$app_dir' && cargo clippy --workspace --all-targets -- -D warnings"
	run_checked "rust test: ai-radar" bash -c "cd '$app_dir' && cargo test --workspace"
}

run_rust_agent_meter_gate() {
	local app_dir="$REPO_ROOT/apps/agent-meter"

	# Compile-only gate (workspace + all targets). The agent-meter workspace
	# still carries pre-existing fmt/clippy debt across crates, and its tests
	# require a live PostgreSQL the CI agent does not provide — so a strict
	# fmt/clippy/test gate would fail on unrelated code. `cargo check
	# --all-targets` still compiles every crate and every test target
	# (catching broken code and broken tests) without needing a database.
	# Tighten to fmt/clippy/test once the workspace lint debt is cleared.
	#
	# bash -c (not -lc): a login shell on the Jenkins agent resets PATH and
	# loses cargo (same gotcha as the citools gate); verify-branch-ci.sh has
	# already exported the cargo PATH into our environment.
	run_checked "rust check: agent-meter" bash -c "cd '$app_dir' && cargo check --workspace --all-targets"
}

run_rust_agent_meter_gate() {
	local app_dir="$REPO_ROOT/apps/agent-meter"

	# Compile-only gate (workspace + all targets). The agent-meter workspace
	# still carries pre-existing fmt/clippy debt across crates, and its tests
	# require a live PostgreSQL the CI agent does not provide — so a strict
	# fmt/clippy/test gate would fail on unrelated code. `cargo check
	# --all-targets` still compiles every crate and every test target
	# (catching broken code and broken tests) without needing a database.
	# Tighten to fmt/clippy/test once the workspace lint debt is cleared.
	#
	# bash -c (not -lc): a login shell on the Jenkins agent resets PATH and
	# loses cargo (same gotcha as the citools gate); verify-branch-ci.sh has
	# already exported the cargo PATH into our environment.
	run_checked "rust check: agent-meter" bash -c "cd '$app_dir' && cargo check --workspace --all-targets"
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
	local rust_needed rust_ai_radar_needed rust_agent_meter_needed bats_needed js_backend_needed js_react_needed js_static_needed yaml_needed citools_needed

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
	rust_ai_radar_needed=$VERIFY_SCOPE_RUST_AI_RADAR_NEEDED
	rust_agent_meter_needed=$VERIFY_SCOPE_RUST_AGENT_METER_NEEDED
	bats_needed=$VERIFY_SCOPE_BATS_NEEDED
	js_backend_needed=$VERIFY_SCOPE_JS_BACKEND_NEEDED
	js_react_needed=$VERIFY_SCOPE_JS_REACT_NEEDED
	js_static_needed=$VERIFY_SCOPE_JS_STATIC_NEEDED
	yaml_needed=$VERIFY_SCOPE_YAML_NEEDED
	citools_needed=$VERIFY_SCOPE_CITOOLS_NEEDED

	local path only_blocking_paths=0
	for path in "${changed_paths[@]}"; do
		path_is_non_blocking_meta "$path" || only_blocking_paths=1
	done

	local -a skipped_stack_gates=()
	[[ $rust_needed -eq 0 ]] && skipped_stack_gates+=("rust")
	[[ $rust_ai_radar_needed -eq 0 ]] && skipped_stack_gates+=("rust-ai-radar")
	[[ $rust_agent_meter_needed -eq 0 ]] && skipped_stack_gates+=("rust-agent-meter")
	[[ $bats_needed -eq 0 ]] && skipped_stack_gates+=("bats")
	[[ $js_backend_needed -eq 0 ]] && skipped_stack_gates+=("js-back-end")
	[[ $js_react_needed -eq 0 ]] && skipped_stack_gates+=("js-react-static")
	[[ $js_static_needed -eq 0 ]] && skipped_stack_gates+=("js-static")
	[[ $yaml_needed -eq 0 ]] && skipped_stack_gates+=("yaml")
	[[ $citools_needed -eq 0 ]] && skipped_stack_gates+=("citools")
	if [[ $only_blocking_paths -eq 1 && ${#skipped_stack_gates[@]} -gt 0 ]]; then
		info "Stack gates skipped (paths did not touch those trees): ${skipped_stack_gates[*]}"
	fi

	if [[ ${#unmapped_paths[@]} -gt 0 ]]; then
		section "unmapped paths"
		printf '%s\n' "${unmapped_paths[@]}"
		if [[ $allow_unmapped -ne 1 ]]; then
			fail "Changed paths without a configured gate. Re-run with --allow-unmapped only if this gap is expected in the current rollout."
			return 2
		fi
		warn "Proceeding with unmapped paths because --allow-unmapped was provided"
	fi

	if [[ ${#shell_paths[@]} -eq 0 ]]; then
		HARNESS_RESULTS+=(
			"shell-syntax|SKIP|-"
			"shell-shellcheck|SKIP|-"
			"shell-shfmt|SKIP|-"
		)
		if [[ $only_blocking_paths -eq 1 ]]; then
			info "No shell files in changed scope; skipping shell-syntax / shellcheck / shfmt"
		fi
	else
		timed_gate "shell-syntax" run_shell_syntax_checks "${shell_paths[@]}"
		timed_gate "shell-shellcheck" run_shellcheck_checks "${shell_paths[@]}"
		timed_gate "shell-shfmt" run_shfmt_checks "${shell_paths[@]}"
	fi

	if [[ $rust_needed -eq 1 ]]; then
		timed_gate "rust" run_rust_observability_gate
	else
		HARNESS_RESULTS+=("rust|SKIP|-")
		if [[ ${HARNESS_VERBOSE:-0} -eq 1 ]]; then
			warn "Rust gate not selected"
		fi
	fi

	if [[ $rust_ai_radar_needed -eq 1 ]]; then
		timed_gate "rust-ai-radar" run_rust_ai_radar_gate
	else
		HARNESS_RESULTS+=("rust-ai-radar|SKIP|-")
		if [[ ${HARNESS_VERBOSE:-0} -eq 1 ]]; then
			warn "Rust ai-radar gate not selected"
		fi
	fi

	if [[ $rust_agent_meter_needed -eq 1 ]]; then
		timed_gate "rust-agent-meter" run_rust_agent_meter_gate
	else
		HARNESS_RESULTS+=("rust-agent-meter|SKIP|-")
		if [[ ${HARNESS_VERBOSE:-0} -eq 1 ]]; then
			warn "Rust agent-meter gate not selected"
		fi
	fi

	if [[ $bats_needed -eq 1 ]]; then
		if [[ "${HARNESS_SKIP_BATS:-0}" == "1" ]]; then
			HARNESS_RESULTS+=("bats|SKIP|-")
			info "BATS gate skipped (HARNESS_SKIP_BATS=1 — CI sem acesso ao cluster)"
		else
			timed_gate "bats" run_cluster_bats_gate
		fi
	else
		HARNESS_RESULTS+=("bats|SKIP|-")
		if [[ ${HARNESS_VERBOSE:-0} -eq 1 ]]; then
			warn "BATS gate not selected"
		fi
	fi

	if [[ $js_backend_needed -eq 1 ]]; then
		if [[ "${HARNESS_SKIP_JS_BACKEND:-0}" == "1" ]]; then
			HARNESS_RESULTS+=("js-back-end|SKIP|-")
			info "JS back-end gate skipped (HARNESS_SKIP_JS_BACKEND=1 — registry inacessível)"
		else
			timed_gate "js-back-end" run_js_back_end_gate
		fi
	else
		HARNESS_RESULTS+=("js-back-end|SKIP|-")
		if [[ ${HARNESS_VERBOSE:-0} -eq 1 ]]; then
			warn "JS back-end gate not selected"
		fi
	fi

	if [[ $js_react_needed -eq 1 ]]; then
		timed_gate "js-react-static" run_js_react_static_gate
	else
		HARNESS_RESULTS+=("js-react-static|SKIP|-")
		if [[ ${HARNESS_VERBOSE:-0} -eq 1 ]]; then
			warn "JS react-static gate not selected"
		fi
	fi

	if [[ $js_static_needed -eq 1 ]]; then
		timed_gate "js-static" run_js_static_gate
	else
		HARNESS_RESULTS+=("js-static|SKIP|-")
		if [[ ${HARNESS_VERBOSE:-0} -eq 1 ]]; then
			warn "JS static gate not selected"
		fi
	fi

	if [[ $citools_needed -eq 1 ]]; then
		timed_gate "citools" run_citools_gate
	else
		HARNESS_RESULTS+=("citools|SKIP|-")
		if [[ ${HARNESS_VERBOSE:-0} -eq 1 ]]; then
			warn "Citools Rust gate not selected"
		fi
	fi

	if [[ $yaml_needed -eq 1 ]]; then
		if [[ "${HARNESS_SKIP_YAML:-0}" == "1" ]]; then
			HARNESS_RESULTS+=("yaml|SKIP|-")
			info "YAML gate skipped (HARNESS_SKIP_YAML=1 — lint path-scoped pendente no CI)"
		else
			timed_gate "yaml" run_yamllint_paths "${changed_paths[@]}"
		fi
	else
		HARNESS_RESULTS+=("yaml|SKIP|-")
		if [[ ${HARNESS_VERBOSE:-0} -eq 1 ]]; then
			warn "YAML gate not selected"
		fi
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

	timed_gate "shell-syntax" run_shell_syntax_checks "${shell_paths[@]}"
	timed_gate "shell-shellcheck" run_shellcheck_checks "${shell_paths[@]}"
	timed_gate "shell-shfmt" run_shfmt_checks "${shell_paths[@]}"
	timed_gate "rust" run_rust_observability_gate
	timed_gate "rust-ai-radar" run_rust_ai_radar_gate
	timed_gate "bats" run_cluster_bats_gate
	timed_gate "js-back-end" run_js_back_end_gate
	timed_gate "js-react-static" run_js_react_static_gate
	timed_gate "js-static" run_js_static_gate
	timed_gate "yaml" run_yamllint_all_manifests
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
	verify-changed | verify-all)
		HARNESS_START=$SECONDS
		trap 'print_summary' EXIT
		;;
	esac

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
