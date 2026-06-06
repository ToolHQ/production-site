#!/usr/bin/env python3
"""Test: send a protobuf OTLP trace that simulates Eclipse javaagent HTTP spans."""
import time
import requests
from opentelemetry.proto.collector.trace.v1.trace_service_pb2 import ExportTraceServiceRequest
from opentelemetry.proto.trace.v1.trace_pb2 import ResourceSpans, ScopeSpans, Span, Status
from opentelemetry.proto.resource.v1.resource_pb2 import Resource
from opentelemetry.proto.common.v1.common_pb2 import KeyValue, AnyValue, InstrumentationScope

def make_span(name, url, status_code=200):
    now_ns = int(time.time() * 1e9)
    return Span(
        name=name,
        start_time_unix_nano=now_ns - 800_000_000,
        end_time_unix_nano=now_ns,
        status=Status(code=Status.STATUS_CODE_OK),
        attributes=[
            KeyValue(key="http.url", value=AnyValue(string_value=url)),
            KeyValue(key="http.method", value=AnyValue(string_value="POST")),
            KeyValue(key="http.status_code", value=AnyValue(int_value=status_code)),
        ],
    )

resource = Resource(attributes=[
    KeyValue(key="service.name", value=AnyValue(string_value="eclipse-copilot")),
])

scope = InstrumentationScope(name="io.opentelemetry.java-http-client")

req = ExportTraceServiceRequest(
    resource_spans=[
        ResourceSpans(
            resource=resource,
            scope_spans=[
                ScopeSpans(
                    scope=scope,
                    spans=[
                        # This should be classified as llm_chat (has /responses)
                        make_span("POST", "https://api.individual.githubcopilot.com/responses"),
                        # This should be classified as copilot_auth
                        make_span("POST", "https://api.github.com/copilot_internal/v2/token"),
                    ]
                )
            ]
        )
    ]
)

payload = req.SerializeToString()
print(f"Sending {len(payload)} bytes protobuf to agent-meter...")

resp = requests.post(
    "https://agent-meter.dnor.io/v1/traces",
    data=payload,
    headers={
        "content-type": "application/x-protobuf",
        "user-agent": "eclipse/2026-03 jdt-ls",
    },
)
print(f"HTTP {resp.status_code}: {resp.text}")
