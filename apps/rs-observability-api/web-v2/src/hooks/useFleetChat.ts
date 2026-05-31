import { useCallback, useEffect, useRef, useState } from 'preact/hooks';

import { SSDNODES_HOSTNAME } from '../constants/fleetHosts';

const STORAGE_KEY = 'fleet-copilot-messages-v1';
const MAX_MESSAGES = 20;

export const PRESET_PROMPTS = {
  'ssdnodes-health': `Como estão disco, memória e carga no host ${SSDNODES_HOSTNAME} agora?`,
  'ssdnodes-k8s': `Há pods não Running, ingress ou warnings no cluster K8s em ${SSDNODES_HOSTNAME}?`,
  'ssdnodes-ssh': `Resuma tentativas SSH suspeitas nas últimas 24h em ${SSDNODES_HOSTNAME}.`,
} as const;

export type FleetPreset = keyof typeof PRESET_PROMPTS;

export interface FleetChatMessage {
  id: string;
  role: 'user' | 'assistant';
  text: string;
  sources?: string[];
  model?: string;
  latencyMs?: number;
  at: number;
}

function loadMessages(): FleetChatMessage[] {
  try {
    const raw = sessionStorage.getItem(STORAGE_KEY);
    if (!raw) return [];
    const parsed = JSON.parse(raw) as FleetChatMessage[];
    return Array.isArray(parsed) ? parsed.slice(-MAX_MESSAGES) : [];
  } catch {
    return [];
  }
}

function saveMessages(messages: FleetChatMessage[]) {
  sessionStorage.setItem(STORAGE_KEY, JSON.stringify(messages.slice(-MAX_MESSAGES)));
}

function newId() {
  return `${Date.now()}-${Math.random().toString(36).slice(2, 8)}`;
}

function parseSseBlock(block: string): { event: string; data: string } | null {
  let event = 'message';
  let data = '';
  for (const line of block.split('\n')) {
    if (line.startsWith('event:')) event = line.slice(6).trim();
    if (line.startsWith('data:')) data += line.slice(5).trim();
  }
  return data ? { event, data } : null;
}

async function consumeSse(
  res: Response,
  onEvent: (event: string, data: string) => void,
  signal: AbortSignal,
) {
  const reader = res.body?.getReader();
  if (!reader) throw new Error('stream unavailable');

  const decoder = new TextDecoder();
  let buffer = '';

  while (!signal.aborted) {
    const { done, value } = await reader.read();
    if (done) break;
    buffer += decoder.decode(value, { stream: true });

    let idx = buffer.indexOf('\n\n');
    while (idx !== -1) {
      const block = buffer.slice(0, idx);
      buffer = buffer.slice(idx + 2);
      const parsed = parseSseBlock(block);
      if (parsed) onEvent(parsed.event, parsed.data);
      idx = buffer.indexOf('\n\n');
    }
  }

  // Flush SSE residual no browser
  const tail = buffer.trim();
  if (tail) {
    const parsed = parseSseBlock(tail);
    if (parsed) onEvent(parsed.event, parsed.data);
  }
}

export function useFleetChat() {
  const [messages, setMessages] = useState<FleetChatMessage[]>(loadMessages);
  const [preset, setPreset] = useState<FleetPreset>('ssdnodes-health');
  const [loading, setLoading] = useState(false);
  const [loadingPhase, setLoadingPhase] = useState<'collect' | 'infer' | null>(null);
  const [streamText, setStreamText] = useState('');
  const [elapsedSec, setElapsedSec] = useState(0);
  const [error, setError] = useState<string | null>(null);
  const abortRef = useRef<AbortController | null>(null);
  const timerRef = useRef<ReturnType<typeof setInterval> | null>(null);

  useEffect(() => {
    saveMessages(messages);
  }, [messages]);

  useEffect(() => {
    return () => {
      abortRef.current?.abort();
      if (timerRef.current) clearInterval(timerRef.current);
    };
  }, []);

  const clearHistory = useCallback(() => {
    setMessages([]);
    sessionStorage.removeItem(STORAGE_KEY);
  }, []);

  const send = useCallback(
    async (text: string, presetId: FleetPreset = preset) => {
      const trimmed = text.trim();
      if (!trimmed || loading) return;

      abortRef.current?.abort();
      const controller = new AbortController();
      abortRef.current = controller;

      setLoading(true);
      setError(null);
      setStreamText('');
      setElapsedSec(0);
      setLoadingPhase('collect');
      timerRef.current = setInterval(() => setElapsedSec((s) => s + 1), 1000);

      const userMsg: FleetChatMessage = {
        id: newId(),
        role: 'user',
        text: trimmed,
        at: Date.now(),
      };
      setMessages((m) => [...m, userMsg]);

      let sources: string[] = [];
      let reply = '';
      let model: string | undefined;
      let latencyMs: number | undefined;
      let streamError: string | null = null;

      const finish = () => {
        if (timerRef.current) {
          clearInterval(timerRef.current);
          timerRef.current = null;
        }
        setLoading(false);
        setLoadingPhase(null);
        setStreamText('');
        abortRef.current = null;
      };

      try {
        const res = await fetch('/api/fleet/chat/stream', {
          method: 'POST',
          credentials: 'same-origin',
          signal: controller.signal,
          headers: {
            'Content-Type': 'application/json',
            Accept: 'text/event-stream',
          },
          body: JSON.stringify({ message: trimmed, preset: presetId }),
        });

        if (res.status === 404) {
          setError('Sessão expirada — peça ao operador um novo link de acesso.');
          finish();
          return;
        }
        if (res.status === 429) {
          setError('Limite de requisições — aguarde cerca de 1 minuto.');
          finish();
          return;
        }
        if (!res.ok) {
          setError(
            res.status === 502
              ? 'Gateway ou modelo indisponível — tente novamente em instantes.'
              : `Erro HTTP ${res.status}`,
          );
          finish();
          return;
        }

        await consumeSse(
          res,
          (event, data) => {
            try {
              const payload = JSON.parse(data) as Record<string, unknown>;
              if (event === 'phase') {
                setLoadingPhase(payload.phase === 'infer' ? 'infer' : 'collect');
                if (Array.isArray(payload.sources)) {
                  sources = payload.sources as string[];
                }
              } else if (event === 'token') {
                const delta = payload.delta;
                if (typeof delta === 'string' && delta) {
                  reply += delta;
                  setStreamText((prev) => prev + delta);
                  setLoadingPhase('infer');
                }
              } else if (event === 'done') {
                if (typeof payload.reply === 'string' && payload.reply) {
                  if (payload.reply.length >= reply.length) {
                    reply = payload.reply;
                  }
                }
                if (typeof payload.model === 'string') {
                  model = payload.model;
                }
                if (Array.isArray(payload.sources)) {
                  sources = payload.sources as string[];
                }
                if (typeof payload.latency_ms === 'number') {
                  latencyMs = payload.latency_ms;
                }
                if (payload.partial === true && reply.trim()) {
                  reply = `${reply.trim()}…`;
                }
              } else if (event === 'error') {
                const raw =
                  typeof payload.message === 'string'
                    ? payload.message
                    : 'Falha no stream';
                streamError = raw.includes('ollama stream')
                  ? 'O modelo demorou ou a conexão caiu — tente de novo (a resposta pode levar até 3 min).'
                  : raw;
              }
            } catch {
              /* ignore malformed sse payloads */
            }
          },
          controller.signal,
        );

        if (streamError) {
          setError(streamError);
        } else if (reply.trim()) {
          setMessages((m) => [
            ...m,
            {
              id: newId(),
              role: 'assistant',
              text: reply.trim(),
              sources,
              model,
              latencyMs,
              at: Date.now(),
            },
          ]);
        } else {
          setError('Resposta vazia do modelo.');
        }
      } catch (e) {
        if (controller.signal.aborted) {
          setError('Consulta cancelada.');
        } else {
          setError(e instanceof Error ? e.message : 'Falha na consulta');
        }
      } finally {
        finish();
      }
    },
    [loading, preset],
  );

  const cancel = useCallback(() => {
    abortRef.current?.abort();
  }, []);

  return {
    messages,
    preset,
    setPreset,
    loading,
    loadingPhase,
    streamText,
    elapsedSec,
    error,
    send,
    cancel,
    clearHistory,
  };
}
