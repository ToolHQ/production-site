@echo off
REM ===================================================================
REM start-eclipse-otel.bat
REM Abre o Eclipse com variáveis OTEL configuradas para o agent-meter.
REM Coloque este arquivo na área de trabalho e use para abrir o Eclipse.
REM ===================================================================

REM --- Configuração OTEL ---
set OTEL_EXPORTER_OTLP_ENDPOINT=https://agent-meter.dnor.io
set OTEL_EXPORTER_OTLP_PROTOCOL=http/protobuf
set OTEL_TRACES_EXPORTER=otlp
set OTEL_SERVICE_NAME=eclipse-copilot
set OTEL_RESOURCE_ATTRIBUTES=deployment.environment=dev,service.namespace=ide,service.version=1.0.0

REM --- Caminho do Eclipse (AJUSTE PARA O SEU) ---
REM Exemplos comuns:
REM   C:\Users\dnorio\eclipse\jee-2024-12\eclipse\eclipse.exe
REM   C:\eclipse\eclipse.exe
REM   C:\Program Files\Eclipse\eclipse.exe

set ECLIPSE_PATH=C:\Users\dnorio\AppData\Local\eclipse\eclipse.exe

REM --- Verificar se existe ---
if not exist "%ECLIPSE_PATH%" (
    echo [ERRO] Eclipse nao encontrado em: %ECLIPSE_PATH%
    echo Edite este arquivo e ajuste ECLIPSE_PATH para o caminho correto.
    pause
    exit /b 1
)

REM --- Abrir Eclipse ---
echo [OK] Abrindo Eclipse com OTEL configurado...
echo     Endpoint: %OTEL_EXPORTER_OTLP_ENDPOINT%
echo     Service:  %OTEL_SERVICE_NAME%
start "" "%ECLIPSE_PATH%"
