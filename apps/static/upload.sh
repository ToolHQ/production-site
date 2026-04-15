#!/bin/sh

set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
REPO_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/../.." && pwd)

SOURCE_DIR=${1:-dist}
TARGET_URI=${STATIC_UPLOAD_TARGET:-s3://my-site/static/}
ENDPOINT_URL=${STATIC_UPLOAD_ENDPOINT_URL:-https://minio.dnor.io}
DEFAULT_CA_BUNDLE="$REPO_ROOT/oci-k8s-cluster/dnor-ca-issuer.crt"

if [ -d "$SOURCE_DIR" ]; then
  SOURCE_PATH=$SOURCE_DIR
elif [ -d "$SCRIPT_DIR/$SOURCE_DIR" ]; then
  SOURCE_PATH="$SCRIPT_DIR/$SOURCE_DIR"
else
  echo "ERROR: static source directory not found: $SOURCE_DIR" >&2
  exit 1
fi

case "$ENDPOINT_URL" in
  https://*)
    if [ -z "${AWS_CA_BUNDLE:-}" ] && [ -f "$DEFAULT_CA_BUNDLE" ]; then
      export AWS_CA_BUNDLE="$DEFAULT_CA_BUNDLE"
    fi
    ;;
esac

if [ -z "${AWS_ACCESS_KEY_ID:-}" ] && [ -n "${MINIO_ACCESS_KEY:-}" ]; then
  export AWS_ACCESS_KEY_ID="$MINIO_ACCESS_KEY"
fi

if [ -z "${AWS_SECRET_ACCESS_KEY:-}" ] && [ -n "${MINIO_SECRET_KEY:-}" ]; then
  export AWS_SECRET_ACCESS_KEY="$MINIO_SECRET_KEY"
fi

if [ -z "${AWS_ACCESS_KEY_ID:-}" ] || [ -z "${AWS_SECRET_ACCESS_KEY:-}" ]; then
  echo "ERROR: MinIO credentials not configured for static upload" >&2
  exit 1
fi

unset AWS_PROFILE AWS_DEFAULT_PROFILE AWS_SESSION_TOKEN

echo "Uploading $SOURCE_PATH to $TARGET_URI via $ENDPOINT_URL"
aws --endpoint-url "$ENDPOINT_URL" s3 sync --delete "$SOURCE_PATH" "$TARGET_URI"
