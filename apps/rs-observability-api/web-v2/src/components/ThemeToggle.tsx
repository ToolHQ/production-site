import { useTheme } from '../hooks/useTheme';
import styles from './ThemeToggle.module.css';

export function ThemeToggle({ compact = false }: { compact?: boolean }) {
  const { theme, setThemePreference } = useTheme();

  const handleToggle = () => {
    if (theme === 'auto') {
      setThemePreference('dark');
    } else if (theme === 'dark') {
      setThemePreference('light');
    } else {
      setThemePreference('auto');
    }
  };

  const getIcon = () => {
    switch (theme) {
      case 'dark':
        return '🌙';
      case 'light':
        return '☀️';
      default:
        return '🔄';
    }
  };

  const getLabel = () => {
    switch (theme) {
      case 'dark':
        return 'Dark Mode';
      case 'light':
        return 'Light Mode';
      default:
        return 'Auto (System)';
    }
  };

  return (
    <button
      class={`${styles.themeToggle}${compact ? ` ${styles.themeToggleCompact}` : ''}`}
      onClick={handleToggle}
      title={`Tema: ${getLabel()} (clique para alternar)`}
      aria-label={`Alternar tema. Atual: ${getLabel()}`}
    >
      <span class={styles.icon}>{getIcon()}</span>
      {!compact && <span class={styles.label}>{getLabel()}</span>}
    </button>
  );
}
