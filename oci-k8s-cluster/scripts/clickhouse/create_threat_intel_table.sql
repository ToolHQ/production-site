CREATE TABLE IF NOT EXISTS default.threat_intel_events
(
    timestamp DateTime,
    service String,
    ip String,
    method String,
    path String,
    status String,
    classification String,
    user_agent String,
    time_elapsed Float64,
    country String
)
ENGINE = MergeTree()
PARTITION BY toYYYYMM(timestamp)
ORDER BY (service, timestamp, ip);
