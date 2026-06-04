#!/usr/bin/env bash
set -ex

# Install fail2ban
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y fail2ban

# Configure sshd jail
cat << 'JAIL' > /etc/fail2ban/jail.local
[DEFAULT]
bantime  = 1h
findtime = 10m
maxretry = 3
banaction = ufw

[sshd]
enabled = true
port    = ssh
logpath = %(sshd_log)s
backend = %(sshd_backend)s
JAIL

systemctl enable --now fail2ban
systemctl restart fail2ban
fail2ban-client status sshd
