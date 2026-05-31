import { useEffect, useRef } from 'preact/hooks';
import { useDnorShell } from '../context/DnorShellContext';
import { useFleetCopilot } from '../context/FleetCopilotContext';
import {
  PRESET_PROMPTS,
  useFleetChat,
  type FleetPreset,
} from '../hooks/useFleetChat';

const PRESETS: { id: FleetPreset; icon: string; title: string; hint: string }[] = [
  {
    id: 'ssdnodes-health',
    icon: '💾',
    title: 'Disco & memória',
    hint: 'Host SSDNodes — df, free, load',
  },
  {
    id: 'ssdnodes-k8s',
    icon: '☸️',
    title: 'Pods & ingress',
    hint: 'Cluster local no monstro',
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

function sourceLabel(path: string) {
  return path.replace(/^\/?ops\//, '').replace(/ \(error\)$/, '');
}

export function FleetCopilotPage() {
  const { setView } = useDnorShell();
  const { session, loading: sessionLoading, logout } = useFleetCopilot();
  const {
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
  } = useFleetChat();
  const bottomRef = useRef<HTMLDivElement>(null);
  const inputRef = useRef<HTMLInputElement>(null);

  useEffect(() => {
    bottomRef.current?.scrollIntoView({ behavior: 'smooth', block: 'end' });
  }, [messages, loading]);

  if (sessionLoading) {
    return (
      <section class="fleet-copilot-page">
        <div class="fleet-copilot-page__skeleton">
          <div class="fleet-copilot-skeleton fleet-copilot-skeleton--head" />
          <div class="fleet-copilot-skeleton fleet-copilot-skeleton--chat" />
        </div>
      </section>
    );
  }

  if (!session?.enabled) return null;

  return (
    <section class="fleet-copilot-page" aria-label="Fleet Copilot">
      <header class="fleet-copilot-hero">
        <div class="fleet-copilot-hero__copy">
          <p class="fleet-copilot-hero__kicker">Operations assistant</p>
          <h1 class="fleet-copilot-hero__title">Fleet Copilot</h1>
          <p class="fleet-copilot-hero__subtitle">
            Perguntas read-only sobre <strong>ssdnodes-monstro</strong> e fleet OCI — dados
            coletados via gateway seguro, resposta local Gemma&nbsp;3.
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
            Após autenticar você será redirecionado para esta página automaticamente.
          </p>
          <button type="button" class="fleet-copilot-secondary-btn" onClick={() => setView('nodes')}>
            Ver Node Fleet
          </button>
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
            <div class="fleet-copilot-sidebar__foot">
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
                  3 local no monstro. Sem execução de comandos a partir do chat.
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
                    Respostas levam ~1–2&nbsp;min (inferência CPU no monstro).
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
                <article class="fleet-copilot-bubble fleet-copilot-bubble--assistant fleet-copilot-bubble--pending">
                  <header class="fleet-copilot-bubble__head">
                    <span>Copilot</span>
                    <span class="fleet-copilot-bubble__latency">{elapsedSec}s</span>
                  </header>
                  <p class="fleet-copilot-typing">
                    {loadingPhase === 'collect'
                      ? 'Coletando métricas do SSDNodes…'
                      : 'Consultando Gemma 3 no monstro…'}
                    <span class="fleet-copilot-dots" aria-hidden="true">
                      <span />
                      <span />
                      <span />
                    </span>
                  </p>
                  <button type="button" class="fleet-copilot-link-btn" onClick={cancel}>
                    Cancelar
                  </button>
                </article>
              )}
              <div ref={bottomRef} />
            </div>

            <form
              class="fleet-copilot-composer"
              onSubmit={(e) => {
                e.preventDefault();
                const value = inputRef.current?.value ?? '';
                if (inputRef.current) inputRef.current.value = '';
                void send(value, preset);
              }}
            >
              <input
                ref={inputRef}
                type="text"
                placeholder="Pergunta sobre os dados coletados…"
                disabled={loading}
                aria-label="Mensagem"
              />
              <button type="submit" disabled={loading}>
                Enviar
              </button>
            </form>

            {error && <p class="fleet-copilot-error">{error}</p>}
          </div>
        </div>
      )}
    </section>
  );
}
