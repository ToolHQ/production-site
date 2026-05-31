import { useCallback, useEffect, useRef, useState } from 'preact/hooks';
import type { ChatResponse } from '../types/fleetCopilot';

const STORAGE_KEY = 'fleet-copilot-messages-v1';
const MAX_MESSAGES = 20;

export const PRESET_PROMPTS = {
  'ssdnodes-health': 'Como estão disco, memória e carga no SSDNodes agora?',
  'ssdnodes-k8s': 'Há pods não Running, ingress ou warnings no cluster SSDNodes?',
  'ssdnodes-ssh': 'Resuma tentativas SSH suspeitas nas últimas 24h no monstro.',
} as const;

export type FleetPreset = keyof typeof PRESET_PROMPTS;

export interface FleetChatMessage {
  id: string;
  role: 'user' | 'assistant';
  text: string;
  sources?: string[];
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

export function useFleetChat() {
  const [messages, setMessages] = useState<FleetChatMessage[]>(loadMessages);
  const [preset, setPreset] = useState<FleetPreset>('ssdnodes-health');
  const [loading, setLoading] = useState(false);
  const [loadingPhase, setLoadingPhase] = useState<'collect' | 'infer' | null>(null);
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

      const inferTimer = window.setTimeout(() => setLoadingPhase('infer'), 12_000);

      try {
        const res = await fetch('/api/fleet/chat', {
          method: 'POST',
          credentials: 'same-origin',
          signal: controller.signal,
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ message: trimmed, preset: presetId }),
        });

        if (res.status === 404) {
          setError('Sessão expirada — peça ao operador um novo link de acesso.');
          return;
        }
        if (res.status === 429) {
          setError('Limite de requisições — aguarde cerca de 1 minuto.');
          return;
        }
        if (!res.ok) {
          setError(
            res.status === 502
              ? 'Gateway ou modelo indisponível — tente novamente em instantes.'
              : `Erro HTTP ${res.status}`,
          );
          return;
        }

        const data = (await res.json()) as ChatResponse;
        setMessages((m) => [
          ...m,
          {
            id: newId(),
            role: 'assistant',
            text: data.reply.trim(),
            sources: data.sources,
            latencyMs: data.latency_ms,
            at: Date.now(),
          },
        ]);
      } catch (e) {
        if (controller.signal.aborted) {
          setError('Consulta cancelada.');
        } else {
          setError(e instanceof Error ? e.message : 'Falha na consulta');
        }
      } finally {
        window.clearTimeout(inferTimer);
        if (timerRef.current) {
          clearInterval(timerRef.current);
          timerRef.current = null;
        }
        setLoading(false);
        setLoadingPhase(null);
        abortRef.current = null;
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
    elapsedSec,
    error,
    send,
    cancel,
    clearHistory,
  };
}
