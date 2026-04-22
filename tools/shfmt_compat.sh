#!/usr/bin/env bash
set -euo pipefail

MIN_SHFMT_VERSION="${PRODUCTION_SITE_MIN_SHFMT_VERSION:-3.8.0}"
CACHE_ROOT="${XDG_CACHE_HOME:-$HOME/.cache}/production-site/shfmt"

normalize_version() {
	echo "${1#v}"
}

version_gte() {
	local left right
	left="$(normalize_version "$1")"
	right="$(normalize_version "$2")"
	[[ "$(printf '%s\n%s\n' "$left" "$right" | sort -V | tail -n1)" == "$left" ]]
}

detect_platform() {
	local os arch
	os="$(uname -s | tr '[:upper:]' '[:lower:]')"
	arch="$(uname -m)"

	case "$arch" in
	x86_64 | amd64) arch="amd64" ;;
	aarch64 | arm64) arch="arm64" ;;
	*)
		echo "Unsupported architecture for shfmt compatibility wrapper: $arch" >&2
		exit 1
		;;
	esac

	echo "$os" "$arch"
}

download_compatible_shfmt() {
	local os arch cache_dir download_url cached_bin tmp_dir
	read -r os arch < <(detect_platform)

	cache_dir="$CACHE_ROOT/v$MIN_SHFMT_VERSION/$os-$arch"
	cached_bin="$cache_dir/shfmt"
	if [[ -x "$cached_bin" ]]; then
		echo "$cached_bin"
		return 0
	fi

	mkdir -p "$cache_dir"
	tmp_dir="$(mktemp -d)"
	trap '[[ -n "${tmp_dir:-}" ]] && rm -rf "$tmp_dir"' RETURN

	download_url="https://github.com/mvdan/sh/releases/download/v${MIN_SHFMT_VERSION}/shfmt_v${MIN_SHFMT_VERSION}_${os}_${arch}"
	curl -fsSL "$download_url" -o "$tmp_dir/shfmt"
	install -m 0755 "$tmp_dir/shfmt" "$cached_bin"

	echo "$cached_bin"
}

resolve_shfmt_bin() {
	local system_shfmt current_version
	system_shfmt="$(command -v shfmt || true)"
	if [[ -n "$system_shfmt" ]]; then
		current_version="$($system_shfmt --version 2>/dev/null || true)"
		if [[ -n "$current_version" ]] && version_gte "$current_version" "$MIN_SHFMT_VERSION"; then
			echo "$system_shfmt"
			return 0
		fi
	fi

	download_compatible_shfmt
}

exec "$(resolve_shfmt_bin)" "$@"
