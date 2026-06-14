#!/usr/bin/env bash
set -e

echo "=== Instalando Hermes Agent (Read-Only Ops Copilot) ==="

# 1. Criar usuário e diretórios
if ! id "hermes-ops" &>/dev/null; then
  echo "Criando usuário hermes-ops..."
  sudo useradd -r -m -s /bin/bash hermes-ops
else
  echo "Usuário hermes-ops já existe."
fi

sudo mkdir -p /home/hermes-ops/.hermes
sudo chown -R hermes-ops:hermes-ops /home/hermes-ops/.hermes

# 2. Instalar o binário do Hermes
if ! command -v hermes &> /dev/null; then
  echo "Baixando e instalando Hermes Agent..."
  # Usar script oficial da NousResearch
  curl -fsSL https://raw.githubusercontent.com/NousResearch/hermes-agent/main/scripts/install.sh | sudo bash
else
  echo "Hermes Agent já está instalado no sistema."
fi

# 3. Aplicar configuração restritiva
echo "Aplicando config.yaml restritivo..."
sudo cp config.yaml.example /home/hermes-ops/.hermes/config.yaml
sudo chown hermes-ops:hermes-ops /home/hermes-ops/.hermes/config.yaml
sudo chmod 600 /home/hermes-ops/.hermes/config.yaml

# 4. Instalar e iniciar o serviço systemd
echo "Instalando serviço hermes-ops.service..."
sudo cp hermes-ops.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable hermes-ops.service
sudo systemctl restart hermes-ops.service

echo "=== Hermes Agent provisionado com sucesso! ==="
echo "Verifique o status com: sudo systemctl status hermes-ops.service"
