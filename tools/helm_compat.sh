#!/usr/bin/env bash
set -euo pipefail

MIN_HELM_VERSION="${PRODUCTION_SITE_MIN_HELM_VERSION:-3.19.0}"
CACHE_ROOT="${XDG_CACHE_HOME:-$HOME/.cache}/production-site/helm"

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
        x86_64|amd64) arch="amd64" ;;
        aarch64|arm64) arch="arm64" ;;
        *)
            echo "Unsupported architecture for Helm compatibility wrapper: $arch" >&2
            exit 1
            ;;
    esac

    echo "$os" "$arch"
}

download_compatible_helm() {
    local os arch cache_dir archive_url tmp_dir cached_bin
    read -r os arch < <(detect_platform)

    cache_dir="$CACHE_ROOT/v$MIN_HELM_VERSION/$os-$arch"
    cached_bin="$cache_dir/helm"
    if [[ -x "$cached_bin" ]]; then
        echo "$cached_bin"
        return 0
    fi

    mkdir -p "$cache_dir"
    tmp_dir="$(mktemp -d)"
    trap '[[ -n "${tmp_dir:-}" ]] && rm -rf "$tmp_dir"' RETURN

    archive_url="https://get.helm.sh/helm-v${MIN_HELM_VERSION}-${os}-${arch}.tar.gz"
    curl -fsSL "$archive_url" -o "$tmp_dir/helm.tgz"
    tar -xzf "$tmp_dir/helm.tgz" -C "$tmp_dir"
    install -m 0755 "$tmp_dir/$os-$arch/helm" "$cached_bin"

    echo "$cached_bin"
}

resolve_helm_bin() {
    local system_helm current_version
    system_helm="$(command -v helm || true)"
    if [[ -n "$system_helm" ]]; then
        current_version="$($system_helm version --template '{{ .Version }}' 2>/dev/null || true)"
        if [[ -n "$current_version" ]] && version_gte "$current_version" "$MIN_HELM_VERSION"; then
            echo "$system_helm"
            return 0
        fi
    fi

    download_compatible_helm
}

exec "$(resolve_helm_bin)" "$@"