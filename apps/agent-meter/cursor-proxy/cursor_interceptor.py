"""
mitmproxy addon: Intercepts AI API calls from Cursor IDE and forwards
telemetry to agent-meter.

Usage:
    mitmdump -p 8898 -s cursor_interceptor.py --set confdir=~/.mitmproxy

Cursor routes LLM traffic to:
    - api.anthropic.com       (Claude — primary model for Cursor Agent)
    - api.openai.com          (GPT models)
    - api.githubcopilot.com   (GitHub Copilot backend, if enabled)
    - cursor.sh / api2.cursor.sh (Cursor's own proxy for some models)

The addon captures:
    - POST /v1/messages              (Anthropic chat)
    - POST /v1/chat/completions      (OpenAI / Copilot chat)
    - POST /v1/engines/*/completions (legacy completions)

Session/conversation grouping:
    Cursor sends `x-session-id` or `x-cursor-session` headers.
    Falls back to a shared trace_id per conversation window (30-min idle gap).
"""

import json
import os
import re
import time
import threading
from typing import Optional
import httpx
from mitmproxy import http, ctx

AGENT_METER_URL = "https://agent-meter.dnor.io/v1/traces"

# Hosts that carry Cursor's LLM traffic
AI_HOSTS = [
    "api.anthropic.com",
    "api.openai.com",
    "api.githubcopilot.com",
    "api.business.githubcopilot.com",
    "api.individual.githubcopilot.com",
    "copilot-proxy.githubusercontent.com",
    "cursor.sh",
    "api2.cursor.sh",
    "proxy.cursor.sh",
]

# Paths that indicate LLM/chat activity
LLM_PATHS = [
    "/v1/messages",           # Anthropic
    "/v1/chat/completions",   # OpenAI / Copilot
    "/v1/engines/",           # legacy
    "/completions",
    "/responses",
]

# ─── Session state ──────────────────────────────────────────────────────────
# Groups multiple LLM calls in the same Cursor conversation by session header.
# Key: session_id → {"trace_id": hex, "last_seen": float}
_sessions: dict = {}
_SESSION_IDLE_SEC = 1800  # 30 min


def _session_trace_id(session_id: str) -> str:
    now = time.time()
    entry = _sessions.get(session_id)
    if entry and (now - entry["last_seen"]) < _SESSION_IDLE_SEC:
        entry["last_seen"] = now
        return entry["trace_id"]
    trace_id = os.urandom(16).hex()
    _sessions[session_id] = {"trace_id": trace_id, "last_seen": now}
    return trace_id


# ─── Regex helpers ──────────────────────────────────────────────────────────
_ATTACHMENTS_RE = re.compile(r'<attachments>.*?</attachments>\s*', re.DOTALL)
_USER_REQUEST_RE = re.compile(r'<userRequest>\s*(.*?)\s*</userRequest>', re.DOTALL)


def _clean_prompt(text: str) -> str:
    if not text:
        return ""
    m = _USER_REQUEST_RE.search(text)
    if m:
        return m.group(1).strip()
    cleaned = _ATTACHMENTS_RE.sub('', text)
    cleaned = re.sub(r'<[^>]+>', ' ', cleaned)
    cleaned = re.sub(r'\s+', ' ', cleaned).strip()
    return cleaned[:500] if cleaned else ""


# ─── Request / Response extraction ──────────────────────────────────────────

def is_ai_request(flow: http.HTTPFlow) -> bool:
    host = flow.request.pretty_host.lower()
    return any(h in host for h in AI_HOSTS)


def is_llm_call(flow: http.HTTPFlow) -> bool:
    path = flow.request.path
    return any(p in path for p in LLM_PATHS)


# Real Cursor headers (observed from Cursor 0.43+):
#   x-cursor-checksum     — per-model-request hash (not stable across turns)
#   x-cursor-client-version — e.g. "0.43.5"
#   x-cursor-timezone     — e.g. "America/Sao_Paulo"
#   x-ghost-mode          — "true" / "false"
# Session stability: Cursor does NOT send a persistent session header for
# the conversation — we derive it from the auth token prefix (stable per login)
# or fall back to grouping by idle-window.
def extract_session_id(flow: http.HTTPFlow) -> Optional[str]:
    headers = flow.request.headers
    # Prefer explicit session headers (some Cursor builds send these)
    for key in ("x-session-id", "x-cursor-session", "vscode-sessionid"):
        if key in headers:
            return headers[key]
    # Use Bearer token prefix as stable session key (first 16 chars of token)
    auth = headers.get("authorization", "")
    if auth.startswith("Bearer "):
        token = auth[7:]
        # Strip JWT prefix if present — use first 16 chars of stable part
        parts = token.split(".")
        stable = parts[0][:16] if parts else token[:16]
        if stable:
            return f"cursor-{stable}"
    # Last resort: x-request-id changes per call, but we use it scoped to
    # the idle-window logic so grouping still works
    if "x-request-id" in headers:
        return headers["x-request-id"]
    return None


def extract_request_meta(flow: http.HTTPFlow) -> dict:
    meta = {
        "method": flow.request.method,
        "url": flow.request.url,
        "host": flow.request.pretty_host,
        "path": flow.request.path,
        "started_at": flow.request.timestamp_start,
    }
    if flow.request.content:
        meta["request_bytes"] = len(flow.request.content)

    sid = extract_session_id(flow)
    if sid:
        meta["session_id"] = sid

    if flow.request.content and flow.request.method == "POST":
        try:
            body = json.loads(flow.request.content)
            # model
            if "model" in body:
                meta["model"] = body["model"]
            # request params
            meta.update({k: body[k] for k in ("max_tokens", "temperature", "stream") if k in body})

            # OpenAI-style messages
            if "messages" in body:
                msgs = body["messages"]
                meta["message_count"] = len(msgs)
                user_msgs = [m for m in msgs if m.get("role") == "user"]
                if user_msgs:
                    last = user_msgs[-1].get("content", "")
                    if isinstance(last, str):
                        meta["user_prompt"] = _clean_prompt(last)
                    elif isinstance(last, list):
                        text = " ".join(p.get("text", "") for p in last if p.get("type") == "text")
                        meta["user_prompt"] = _clean_prompt(text)

            # Anthropic-style messages
            if "messages" not in body and "prompt" in body:
                meta["user_prompt"] = _clean_prompt(body["prompt"])

            # Tool results in input (Responses API)
            if "input" in body and isinstance(body["input"], list):
                items = body["input"]
                meta["input_items"] = items
                for item in reversed(items):
                    if item.get("role") == "user":
                        content = item.get("content", "")
                        raw = content if isinstance(content, str) else " ".join(
                            p.get("text", "") for p in content if p.get("type") in ("text", "input_text"))
                        cleaned = _clean_prompt(raw)
                        if cleaned:
                            meta["user_prompt"] = cleaned
                            break
                meta["tool_results_in_input"] = [
                    {"call_id": i.get("call_id", ""), "output": i.get("output", "")}
                    for i in items if i.get("type") == "function_call_output"
                ]
        except (json.JSONDecodeError, KeyError, TypeError):
            pass

    return meta


def extract_response_meta(flow: http.HTTPFlow) -> dict:
    meta = {
        "status_code": flow.response.status_code,
        "ended_at": flow.response.timestamp_end,
        "duration_ms": int((flow.response.timestamp_end - flow.request.timestamp_start) * 1000),
    }
    if flow.response.content:
        meta["response_bytes"] = len(flow.response.content)

    ct = flow.response.headers.get("content-type", "")
    is_stream = "event-stream" in ct

    if flow.response.content and not is_stream:
        try:
            body = json.loads(flow.response.content)

            # OpenAI / Copilot format
            if "usage" in body:
                u = body["usage"]
                meta["input_tokens"] = u.get("prompt_tokens") or u.get("input_tokens", 0)
                meta["output_tokens"] = u.get("completion_tokens") or u.get("output_tokens", 0)
                meta["total_tokens"] = u.get("total_tokens", 0)
                meta["cached_tokens"] = (u.get("prompt_tokens_details") or {}).get("cached_tokens", 0)
                meta["reasoning_tokens"] = (u.get("completion_tokens_details") or {}).get("reasoning_tokens", 0)
            if "model" in body:
                meta["model"] = body["model"]
            if "choices" in body and body["choices"]:
                choice = body["choices"][0]
                msg = choice.get("message", {})
                content = msg.get("content", "")
                if content:
                    meta["response_text"] = content
                    meta["response_preview"] = content[:200]
                meta["tool_calls"] = msg.get("tool_calls", [])
                meta["finish_reason"] = choice.get("finish_reason", "")

            # Anthropic format
            if "content" in body and "usage" not in body:
                # Anthropic /v1/messages response
                blocks = body.get("content", [])
                text_blocks = [b.get("text", "") for b in blocks if b.get("type") == "text"]
                tool_use_blocks = [b for b in blocks if b.get("type") == "tool_use"]
                if text_blocks:
                    meta["response_text"] = " ".join(text_blocks)
                    meta["response_preview"] = meta["response_text"][:200]
                if tool_use_blocks:
                    meta["tool_calls"] = [
                        {"name": b.get("name"), "call_id": b.get("id"), "arguments": json.dumps(b.get("input", {}))}
                        for b in tool_use_blocks
                    ]
                meta["finish_reason"] = body.get("stop_reason", "")
            if "usage" in body:
                # Anthropic also has usage in same response
                u = body["usage"]
                meta["input_tokens"] = u.get("input_tokens", 0)
                meta["output_tokens"] = u.get("output_tokens", 0)
                meta["cached_tokens"] = u.get("cache_read_input_tokens", 0)

        except (json.JSONDecodeError, KeyError, TypeError):
            pass

    elif flow.response.content and is_stream:
        try:
            raw = flow.response.content.decode("utf-8", errors="replace")
            # Try to find last data chunk with usage
            for line in reversed(raw.split("\n")):
                if line.startswith("data: ") and line != "data: [DONE]":
                    try:
                        chunk = json.loads(line[6:])
                        if "usage" in chunk:
                            u = chunk["usage"]
                            meta["input_tokens"] = u.get("prompt_tokens") or u.get("input_tokens", 0)
                            meta["output_tokens"] = u.get("completion_tokens") or u.get("output_tokens", 0)
                        if "model" in chunk:
                            meta["model"] = chunk["model"]
                        break
                    except (json.JSONDecodeError, KeyError):
                        continue
        except Exception:
            pass

    return meta


# ─── OTLP span sender ────────────────────────────────────────────────────────

def send_otlp_span(req_meta: dict, resp_meta: dict,
                   tool_call: dict = None,
                   parent_span_id: str = None,
                   shared_trace_id: str = None) -> tuple[str, str]:
    span_id = os.urandom(8).hex()
    trace_id = shared_trace_id or os.urandom(16).hex()

    session_id = req_meta.get("session_id", trace_id)
    conversation_id = session_id

    if tool_call:
        span_name = f"execute_tool {tool_call.get('name', 'tool_call')}"
    else:
        # For LLM spans, use "chat <model>" format so the backend detects them
        model = req_meta.get("model") or resp_meta.get("model") or "unknown"
        span_name = f"chat {model}"

    span = {
        "traceId": trace_id,
        "spanId": span_id,
        "name": span_name,
        "kind": 3,  # CLIENT
        "startTimeUnixNano": str(int(req_meta.get("started_at", time.time()) * 1_000_000_000)),
        "endTimeUnixNano": str(int(resp_meta.get("ended_at", time.time()) * 1_000_000_000)),
        "attributes": [],
        "status": {"code": 1 if resp_meta.get("status_code", 200) < 400 else 2},
    }
    if parent_span_id:
        span["parentSpanId"] = parent_span_id

    attrs: dict = {
        "gen_ai.conversation.id": conversation_id,
    }

    if tool_call:
        attrs["gen_ai.tool.name"] = tool_call.get("name", "")
        if tool_call.get("arguments"):
            attrs["gen_ai.tool.call.arguments"] = tool_call["arguments"]
        if tool_call.get("call_id"):
            attrs["gen_ai.tool.call_id"] = tool_call["call_id"]
        if tool_call.get("result"):
            attrs["gen_ai.tool.call.result"] = tool_call["result"]
    else:
        attrs["http.method"] = req_meta.get("method", "POST")
        attrs["http.url"] = req_meta.get("url", "")
        if resp_meta.get("response_text"):
            attrs["gen_ai.tool.call.result"] = resp_meta["response_text"][:2000]
        if req_meta.get("user_prompt"):
            attrs["gen_ai.prompt"] = req_meta["user_prompt"]

    model = req_meta.get("model") or resp_meta.get("model")
    if model:
        attrs["gen_ai.request.model"] = model
        attrs["gen_ai.response.model"] = model
    for k, src in [
        ("gen_ai.usage.input_tokens", "input_tokens"),
        ("gen_ai.usage.output_tokens", "output_tokens"),
        ("gen_ai.usage.cached_tokens", "cached_tokens"),
        ("gen_ai.usage.reasoning_tokens", "reasoning_tokens"),
        ("gen_ai.request.max_tokens", "max_tokens"),
        ("gen_ai.request.temperature", "temperature"),
        ("gen_ai.response.finish_reason", "finish_reason"),
    ]:
        if src in resp_meta:
            attrs[k] = resp_meta[src]
        elif src in req_meta:
            attrs[k] = req_meta[src]

    if session_id:
        attrs["copilot.conversation.id"] = session_id
    if resp_meta.get("duration_ms"):
        attrs["http.request.duration_ms"] = resp_meta["duration_ms"]

    # Detect LLM system from host
    host = req_meta.get("host", "")
    if "anthropic" in host:
        attrs["gen_ai.system"] = "anthropic"
    elif "openai" in host:
        attrs["gen_ai.system"] = "openai"
    else:
        attrs["gen_ai.system"] = "openai"

    for k, v in attrs.items():
        if isinstance(v, int):
            span["attributes"].append({"key": k, "value": {"intValue": str(v)}})
        elif isinstance(v, float):
            span["attributes"].append({"key": k, "value": {"doubleValue": v}})
        elif isinstance(v, str):
            span["attributes"].append({"key": k, "value": {"stringValue": v}})

    payload = {
        "resourceSpans": [{
            "resource": {
                "attributes": [
                    {"key": "service.name", "value": {"stringValue": "cursor"}},
                    {"key": "service.namespace", "value": {"stringValue": "ide"}},
                    {"key": "session.id", "value": {"stringValue": session_id}},
                ]
            },
            "scopeSpans": [{
                "scope": {"name": "cursor-interceptor", "version": "1.0.0"},
                "spans": [span],
            }]
        }]
    }

    def _send():
        try:
            r = httpx.post(
                AGENT_METER_URL,
                json=payload,
                headers={"Content-Type": "application/json"},
                timeout=5.0,
                verify=False,
            )
            ctx.log.info(f"[cursor-interceptor] OTLP span sent ({span_name}): {r.status_code}")
        except Exception as e:
            ctx.log.warn(f"[cursor-interceptor] OTLP send failed: {e}")

    threading.Thread(target=_send, daemon=True).start()
    return span_id, trace_id


# ─── mitmproxy Addon ─────────────────────────────────────────────────────────

class CursorInterceptor:
    def __init__(self):
        self.call_count = 0
        self.pending_tool_calls: dict = {}
        ctx.log.info("[cursor-interceptor] Loaded — watching for Cursor AI traffic...")

    def response(self, flow: http.HTTPFlow):
        if not is_ai_request(flow):
            return
        if not is_llm_call(flow):
            return

        self.call_count += 1
        req_meta = extract_request_meta(flow)
        resp_meta = extract_response_meta(flow)

        # Pick or create trace_id for this session
        session_id = req_meta.get("session_id", os.urandom(16).hex())
        shared_trace_id = _session_trace_id(session_id)

        model = req_meta.get("model") or resp_meta.get("model") or "unknown"
        ctx.log.info(
            f"[cursor-interceptor] #{self.call_count} "
            f"{req_meta['host']}{req_meta['path'][:50]} "
            f"→ {resp_meta['status_code']} "
            f"[{resp_meta.get('duration_ms')}ms model={model} "
            f"in={resp_meta.get('input_tokens',0)} out={resp_meta.get('output_tokens',0)}]"
        )

        # Emit tool-result spans for tool calls returning in this request's input
        tool_results_in_input = req_meta.get("tool_results_in_input", [])
        input_items = req_meta.get("input_items", [])
        if tool_results_in_input:
            fc_lookup = {i.get("id", ""): i for i in input_items if i.get("type") == "function_call"}
            for tr in tool_results_in_input:
                call_id = tr.get("call_id", "")
                result = tr.get("output", "")
                fc = fc_lookup.get(call_id) or self.pending_tool_calls.get(call_id, {})
                tc_with_result = {
                    "name": fc.get("name", "unknown_tool"),
                    "arguments": json.dumps(fc.get("input", fc.get("arguments", ""))),
                    "call_id": call_id,
                    "result": result,
                }
                ctx.log.info(f"[cursor-interceptor]   ✓ tool_result: {tc_with_result['name']}")
                send_otlp_span(req_meta, resp_meta, tool_call=tc_with_result,
                               shared_trace_id=shared_trace_id)
                self.pending_tool_calls.pop(call_id, None)

        # Emit main LLM span
        llm_span_id, _ = send_otlp_span(req_meta, resp_meta,
                                         shared_trace_id=shared_trace_id)

        # Emit child spans for each tool call in this response
        for tc in resp_meta.get("tool_calls", []):
            call_id = tc.get("id") or tc.get("call_id", "")
            tc_name = tc.get("name") or (tc.get("function") or {}).get("name", "unknown_tool")
            args_raw = tc.get("arguments") or json.dumps((tc.get("function") or {}).get("arguments", ""))
            ctx.log.info(f"[cursor-interceptor]   → tool_call pending: {tc_name}")
            if call_id:
                self.pending_tool_calls[call_id] = {
                    "name": tc_name,
                    "arguments": args_raw,
                    "_ts": time.time(),
                }
            send_otlp_span(req_meta, resp_meta,
                           tool_call={"name": tc_name, "arguments": args_raw, "call_id": call_id},
                           parent_span_id=llm_span_id,
                           shared_trace_id=shared_trace_id)

        # Expire stale pending calls (> 5 min)
        now = time.time()
        expired = [c for c, v in self.pending_tool_calls.items() if now - v.get("_ts", now) > 300]
        for c in expired:
            self.pending_tool_calls.pop(c, None)


addons = [CursorInterceptor()]
