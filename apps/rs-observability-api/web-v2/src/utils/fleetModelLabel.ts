/** Rótulo legível do motor de resposta (T-340-74). */
export function fleetModelLabel(model: string): string {
  const m = model.toLowerCase();
  if (m.includes('structured') || m.includes('instant')) return 'Instant';
  if (m.includes('gemma')) return 'Gemma';
  if (m.includes('manifest')) return 'Manifest';
  if (m === 'meta' || m.includes('meta')) return 'Meta';
  return model.replace(/^fleet-/, '').replace(/-/g, ' ');
}
