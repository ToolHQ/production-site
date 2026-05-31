import { useFleetCopilot } from '../context/FleetCopilotContext';
import { useDnorShell } from '../context/DnorShellContext';

export function FleetCopilotTeaser() {
  const { session } = useFleetCopilot();
  const { setView } = useDnorShell();

  if (!session.enabled) return null;

  return (
    <aside class="fleet-copilot-teaser" aria-label="Fleet Copilot">
      <div class="fleet-copilot-teaser__glow" aria-hidden="true" />
      <div class="fleet-copilot-teaser__content">
        <div>
          <p class="fleet-copilot-teaser__kicker">New · Read-only AI</p>
          <h3 class="fleet-copilot-teaser__title">Fleet Copilot</h3>
          <p class="fleet-copilot-teaser__copy">
            Pergunte sobre disco, pods e SSH no SSDNodes — respostas citando fontes ops reais.
          </p>
        </div>
        <button
          type="button"
          class="fleet-copilot-teaser__cta"
          onClick={() => setView('fleet-copilot')}
        >
          {session.authenticated ? 'Abrir Copilot' : 'Entrar no Copilot'}
        </button>
      </div>
    </aside>
  );
}
