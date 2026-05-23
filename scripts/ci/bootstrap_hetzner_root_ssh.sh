#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Uso:
  ./scripts/ci/bootstrap_hetzner_root_ssh.sh --host <ssh-host>

O script prepara, no host remoto, o acesso root por chave SSH.
Ele deve ser executado a partir da workstation local e usa o usuario atual do host.

Fluxo:
1. copia ~/.ssh/authorized_keys do usuario remoto para /tmp
2. roda comandos sudo remotos para instalar a chave em /root/.ssh/authorized_keys
3. garante PermitRootLogin=prohibit-password
4. reinicia ssh/sshd no host remoto

Requisitos:
- voce ja consegue acessar o host remoto com seu usuario normal via SSH
- esse usuario remoto possui sudo
- voce vai digitar a senha sudo no prompt remoto uma vez

Exemplo:
  ./scripts/ci/bootstrap_hetzner_root_ssh.sh --host hetzner-cax21-helsinki-4vcpu-8gb-ipv4
EOF
}

HOST=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --host)
      HOST="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "[erro] argumento desconhecido: $1" >&2
      usage
      exit 1
      ;;
  esac
done

if [[ -z "$HOST" ]]; then
  echo "[erro] --host e obrigatorio." >&2
  usage
  exit 1
fi

REMOTE_USER="$(ssh "$HOST" 'whoami')"

echo "[info] host remoto: $HOST"
echo "[info] usuario remoto atual: $REMOTE_USER"
echo "[info] preparando authorized_keys do usuario remoto para root..."

ssh -tt "$HOST" "set -euo pipefail
  test -f \"\$HOME/.ssh/authorized_keys\"
  cp \"\$HOME/.ssh/authorized_keys\" /tmp/${REMOTE_USER}.authorized_keys.root-bootstrap
  chmod 600 /tmp/${REMOTE_USER}.authorized_keys.root-bootstrap
  sudo install -d -m 700 /root/.ssh
  sudo install -m 600 /tmp/${REMOTE_USER}.authorized_keys.root-bootstrap /root/.ssh/authorized_keys
  sudo chown -R root:root /root/.ssh
  sudo sh -c '
    cfg=/etc/ssh/sshd_config
    if grep -q "^#\\?PermitRootLogin" "\$cfg"; then
      sed -i "s/^#\\?PermitRootLogin.*/PermitRootLogin prohibit-password/" "\$cfg"
    else
      printf "\\nPermitRootLogin prohibit-password\\n" >> "\$cfg"
    fi
  '
  sudo systemctl restart ssh 2>/dev/null || sudo systemctl restart sshd
"

echo "[ok] bootstrap concluido. Teste agora: ssh root@$HOST"