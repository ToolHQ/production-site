#!/usr/bin/env bash
# warmup_ollama.sh — Pre-load Gemma/qwen into RAM after boot (T-335).
set -euo pipefail

REMOTE_HOST="${REMOTE_HOST:-ssdnodes-monstro}"
MODEL="${FLEET_OLLAMA_MODEL:-gemma3:4b}"

_SSH=(ssh -o BatchMode=yes -o ConnectTimeout=20)

echo "Warming Ollama model ${MODEL} on ${REMOTE_HOST}..."
"${_SSH[@]}" "$REMOTE_HOST" "curl -sf --max-time 300 http://127.0.0.1:11434/api/generate -d '$(cat <<EOF
{"model":"${MODEL}","prompt":"Responda apenas: ok","stream":false,"keep_alive":"30m"}
EOF
)'" >/dev/null
echo "Ollama warm-up OK (${MODEL})."
