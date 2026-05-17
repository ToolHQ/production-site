import { useEffect, useState } from 'preact/hooks';

export interface PanelLayout {
  id: string;
  x: number;
  y: number;
  w: number;
  h: number;
  order: number;
}

export interface DashboardLayoutState {
  panels: Record<string, PanelLayout>;
}

const GRID_SIZE = 16;
const DEFAULT_PANELS: PanelLayout[] = [
  { id: 'metrics', x: 0, y: 0, w: 100, h: 150, order: 1 },
  { id: 'nodes', x: 0, y: 160, w: 100, h: 200, order: 2 },
  { id: 'services', x: 0, y: 370, w: 100, h: 180, order: 3 },
  { id: 'incidents', x: 0, y: 560, w: 100, h: 150, order: 4 },
];

export function useDashboardLayout() {
  const [layout, setLayout] = useState<DashboardLayoutState>(() => {
    const saved = localStorage.getItem('dashboard-layout');
    if (saved) {
      try {
        return JSON.parse(saved);
      } catch {
        // Fallback if corrupted
      }
    }
    // Initialize with default layout
    const defaultLayout: DashboardLayoutState = {
      panels: DEFAULT_PANELS.reduce((acc, panel) => {
        acc[panel.id] = panel;
        return acc;
      }, {} as Record<string, PanelLayout>),
    };
    return defaultLayout;
  });

  // Save to localStorage with debounce
  useEffect(() => {
    const timer = setTimeout(() => {
      localStorage.setItem('dashboard-layout', JSON.stringify(layout));
    }, 300);
    return () => clearTimeout(timer);
  }, [layout]);

  const updatePanelPosition = (panelId: string, x: number, y: number) => {
    setLayout((prev) => ({
      ...prev,
      panels: {
        ...prev.panels,
        [panelId]: {
          ...prev.panels[panelId],
          x: Math.round(x / GRID_SIZE) * GRID_SIZE,
          y: Math.round(y / GRID_SIZE) * GRID_SIZE,
        },
      },
    }));
  };

  const updatePanelSize = (panelId: string, w: number, h: number) => {
    setLayout((prev) => ({
      ...prev,
      panels: {
        ...prev.panels,
        [panelId]: {
          ...prev.panels[panelId],
          w: Math.max(300, Math.round(w / GRID_SIZE) * GRID_SIZE),
          h: Math.max(200, Math.round(h / GRID_SIZE) * GRID_SIZE),
        },
      },
    }));
  };

  const updatePanelOrder = (panelId: string, order: number) => {
    setLayout((prev) => ({
      ...prev,
      panels: {
        ...prev.panels,
        [panelId]: {
          ...prev.panels[panelId],
          order,
        },
      },
    }));
  };

  const resetLayout = () => {
    const defaultLayout: DashboardLayoutState = {
      panels: DEFAULT_PANELS.reduce((acc, panel) => {
        acc[panel.id] = panel;
        return acc;
      }, {} as Record<string, PanelLayout>),
    };
    setLayout(defaultLayout);
    localStorage.removeItem('dashboard-layout');
  };

  const getPanelStyle = (panelId: string) => {
    const panel = layout.panels[panelId];
    if (!panel) return {};
    return {
      position: 'absolute' as const,
      left: `${panel.x}px`,
      top: `${panel.y}px`,
      width: `${panel.w}px`,
      height: `${panel.h}px`,
      zIndex: panel.order,
    };
  };

  return {
    layout,
    updatePanelPosition,
    updatePanelSize,
    updatePanelOrder,
    resetLayout,
    getPanelStyle,
  };
}
