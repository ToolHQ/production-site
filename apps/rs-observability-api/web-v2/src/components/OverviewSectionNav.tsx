const SECTIONS = [
  { id: 'dnor-nodes', label: 'Nós' },
  { id: 'dnor-metrics', label: 'Pressão' },
  { id: 'dnor-platform', label: 'Plataforma' },
  { id: 'dnor-incidents', label: 'Incidentes' },
  { id: 'dnor-services', label: 'Serviços' },
  { id: 'dnor-catalog', label: 'Catálogo' },
] as const;

export function OverviewSectionNav() {
  return (
    <nav class="dnor-overview-nav" aria-label="Seções do overview">
      {SECTIONS.map((s) => (
        <a key={s.id} class="dnor-overview-nav__link" href={`#${s.id}`}>
          {s.label}
        </a>
      ))}
    </nav>
  );
}
