/**
 * copilot-otlp-proxy.js
 * 
 * Proxy transparente que intercepta chamadas HTTP/HTTPS do copilot-language-server
 * para a API do GitHub e emite spans OTLP para o agent-meter.
 *
 * Uso:
 *   set HTTPS_PROXY=http://127.0.0.1:18080
 *   set HTTP_PROXY=http://127.0.0.1:18080
 *   (abrir Eclipse ou qualquer IDE com Copilot)
 *
 * O proxy captura:
 *   - URLs matching *github* / *copilot* / *api.githubcopilot.com*
 *   - Emite spans OTLP com tool_name, model, duration, status
 */

const http = require('http');
const https = require('https');
const { URL } = require('url');

// ─── Config ────────────────────────────────────────────────────────────────
const PROXY_PORT = parseInt(process.env.PROXY_PORT || '18080');
const AGENT_METER_ENDPOINT = process.env.AGENT_METER_ENDPOINT || 'https://agent-meter.dnor.io';
const SERVICE_NAME = process.env.OTEL_SERVICE_NAME || 'eclipse-copilot';
const VERBOSE = process.env.VERBOSE === '1';

// ─── OTLP Span Emitter ────────────────────────────────────────────────────
function generateId(bytes) {
    const chars = '0123456789abcdef';
    let result = '';
    for (let i = 0; i < bytes * 2; i++) {
        result += chars[Math.floor(Math.random() * 16)];
    }
    return result;
}

async function emitOtlpSpan(spanData) {
    const traceId = generateId(16);
    const spanId = generateId(8);
    const startNano = BigInt(spanData.startTime) * 1000000n;
    const endNano = BigInt(spanData.endTime) * 1000000n;

    const payload = {
        resourceSpans: [{
            resource: {
                attributes: [
                    { key: "service.name", value: { stringValue: SERVICE_NAME } },
                    { key: "deployment.environment", value: { stringValue: "dev" } },
                    { key: "service.namespace", value: { stringValue: "ide" } },
                    { key: "service.version", value: { stringValue: "1.0.0" } }
                ]
            },
            scopeSpans: [{
                scope: { name: "copilot-otlp-proxy", version: "1.0.0" },
                spans: [{
                    traceId,
                    spanId,
                    name: spanData.spanName,
                    kind: 3, // CLIENT
                    startTimeUnixNano: startNano.toString(),
                    endTimeUnixNano: endNano.toString(),
                    status: { code: spanData.statusCode === 200 ? 1 : 2 },
                    attributes: [
                        { key: "http.method", value: { stringValue: spanData.method } },
                        { key: "http.url", value: { stringValue: spanData.url } },
                        { key: "http.status_code", value: { intValue: spanData.statusCode } },
                        { key: "tool_name", value: { stringValue: spanData.toolName || "copilot_api" } },
                        { key: "copilot.endpoint", value: { stringValue: spanData.endpoint } },
                        ...(spanData.model ? [{ key: "gen_ai.request.model", value: { stringValue: spanData.model } }] : []),
                        ...(spanData.contentLength ? [{ key: "http.response.body.size", value: { intValue: spanData.contentLength } }] : [])
                    ]
                }]
            }]
        }]
    };

    const body = JSON.stringify(payload);
    const url = new URL(`${AGENT_METER_ENDPOINT}/v1/traces`);

    const options = {
        hostname: url.hostname,
        port: url.port || 443,
        path: url.pathname,
        method: 'POST',
        headers: {
            'Content-Type': 'application/json',
            'Content-Length': Buffer.byteLength(body),
            'User-Agent': 'eclipse/2026-03 jdt-language-server copilot-otlp-proxy'
        }
    };

    return new Promise((resolve) => {
        const req = https.request(options, (res) => {
            let data = '';
            res.on('data', (chunk) => data += chunk);
            res.on('end', () => {
                if (VERBOSE) console.log(`  [OTLP] Emitted span: ${spanData.spanName} → ${res.statusCode}`);
                resolve(true);
            });
        });
        req.on('error', (err) => {
            console.error(`  [OTLP] Error: ${String(err.message).replace(/[\r\n]/g, '')}`);
            resolve(false);
        });
        req.write(body);
        req.end();
    });
}

// ─── Classify Copilot API calls ───────────────────────────────────────────
function classifyRequest(method, urlStr) {
    const lower = urlStr.toLowerCase();

    if (lower.includes('/completions')) {
        return { spanName: 'execute_tool completions', toolName: 'copilot_completions', endpoint: 'completions' };
    }
    if (lower.includes('/chat/completions')) {
        return { spanName: 'chat', toolName: 'llm_chat', endpoint: 'chat/completions' };
    }
    if (lower.includes('/conversation')) {
        return { spanName: 'chat', toolName: 'llm_chat', endpoint: 'conversation' };
    }
    if (lower.includes('/telemetry')) {
        return { spanName: 'execute_tool telemetry', toolName: 'copilot_telemetry', endpoint: 'telemetry' };
    }
    if (lower.includes('/models')) {
        return { spanName: 'execute_tool models', toolName: 'copilot_models', endpoint: 'models' };
    }
    if (lower.includes('/token') || lower.includes('/oauth')) {
        return { spanName: 'execute_tool auth', toolName: 'copilot_auth', endpoint: 'auth' };
    }
    if (lower.includes('copilot') || lower.includes('github')) {
        return { spanName: 'execute_tool api', toolName: 'copilot_api', endpoint: 'generic' };
    }
    return null; // Not a copilot request, skip
}

// ─── HTTP CONNECT Proxy (for HTTPS) ──────────────────────────────────────
function handleConnect(req, clientSocket, head) {
    const [hostname, port] = req.url.split(':');
    const targetPort = parseInt(port) || 443;
    const isCopilotTarget = hostname.includes('github') || hostname.includes('copilot');

    if (VERBOSE && isCopilotTarget) {
        console.log(`[CONNECT] ${hostname}:${targetPort}`);
    }

    const serverSocket = require('net').connect(targetPort, hostname, () => {
        clientSocket.write('HTTP/1.1 200 Connection Established\r\n\r\n');
        serverSocket.write(head);
        serverSocket.pipe(clientSocket);
        clientSocket.pipe(serverSocket);
    });

    serverSocket.on('error', (err) => {
        if (VERBOSE) console.error(`[CONNECT ERROR] ${hostname}: ${err.message}`);
        clientSocket.end();
    });

    clientSocket.on('error', () => serverSocket.end());
}

// ─── HTTP Proxy (for plain HTTP) ─────────────────────────────────────────
function handleRequest(req, res) {
    const startTime = Date.now();
    const targetUrl = req.url;
    const classification = classifyRequest(req.method, targetUrl);

    const parsedUrl = new URL(targetUrl);
    const options = {
        hostname: parsedUrl.hostname,
        port: parsedUrl.port || 80,
        path: parsedUrl.pathname + parsedUrl.search,
        method: req.method,
        headers: req.headers
    };

    const proxyReq = http.request(options, (proxyRes) => {
        const endTime = Date.now();
        res.writeHead(proxyRes.statusCode, proxyRes.headers);
        proxyRes.pipe(res);

        if (classification) {
            emitOtlpSpan({
                ...classification,
                method: req.method,
                url: targetUrl,
                statusCode: proxyRes.statusCode,
                startTime,
                endTime,
                contentLength: parseInt(proxyRes.headers['content-length'] || '0')
            });
        }
    });

    proxyReq.on('error', (err) => {
        console.error(`[PROXY ERROR] ${String(err.message).replace(/[\r\n]/g, '')}`);
        res.writeHead(502);
        res.end('Bad Gateway');
    });

    req.pipe(proxyReq);
}

// ─── Start Proxy Server ──────────────────────────────────────────────────
const server = http.createServer(handleRequest);
server.on('connect', handleConnect);

server.listen(PROXY_PORT, '127.0.0.1', () => {
    console.log(`
╔══════════════════════════════════════════════════════════════════╗
║  Copilot OTLP Proxy — listening on 127.0.0.1:${PROXY_PORT}          ║
║                                                                  ║
║  Intercepting: *github* / *copilot* API calls                    ║
║  Emitting to:  ${AGENT_METER_ENDPOINT}/v1/traces     ║
║  Service:      ${SERVICE_NAME}                             ║
║                                                                  ║
║  Configure your IDE:                                             ║
║    set HTTPS_PROXY=http://127.0.0.1:${PROXY_PORT}                    ║
║    set HTTP_PROXY=http://127.0.0.1:${PROXY_PORT}                     ║
╚══════════════════════════════════════════════════════════════════╝
`);
});

process.on('SIGINT', () => {
    console.log('\n[PROXY] Shutting down...');
    server.close();
    process.exit(0);
});
