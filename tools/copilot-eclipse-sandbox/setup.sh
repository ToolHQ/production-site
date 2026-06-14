#!/usr/bin/env bash
# setup.sh — Baixa o OpenTelemetry Java Agent e prepara o projeto Eclipse.
# Para quem prefere rodar via Git Bash / WSL no Windows.
set -euo pipefail

OTEL_VERSION="2.12.0"
AGENT_URL="https://github.com/open-telemetry/opentelemetry-java-instrumentation/releases/download/v${OTEL_VERSION}/opentelemetry-javaagent.jar"
PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
LIB_DIR="${PROJECT_DIR}/lib"
AGENT_PATH="${LIB_DIR}/opentelemetry-javaagent.jar"

echo "=== Copilot Eclipse Sandbox — Setup ==="
echo ""

# 1. Criar pasta lib
mkdir -p "$LIB_DIR"
echo "[OK] Pasta lib/ pronta."

# 2. Baixar javaagent
if [ ! -f "$AGENT_PATH" ]; then
    echo "[...] Baixando OpenTelemetry Java Agent v${OTEL_VERSION}..."
    curl -fSL "$AGENT_URL" -o "$AGENT_PATH"
    echo "[OK] Agent baixado: $AGENT_PATH"
else
    echo "[OK] Agent ja existe: $AGENT_PATH"
fi

# 3. Verificar Java
if command -v java &>/dev/null; then
    echo "[OK] Java: $(java -version 2>&1 | head -1)"
else
    echo "[ERRO] Java nao encontrado. Instale JDK 17+."
    exit 1
fi

# 4. Verificar Maven
if command -v mvn &>/dev/null; then
    echo "[OK] Maven: $(mvn --version 2>&1 | head -1)"
else
    echo "[ERRO] Maven nao encontrado. Instale Maven 3.9+."
    exit 1
fi

# 5. Resolver dependencias
echo ""
echo "[...] Resolvendo dependencias Maven..."
cd "$PROJECT_DIR"
mvn dependency:resolve -q
mvn compile -q
echo "[OK] Dependencias baixadas e projeto compilado."

echo ""
echo "=== PRONTO ==="
echo ""
echo "Proximo passo:"
echo "  1. Abra Eclipse"
echo "  2. File > Import > Existing Maven Projects"
echo "  3. Aponte para esta pasta: $PROJECT_DIR"
echo "  4. Finish"
echo ""
echo "As Run Configurations ja estao prontas (.launch files)."
echo "Basta rodar pelo menu Run e os traces OTLP serao enviados"
echo "automaticamente para https://agent-meter.dnor.io"
echo ""
