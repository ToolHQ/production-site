sudo rm -f /etc/vector/vector.toml
sudo tee /etc/vector/vector.yaml > /dev/null <<IN_EOF
api:
  enabled: true
  address: "127.0.0.1:8686"

sources:
  fail2ban:
    type: file
    include:
      - /var/log/fail2ban.log
    read_from: end

transforms:
  fail2ban_parse:
    type: remap
    inputs:
      - fail2ban
    source: |-
      .raw_log = .message
      parsed = parse_regex(.message, r'^(?P<timestamp>\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2},\d{3})\s+fail2ban\.[\w\.]+\s+\[\d+\]:\s+\w+\s+\[(?P<service>[\w-]+)\] (?P<action>\w+)\s+(?P<ip>\d+\.\d+\.\d+\.\d+)') ?? {}
      
      if parsed != {} {
          .service = parsed.service
          .ip = parsed.ip
          
          action = string!(parsed.action)
          if action == "Ban" || action == "Restore" || action == "Found" {
              .status = downcase(action)
          } else {
              .status = action
          }
          
          .timestamp = parse_timestamp!(string!(parsed.timestamp), format: "%Y-%m-%d %H:%M:%S,%f")
      } else {
          .status = "unknown"
      }
      .source_node = "ssdnodes"
      .country = "Unknown"

sinks:
  clickhouse:
    type: clickhouse
    inputs:
      - fail2ban_parse
    endpoint: "http://100.97.87.39:80"
    database: "default"
    table: "threat_intel_events"
    auth:
      strategy: basic
      user: default
      password: i4FtSOCFXu
    request:
      headers:
        Host: clickhouse.dnor.io
    encoding:
      timestamp_format: rfc3339
IN_EOF

sudo systemctl restart vector
