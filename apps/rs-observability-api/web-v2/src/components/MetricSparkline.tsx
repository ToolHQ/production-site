import type { TimeSeriesPoint } from '../types/api';

interface MetricSparklineProps {
  points: TimeSeriesPoint[];
  color: string;
  width?: number;
  height?: number;
}

export function MetricSparkline({ points, color, width = 220, height = 72 }: MetricSparklineProps) {
  let values = Array.isArray(points) ? points.filter((p) => Number.isFinite(p.value)) : [];

  if (!values.length) {
    return (
      <svg class="sparkline" viewBox={`0 0 ${width} ${height}`} preserveAspectRatio="none">
        <path
          d={`M0 ${height * 0.64} L${width} ${height * 0.64}`}
          stroke="rgba(22,32,43,0.12)"
          stroke-width="2"
          stroke-dasharray="4 6"
          fill="none"
        />
      </svg>
    );
  }

  if (values.length === 1) {
    values = [values[0], { ...values[0] }];
  }

  const min = Math.min(...values.map((p) => p.value));
  const max = Math.max(...values.map((p) => p.value));
  const span = max - min || 1;

  const coords = values.map((p, i) => {
    const x = values.length === 1 ? 0 : (i / (values.length - 1)) * width;
    const y = height - (((p.value - min) / span) * (height - 10) + 5);
    return [x, y] as [number, number];
  });

  const line = coords.map(([x, y]) => `${x.toFixed(2)},${y.toFixed(2)}`).join(' ');
  const area = `0,${height} ${line} ${width},${height}`;

  return (
    <svg class="sparkline" viewBox={`0 0 ${width} ${height}`} preserveAspectRatio="none">
      <polyline points={area} fill={`${color}18`} stroke="none" />
      <polyline
        points={line}
        fill="none"
        stroke={color}
        stroke-width="3"
        stroke-linecap="round"
        stroke-linejoin="round"
      />
    </svg>
  );
}
