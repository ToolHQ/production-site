#!/bin/bash
set -euo pipefail

NODE_TYPE=$1

if [ -z "$NODE_TYPE" ]; then
    echo "Usage: $0 <node_type>"
    exit 1
fi

echo "Installing Vector on $NODE_TYPE..."
curl -1sLf 'https://repositories.timber.io/public/vector/cfg/setup/bash.deb.sh' | sudo -E bash
sudo apt-get install -y vector

echo "Configuring Vector for $NODE_TYPE..."

CLICKHOUSE_ENDPOINT="http://100.97.87.39:80"
CLICKHOUSE_HOST="clickhouse.dnor.io"

sudo tee /etc/vector/vector.toml > /dev/null <<EOF
[api]
enabled = true
address = "127.0.0.1:8686"
EOF

if [ "$NODE_TYPE" == "ssdnodes" ]; then
sudo tee -a /etc/vector/vector.toml > /dev/null <<EOF

[sources.fail2ban]
type = "file"
include = ["/var/log/fail2ban.log"]
read_from = "end"

[transforms.fail2ban_parse]
type = "remap"
inputs = ["fail2ban"]
source = '''
.raw_log = .message
parsed = parse_regex(.message, r'^(?P<timestamp>\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2},\d{3})\s+fail2ban\.[\w\.]+\s+\[\d+\]:\s+\w+\s+\[(?P<service>[\w-]+)\] (?P<action>\w+)\s+(?P<ip>\d+\.\d+\.\d+\.\d+)') ?? {}

if parsed != {} {
    .service = parsed.service
    .ip = parsed.ip
    
    if parsed.action == "Ban" {
        .status = "banned"
    } else if parsed.action == "Restore" {
        .status = "unbanned"
    } else if parsed.action == "Found" {
        .status = "failed"
    } else {
        .status = parsed.action
    }
    
    # parse timestamp
    .timestamp = parse_timestamp!(parsed.timestamp, format: "%Y-%m-%d %H:%M:%S,%f")
} else {
    .status = "unknown"
}
.source_node = "ssdnodes"
.country = "Unknown"
'''

[sinks.clickhouse]
type = "clickhouse"
inputs = ["fail2ban_parse"]
endpoint = "${CLICKHOUSE_ENDPOINT}"
database = "default"
table = "threat_intel_events"
request.headers = { "Host" = "${CLICKHOUSE_HOST}", "X-ClickHouse-User" = "default", "X-ClickHouse-Key" = "i4FtSOCFXu" }
healthcheck.enabled = false
encoding.timestamp_format = "unix_ms"
EOF
elif [ "$NODE_TYPE" == "aws-ec2" ]; then
sudo tee -a /etc/vector/vector.toml > /dev/null <<EOF

[sources.honeypot]
type = "file"
include = ["/var/log/admin_honeypot.log"]
read_from = "end"

[transforms.honeypot_parse]
type = "remap"
inputs = ["honeypot"]
source = '''
parsed = parse_json(.message) ?? {}
if parsed != {} {
    . = merge(., parsed)
}
.raw_log = .message
.source_node = "aws-ec2"
.service = "admin_honeypot"
.status = "honeypot"
if !exists(.country) {
    .country = "Unknown"
}
if !exists(.ip) {
    .ip = "Unknown"
}
'''

[sinks.clickhouse]
type = "clickhouse"
inputs = ["honeypot_parse"]
endpoint = "${CLICKHOUSE_ENDPOINT}"
database = "default"
table = "threat_intel_events"
request.headers = { "Host" = "${CLICKHOUSE_HOST}", "X-ClickHouse-User" = "default", "X-ClickHouse-Key" = "i4FtSOCFXu" }
healthcheck.enabled = false
encoding.timestamp_format = "unix_ms"
EOF
fi

sudo systemctl enable vector
sudo systemctl restart vector
sudo systemctl status vector --no-pager
