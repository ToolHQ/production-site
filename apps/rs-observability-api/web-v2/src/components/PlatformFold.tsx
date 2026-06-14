import type { ComponentChildren } from 'preact';

interface PlatformFoldProps {
  children: ComponentChildren;
  panelCount: number;
}

export function PlatformFold({ children, panelCount }: PlatformFoldProps) {
  return (
    <details class="dnor-platform-fold" id="dnor-platform">
      <summary class="dnor-platform-fold__summary">
        <span class="dnor-platform-fold__title">Plataforma e storage</span>
        <span class="dnor-platform-fold__hint">
          Longhorn, CronJobs, certificados, ingress, workloads e namespaces
        </span>
        <span class="panel-tag dnor-platform-fold__tag">{panelCount} painéis</span>
      </summary>
      <div class="dnor-platform-fold__body">{children}</div>
    </details>
  );
}
