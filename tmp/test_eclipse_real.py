#!/usr/bin/env python3
"""Test: simulate REAL Eclipse javaagent spans — GET requests to non-copilot URLs."""
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
        start_time_unix_nano=now_ns - 200_000_000,
        end_time_unix_nano=now_ns,
        status=Status(code=Status.STATUS_CODE_OK),
        attributes=[
            KeyValue(key="url.full", value=AnyValue(string_value=url)),
            KeyValue(key="http.request.method", value=AnyValue(string_value=name)),
            KeyValue(key="http.response.status_code", value=AnyValue(int_value=status_code)),
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
                        # Real Eclipse activity: marketplace, update checks, etc.
                        make_span("GET", "https://marketplace.eclipse.org/api/p/search"),
                        make_span("GET", "https://download.eclipse.org/releases/2026-03/compositeContent.xml"),
                        # The actual Copilot chat call
                        make_span("POST", "https://api.individual.githubcopilot.com/responses"),
                    ]
                )
            ]
        )
    ]
)

payload = req.SerializeToString()
print(f"Sending {len(payload)} bytes protobuf (Eclipse-like activity)...")

resp = requests.post(
    "https://agent-meter.dnor.io/v1/traces",
    data=payload,
    headers={
        "content-type": "application/x-protobuf",
        "user-agent": "eclipse/2026-03 jdt-ls",
    },
)
print(f"HTTP {resp.status_code}: {resp.text}")
