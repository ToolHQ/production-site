#!/bin/bash
set -e

# Setup Vector for SSDNodes (fail2ban/sshd -> ClickHouse)
echo "Installing Vector..."
curl -1sLf "https://repositories.timber.io/public/vector/cfg/setup/bash.deb.sh" | sudo -E bash
sudo apt-get install -y vector

echo "Configuring Vector..."
cat << 'EOF' | sudo tee /etc/vector/vector.toml
[sources.journald_ssh]
type = "journald"
include_units = ["ssh.service", "fail2ban.service"]

[transforms.filter_ssh]
type = "filter"
inputs = ["journald_ssh"]
condition = '''
  includes(["ssh", "sshd", "fail2ban-server", "fail2ban"], .SYSLOG_IDENTIFIER) || 
  includes(["ssh", "sshd", "fail2ban-server", "fail2ban"], ._COMM)
'''

[transforms.parse_ssh]
type = "remap"
inputs = ["filter_ssh"]
source = '''
  service = .SYSLOG_IDENTIFIER || ._COMM || "unknown"
  if includes(service, "sshd") || includes(service, "ssh") {
    service = "sshd"
  } else if includes(service, "fail2ban") {
    service = "fail2ban"
  }

  status = "unknown"
  classification = "unknown"
  ip = ""

  if service == "fail2ban" {
    # Parse Ban/Unban/Found
    if match(.message, r'\[sshd\] Found (.*)') {
      status = "found"
      classification = "malicious"
      parsed = parse_regex!(.message, r'\[sshd\] Found (?P<ip>[0-9\.]+) -.*')
      ip = parsed.ip
    } else if match(.message, r'\[sshd\] Ban (.*)') {
      status = "banned"
      classification = "malicious"
      parsed = parse_regex!(.message, r'\[sshd\] Ban (?P<ip>[0-9\.]+)')
      ip = parsed.ip
    }
  } else if service == "sshd" {
    if match(.message, r'Failed password') || match(.message, r'Invalid user') || match(.message, r'Disconnected from invalid user') {
      status = "failed"
      classification = "malicious"
      # Try to extract IP
      parsed_ip = parse_regex(.message, r'(?P<ip>[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3})')
      if parsed_ip != null {
        ip = parsed_ip.ip
      }
    } else if match(.message, r'Accepted publickey') {
      status = "success"
      classification = "benign"
    }
  }

  . = {
    "timestamp": format_timestamp!(.timestamp, format: "%Y-%m-%d %H:%M:%S"),
    "service": service,
    "ip": ip,
    "method": "-",
    "path": "-",
    "status": status,
    "classification": classification,
    "user_agent": "-",
    "time_elapsed": 0.0,
    "country": ""
  }
'''

[sinks.clickhouse_out]
type = "clickhouse"
inputs = ["parse_ssh"]
endpoint = "https://clickhouse.dnor.io"
database = "default"
table = "threat_intel_events"
auth.strategy = "basic"
auth.user = "default"
auth.password = "i4FtSOCFXu"
compression = "gzip"
skip_unknown_fields = true
EOF

echo "Restarting Vector..."
sudo systemctl enable vector
sudo systemctl restart vector
sudo systemctl status vector --no-pager

echo "Vector configured successfully on SSDNodes!"
