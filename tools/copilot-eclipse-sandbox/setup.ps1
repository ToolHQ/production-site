#!/usr/bin/env pwsh
# setup.ps1 — Baixa o OpenTelemetry Java Agent e prepara o projeto Eclipse.
# Rodar uma vez antes de importar no Eclipse.

$ErrorActionPreference = "Stop"
$OTEL_VERSION = "2.12.0"
$AGENT_URL = "https://github.com/open-telemetry/opentelemetry-java-instrumentation/releases/download/v${OTEL_VERSION}/opentelemetry-javaagent.jar"
$PROJECT_DIR = Split-Path -Parent $MyInvocation.MyCommand.Path
$LIB_DIR = Join-Path $PROJECT_DIR "lib"
$AGENT_PATH = Join-Path $LIB_DIR "opentelemetry-javaagent.jar"

Write-Host "=== Copilot Eclipse Sandbox — Setup ==="
Write-Host ""

# 1. Criar pasta lib
if (-not (Test-Path $LIB_DIR)) {
    New-Item -ItemType Directory -Path $LIB_DIR | Out-Null
    Write-Host "[OK] Pasta lib/ criada."
} else {
    Write-Host "[OK] Pasta lib/ ja existe."
}

# 2. Baixar javaagent
if (-not (Test-Path $AGENT_PATH)) {
    Write-Host "[...] Baixando OpenTelemetry Java Agent v${OTEL_VERSION}..."
    Write-Host "     URL: $AGENT_URL"
    Invoke-WebRequest -Uri $AGENT_URL -OutFile $AGENT_PATH -UseBasicParsing
    Write-Host "[OK] Agent baixado: $AGENT_PATH"
} else {
    Write-Host "[OK] Agent ja existe: $AGENT_PATH"
}

# 3. Verificar Java
Write-Host ""
try {
    $javaVersion = & java -version 2>&1 | Select-Object -First 1
    Write-Host "[OK] Java encontrado: $javaVersion"
} catch {
    Write-Host "[ERRO] Java nao encontrado no PATH. Instale JDK 17+."
    exit 1
}

# 4. Verificar Maven
try {
    $mvnVersion = & mvn --version 2>&1 | Select-Object -First 1
    Write-Host "[OK] Maven encontrado: $mvnVersion"
} catch {
    Write-Host "[ERRO] Maven nao encontrado no PATH. Instale Maven 3.9+."
    exit 1
}

# 5. Rodar Maven para baixar dependencias
Write-Host ""
Write-Host "[...] Resolvendo dependencias Maven..."
Push-Location $PROJECT_DIR
& mvn dependency:resolve -q
& mvn compile -q
Write-Host "[OK] Dependencias baixadas e projeto compilado."
Pop-Location

Write-Host ""
Write-Host "=== PRONTO ==="
Write-Host ""
Write-Host "Proximo passo:"
Write-Host "  1. Abra Eclipse"
Write-Host "  2. File > Import > Existing Maven Projects"
Write-Host "  3. Aponte para esta pasta: $PROJECT_DIR"
Write-Host "  4. Finish"
Write-Host ""
Write-Host "As Run Configurations ja estao prontas (.launch files)."
Write-Host "Basta rodar pelo menu Run e os traces OTLP serao enviados"
Write-Host "automaticamente para https://agent-meter.dnor.io"
Write-Host ""
