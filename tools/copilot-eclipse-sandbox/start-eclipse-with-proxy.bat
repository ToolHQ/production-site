@echo off
REM ===================================================================
REM start-eclipse-with-proxy.bat
REM Inicia o proxy OTLP interceptor + Eclipse com proxy configurado.
REM O proxy captura chamadas do Copilot e emite spans para agent-meter.
REM ===================================================================

REM --- Configuração ---
set PROXY_PORT=18080
set AGENT_METER_ENDPOINT=https://agent-meter.dnor.io
set OTEL_SERVICE_NAME=eclipse-copilot
set ECLIPSE_PATH=C:\Users\dnorio\AppData\Local\eclipse\eclipse.exe

REM --- Verificar Node.js ---
where node >nul 2>nul
if errorlevel 1 (
    echo [ERRO] Node.js nao encontrado. Instale em https://nodejs.org
    pause
    exit /b 1
)

REM --- Verificar Eclipse ---
if not exist "%ECLIPSE_PATH%" (
    echo [ERRO] Eclipse nao encontrado em: %ECLIPSE_PATH%
    pause
    exit /b 1
)

REM --- Iniciar proxy em background ---
echo [OK] Iniciando proxy OTLP na porta %PROXY_PORT%...
start "Copilot OTLP Proxy" /MIN cmd /C "node %~dp0copilot-otlp-proxy.js"

REM --- Aguardar proxy subir ---
timeout /t 2 /nobreak >nul

REM --- Configurar proxy para o Eclipse ---
set HTTPS_PROXY=http://127.0.0.1:%PROXY_PORT%
set HTTP_PROXY=http://127.0.0.1:%PROXY_PORT%
set NO_PROXY=localhost,127.0.0.1

REM --- Variáveis OTEL (para javaagent no eclipse.ini) ---
set OTEL_EXPORTER_OTLP_ENDPOINT=%AGENT_METER_ENDPOINT%
set OTEL_EXPORTER_OTLP_PROTOCOL=http/protobuf
set OTEL_TRACES_EXPORTER=otlp
set OTEL_METRICS_EXPORTER=none
set OTEL_LOGS_EXPORTER=none
set OTEL_SERVICE_NAME=eclipse-copilot
set OTEL_RESOURCE_ATTRIBUTES=deployment.environment=dev,service.namespace=ide,service.version=1.0.0

REM --- Abrir Eclipse ---
echo [OK] Abrindo Eclipse com proxy OTLP + javaagent...
echo     Proxy: http://127.0.0.1:%PROXY_PORT%
echo     Endpoint: %AGENT_METER_ENDPOINT%
start "" "%ECLIPSE_PATH%"

echo.
echo [OK] Eclipse aberto. O proxy esta rodando em background.
echo     Para parar o proxy: feche a janela "Copilot OTLP Proxy".
echo.
