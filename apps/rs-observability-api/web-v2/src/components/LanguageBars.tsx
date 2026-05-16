import type { SnapshotSummary } from '../types/api';

interface LanguageBarsProps {
  summary: SnapshotSummary | null;
}

export function LanguageBars({ summary }: LanguageBarsProps) {
  const languages = summary?.app_languages ?? [];
  const max = Math.max(...languages.map((item) => item.count), 1);

  return (
    <div class="language-bars" id="language-bars">
      {languages.length > 0 ? (
        languages.map((item) => (
          <div class="language-row" key={item.language}>
            <div class="language-head">
              <span>{item.language}</span>
              <strong>{item.count}</strong>
            </div>
            <div class="language-track">
              <div class="language-fill" style={{ width: `${(item.count / max) * 100}%` }} />
            </div>
          </div>
        ))
      ) : (
        <div class="language-row">
          <div class="language-head">
            <span>{summary === null ? 'Loading' : 'No language data'}</span>
            <strong>--</strong>
          </div>
          <div class="language-track">
            <div class="language-fill" style={{ width: '0%' }} />
          </div>
        </div>
      )}
    </div>
  );
}
