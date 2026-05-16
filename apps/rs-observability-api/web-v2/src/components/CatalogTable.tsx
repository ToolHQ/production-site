import type { CatalogData, ReportsData, SnapshotSummary } from '../types/api';
import { tableStatusClass, formatBytes } from '../utils/format';

// ────────────────────────────────────────────────────────────
// CatalogRow (linha da tabela)
// ────────────────────────────────────────────────────────────

interface CatalogRowProps {
  app: CatalogData['apps'][number];
}

function CatalogRow({ app }: CatalogRowProps) {
  const stack = [app.language ?? 'unknown', app.framework ?? ''].filter(Boolean).join(' · ');
  return (
    <tr>
      <td data-label="App">
        <strong>{app.name}</strong>
        <small>{app.description ?? app.framework ?? 'No description'}</small>
      </td>
      <td data-label="Stack">{stack}</td>
      <td data-label="Deploy Path">
        <strong>{app.deploy_script ?? 'manual / missing'}</strong>
        <small>{app.exposed_port ? `port ${app.exposed_port}` : (app.readiness_missing ?? 'path available')}</small>
      </td>
      <td data-label="Readiness">
        <span class={`table-status ${tableStatusClass(app.deploy_readiness)}`}>
          {app.deploy_readiness ?? 'unknown'}
        </span>
      </td>
    </tr>
  );
}

// ────────────────────────────────────────────────────────────
// CatalogTable (seção completa)
// ────────────────────────────────────────────────────────────

interface CatalogTableProps {
  catalog: CatalogData | null;
  summary: SnapshotSummary | null;
}

export function CatalogTable({ catalog, summary }: CatalogTableProps) {
  const apps = (catalog?.apps ?? [])
    .slice()
    .sort((a, b) => {
      const score: Record<string, number> = { deployable: 0, partial: 1, wip: 2 };
      return (score[a.deploy_readiness] ?? 3) - (score[b.deploy_readiness] ?? 3) || a.name.localeCompare(b.name);
    })
    .slice(0, 8);

  const deployableMeta = summary
    ? `${summary.deployable_app_count ?? 0} deployable · ${summary.missing_deploy_script_count ?? 0} without deploy path · ${summary.undocumented_count ?? 0} undocumented`
    : 'Waiting for catalog classification...';

  return (
    <section>
      <div class="section-head">
        <div>
          <div class="section-title">Deployable Surface</div>
          <p id="deployable-meta">{deployableMeta}</p>
        </div>
      </div>
      <div class="table-shell">
        <table>
          <thead>
            <tr>
              <th>App</th>
              <th>Stack</th>
              <th>Deploy Path</th>
              <th>Readiness</th>
            </tr>
          </thead>
          <tbody id="apps-body">
            {apps.length > 0 ? (
              apps.map((app) => <CatalogRow key={app.name} app={app} />)
            ) : (
              <tr>
                <td colSpan={4}>{catalog === null ? 'Loading catalog...' : 'No cataloged apps found.'}</td>
              </tr>
            )}
          </tbody>
        </table>
      </div>
    </section>
  );
}

// ────────────────────────────────────────────────────────────
// ArtifactList
// ────────────────────────────────────────────────────────────

interface ArtifactListProps {
  reports: ReportsData | null;
}

export function ArtifactList({ reports }: ArtifactListProps) {
  const artifacts = (reports?.artifacts ?? []).slice(0, 8);

  return (
    <div class="artifact-list" id="artifact-list">
      {artifacts.length > 0 ? (
        artifacts.map((artifact) => (
          <article class="artifact" key={artifact.id}>
            <div class="artifact-meta">
              <div>
                <div class="artifact-kind">{artifact.kind}</div>
                <strong>
                  <a href={artifact.href} target="_blank" rel="noreferrer">
                    {artifact.label}
                  </a>
                </strong>
              </div>
              <small>{formatBytes(artifact.size_bytes)}</small>
            </div>
            <p>Artifact id: {artifact.id}</p>
          </article>
        ))
      ) : (
        <div class="artifact">
          <p>{reports === null ? 'Loading artifact index...' : 'No report artifacts were bundled into this image.'}</p>
        </div>
      )}
    </div>
  );
}
