import { useEffect, useRef, useState } from 'preact/hooks';
import { useDnorShell } from '../context/DnorShellContext';
import { useFleetCopilot } from '../context/FleetCopilotContext';
import {
  PRESET_PROMPTS,
  useFleetChat,
  type FleetPreset,
} from '../hooks/useFleetChat';
import { SSDNODES_HOSTNAME, FLEET_CHAT_HOSTS } from '../constants/fleetHosts';
import { useCopilotStatus } from '../hooks/useCopilotStatus';
import { fleetModelLabel } from '../utils/fleetModelLabel';

const PRESETS: { id: FleetPreset; icon: string; title: string; hint: string }[] = [
  {
    id: 'ssdnodes-overview',
    icon: '📊',
    title: 'Visão geral',
    hint: `Resumo rápido disco/memória/carga (${SSDNODES_HOSTNAME})`,
  },
  {
    id: 'ssdnodes-health',
    icon: '💾',
    title: 'Disco & memória',
    hint: `Host ${SSDNODES_HOSTNAME} — df, free, load`,
  },
  {
    id: 'ssdnodes-k8s',
    icon: '☸️',
    title: 'Pods & ingress',
    hint: `Cluster K8s local (${SSDNODES_HOSTNAME})`,
  },
  {
    id: 'ssdnodes-ssh',
    icon: '🔐',
    title: 'SSH 24h',
    hint: 'Tentativas recentes / fail2ban',
  },
];

function formatTime(ms: number) {
  return new Date(ms).toLocaleTimeString(undefined, {
    hour: '2-digit',
    minute: '2-digit',
  });
}

function formatLatency(ms?: number) {
  if (!ms) return null;
  if (ms < 1000) return `${ms}ms`;
  return `${(ms / 1000).toFixed(1)}s`;
}

function fleetLoadingMessage(
  phase: 'collect' | 'infer' | null,
  elapsedSec: number,
  host: string,
): string {
  if (phase === 'collect') {
    return elapsedSec >= 10
      ? `Coletando contexto da fleet (${elapsedSec}s)…`
      : 'Coletando métricas e contexto…';
  }
  if (elapsedSec >= 60) {
    return `Modelo local inferindo (${elapsedSec}s — pode levar até ~3 min)…`;
  }
  if (elapsedSec >= 30) {
    return `Gemma 3 em ${host} (${elapsedSec}s — normal levar 1–2 min)…`;
  }
  if (elapsedSec >= 10) {
    return `Consultando Gemma 3 em ${host} (${elapsedSec}s)…`;
  }
  return `Consultando Gemma 3 em ${host}…`;
}

function copyThreadText(messages: { role: string; text: string; at: number }[]) {
  return messages
    .map((m) => {
      const who = m.role === 'user' ? 'Operador' : 'Copilot';
      const when = new Date(m.at).toLocaleString();
      return `[${when}] ${who}:\n${m.text}`;
    })
    .join('\n\n');
}

function sourceLabel(path: string) {
  return path.replace(/^\/?ops\//, '').replace(/ \(error\)$/, '');
}

export function FleetCopilotPage() {
  const { setView } = useDnorShell();
  const { session, loading: sessionLoading, logout, refresh } = useFleetCopilot();
  const {
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
  } = useFleetChat();
  const bottomRef = useRef<HTMLDivElement>(null);
  const inputRef = useRef<HTMLInputElement>(null);
  const [focusHost, setFocusHost] = useState('');
  const copilotStatus = useCopilotStatus(session.authenticated, messages.length);
  const [copyHint, setCopyHint] = useState<string | null>(null);
  const [loginCopyHint, setLoginCopyHint] = useState<string | null>(null);

  useEffect(() => {
    bottomRef.current?.scrollIntoView({ behavior: 'smooth', block: 'end' });
  }, [messages, loading, streamText]);

  if (sessionLoading) {
    return (
      <section class="fleet-copilot-page" aria-busy="true" aria-label="Fleet Copilot">
        <header class="fleet-copilot-hero fleet-copilot-hero--stable">
          <div class="fleet-copilot-hero__copy">
            <p class="fleet-copilot-hero__kicker">Assistente de operações</p>
            <h1 class="fleet-copilot-hero__title">Fleet Copilot</h1>
          </div>
        </header>
        <div class="fleet-copilot-layout fleet-copilot-layout--loading">
          <aside class="fleet-copilot-sidebar fleet-copilot-skeleton-sidebar" aria-hidden="true" />
          <div class="fleet-copilot-chat">
            <div class="fleet-copilot-thread fleet-copilot-skeleton-thread" aria-hidden="true" />
          </div>
        </div>
      </section>
    );
  }

  if (!session.enabled) {
    return (
      <section class="fleet-copilot-page" aria-label="Fleet Copilot">
        <div class="fleet-copilot-locked-card">
          <h2>Fleet Copilot indisponível</h2>
          <p>
            O proxy Fleet Copilot não está habilitado neste deployment (
            <code>FLEET_COPILOT_ENABLED</code>).
          </p>
          <button type="button" class="fleet-copilot-secondary-btn" onClick={() => setView('nodes')}>
            Voltar ao Node Fleet
          </button>
        </div>
      </section>
    );
  }

  return (
    <section class="fleet-copilot-page" aria-label="Fleet Copilot">
      <header class="fleet-copilot-hero">
        <div class="fleet-copilot-hero__copy">
          <p class="fleet-copilot-hero__kicker">Assistente de operações</p>
          <h1 class="fleet-copilot-hero__title">Fleet Copilot</h1>
          <p class="fleet-copilot-hero__subtitle">
            Assistente read-only para sua fleet — respostas instantâneas em métricas conhecidas
            ou inferência Gemma&nbsp;3 local. Contexto de conversa mantido na sessão.
          </p>
        </div>
        <div class="fleet-copilot-hero__meta">
          <span class="fleet-copilot-pill fleet-copilot-pill--amber">Read-only</span>
          <span class="fleet-copilot-pill">Gemma 3 · 4B</span>
          {session.authenticated && (
            <button type="button" class="fleet-copilot-link-btn" onClick={() => void logout()}>
              Sair
            </button>
          )}
        </div>
      </header>

      <div class="fleet-copilot-banner" role="note">
        <span class="fleet-copilot-banner__icon" aria-hidden="true">
          ⚠
        </span>
        <p>
          Assistente read-only. <strong>Não executa remediação.</strong> Verifique as fontes antes
          de agir em produção.
        </p>
      </div>

      {!session.authenticated ? (
        <div class="fleet-copilot-locked-card">
          <div class="fleet-copilot-locked-card__icon" aria-hidden="true">
            🔒
          </div>
          <h2>Sessão necessária</h2>
          <p>
            O Fleet Copilot exige autenticação de operador. Peça ao admin o link de acesso
            (cookie válido por 8&nbsp;h após login).
          </p>
          <p class="fleet-copilot-locked-card__hint">
            Abra o link de operador enviado pelo admin (rota{' '}
            <code>/fleet-copilot?key=…</code>). Cookie válido por 8&nbsp;h.
          </p>
          <p class="fleet-copilot-locked-card__hint">
            Depois do login você volta aqui em <code>#fleet-copilot</code> automaticamente.
          </p>
          <div class="fleet-copilot-locked-card__actions">
            <button
              type="button"
              class="fleet-copilot-secondary-btn"
              onClick={() => {
                const url = `${window.location.origin}/#fleet-copilot`;
                void navigator.clipboard.writeText(url).then(() => {
                  setLoginCopyHint('Link copiado');
                  setTimeout(() => setLoginCopyHint(null), 2500);
                });
              }}
            >
              {loginCopyHint ?? 'Copiar link desta view'}
            </button>
            <button type="button" class="fleet-copilot-secondary-btn" onClick={() => void refresh()}>
              Verificar sessão
            </button>
            <button type="button" class="fleet-copilot-secondary-btn" onClick={() => setView('nodes')}>
              Ver Node Fleet
            </button>
          </div>
        </div>
      ) : (
        <div class="fleet-copilot-layout">
          <aside class="fleet-copilot-sidebar">
            <h2 class="fleet-copilot-sidebar__title">Consultas rápidas</h2>
            <div class="fleet-copilot-starters">
              {PRESETS.map((p) => (
                <button
                  type="button"
                  key={p.id}
                  class={`fleet-copilot-starter${preset === p.id ? ' fleet-copilot-starter--active' : ''}`}
                  disabled={loading}
                  onClick={() => {
                    setPreset(p.id);
                    void send(PRESET_PROMPTS[p.id], p.id);
                  }}
                >
                  <span class="fleet-copilot-starter__icon">{p.icon}</span>
                  <span class="fleet-copilot-starter__body">
                    <strong>{p.title}</strong>
                    <span>{p.hint}</span>
                  </span>
                </button>
              ))}
            </div>
            <label class="fleet-copilot-host-select">
              <span>Foco no nó</span>
              <select
                value={focusHost}
                disabled={loading}
                onChange={(e) => setFocusHost((e.target as HTMLSelectElement).value)}
                aria-label="Selecionar nó da fleet"
              >
                <option value="">Todos / inferir da pergunta</option>
                {FLEET_CHAT_HOSTS.map((h) => (
                  <option key={h.id} value={h.id}>
                    {h.label}
                  </option>
                ))}
              </select>
            </label>
            <div class="fleet-copilot-sidebar__foot">
              {copilotStatus && (
                <p class="fleet-copilot-quota" role="status">
                  Consultas: {copilotStatus.rate_limit_remaining}/{copilotStatus.rate_limit_max}{' '}
                  por min
                  {!copilotStatus.gateway_reachable && ' · gateway offline'}
                </p>
              )}
              <button
                type="button"
                class="fleet-copilot-link-btn"
                disabled={messages.length === 0}
                onClick={() => {
                  const text = copyThreadText(messages);
                  void navigator.clipboard.writeText(text).then(() => {
                    setCopyHint('Copiado');
                    setTimeout(() => setCopyHint(null), 2000);
                  });
                }}
              >
                {copyHint ?? 'Copiar thread'}
              </button>
              <button
                type="button"
                class="fleet-copilot-link-btn"
                disabled={messages.length === 0}
                onClick={clearHistory}
              >
                Limpar histórico
              </button>
              <details class="fleet-copilot-help">
                <summary>Como funciona</summary>
                <p>
                  Coleta read-only via gateway (:18443), contexto JSON compactado e inferência Gemma
                  3 local em {SSDNODES_HOSTNAME}. Sem execução de comandos a partir do chat.
                </p>
              </details>
            </div>
          </aside>

          <div class="fleet-copilot-chat">
            <div class="fleet-copilot-thread" aria-live="polite">
              {messages.length === 0 && !loading && (
                <div class="fleet-copilot-empty">
                  <p>Escolha uma consulta rápida ou faça uma pergunta sobre os dados coletados.</p>
                  <p class="fleet-copilot-empty__note">
                    Respostas rápidas para consultas estruturadas; perguntas abertas levam ~1–2&nbsp;min
                    (Gemma em {SSDNODES_HOSTNAME}). Você pode corrigir o Copilot na mesma thread.
                  </p>
                </div>
              )}

              {messages.map((msg) => (
                <article
                  key={msg.id}
                  class={`fleet-copilot-bubble fleet-copilot-bubble--${msg.role}`}
                >
                  <header class="fleet-copilot-bubble__head">
                    <span>{msg.role === 'user' ? 'Você' : 'Copilot'}</span>
                    <time dateTime={new Date(msg.at).toISOString()}>{formatTime(msg.at)}</time>
                    {msg.latencyMs != null && (
                      <span class="fleet-copilot-bubble__latency">
                        {formatLatency(msg.latencyMs)}
                      </span>
                    )}
                    {msg.model && msg.role === 'assistant' && (
                      <span class="fleet-copilot-bubble__model" title={`Motor: ${msg.model}`}>
                        {fleetModelLabel(msg.model)}
                      </span>
                    )}
                  </header>
                  <p class="fleet-copilot-bubble__text">{msg.text}</p>
                  {msg.sources && msg.sources.length > 0 && (
                    <div class="fleet-copilot-source-row">
                      {msg.sources.map((s) => (
                        <span key={s} class="fleet-copilot-source-pill" title={s}>
                          {sourceLabel(s)}
                        </span>
                      ))}
                    </div>
                  )}
                </article>
              ))}

              {loading && (
                <article
                  class={`fleet-copilot-bubble fleet-copilot-bubble--assistant fleet-copilot-bubble--pending${streamText ? ' fleet-copilot-bubble--streaming' : ''}`}
                >
                  <header class="fleet-copilot-bubble__head">
                    <span>Copilot</span>
                    <span class="fleet-copilot-bubble__latency">{elapsedSec}s</span>
                  </header>
                  {streamText ? (
                    <p class="fleet-copilot-bubble__text fleet-copilot-bubble__text--stream">
                      {streamText}
                      <span class="fleet-copilot-caret" aria-hidden="true" />
                    </p>
                  ) : (
                    <>
                      <div
                        class="fleet-copilot-progress"
                        role="progressbar"
                        aria-valuetext={fleetLoadingMessage(loadingPhase, elapsedSec, SSDNODES_HOSTNAME)}
                      >
                        <div class="fleet-copilot-progress__bar" />
                      </div>
                      <p class="fleet-copilot-typing">
                        {fleetLoadingMessage(loadingPhase, elapsedSec, SSDNODES_HOSTNAME)}
                        <span class="fleet-copilot-dots" aria-hidden="true">
                          <span />
                          <span />
                          <span />
                        </span>
                      </p>
                    </>
                  )}
                  <button type="button" class="fleet-copilot-link-btn" onClick={cancel}>
                    Cancelar
                  </button>
                </article>
              )}
              <div ref={bottomRef} />
            </div>

            <form
              class="fleet-copilot-composer"
              aria-busy={loading}
              onSubmit={(e) => {
                e.preventDefault();
                const value = inputRef.current?.value ?? '';
                if (inputRef.current) inputRef.current.value = '';
                let msg = value.trim();
                if (focusHost && !msg.toLowerCase().includes(focusHost.toLowerCase())) {
                  msg = `${msg} (${focusHost})`.trim();
                }
                if (msg) void send(msg, preset);
              }}
            >
              <input
                ref={inputRef}
                type="text"
                placeholder="Pergunta sobre os dados coletados…"
                disabled={loading}
                aria-label="Mensagem"
              />
              <button type="submit" disabled={loading} aria-disabled={loading}>
                Enviar
              </button>
            </form>
            <div class="fleet-copilot-host-chips" aria-label="Inserir host na pergunta">
              {FLEET_CHAT_HOSTS.map((h) => (
                <button
                  type="button"
                  key={h.id}
                  class="fleet-copilot-host-chip"
                  disabled={loading}
                  title={h.label}
                  onClick={() => {
                    const el = inputRef.current;
                    if (!el) return;
                    const prefix = `@${h.id} `;
                    if (!el.value.includes(h.id)) {
                      el.value = `${prefix}${el.value}`.trimStart();
                    }
                    el.focus();
                  }}
                >
                  @{h.id.split('-')[0]}
                </button>
              ))}
            </div>

            {error && <p class="fleet-copilot-error">{error}</p>}
          </div>
        </div>
      )}
    </section>
  );
}
