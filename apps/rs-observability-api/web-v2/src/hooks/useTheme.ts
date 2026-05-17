import { useEffect, useState } from 'preact/hooks';

export type ThemePreference = 'auto' | 'light' | 'dark';

export function useTheme() {
  const [theme, setTheme] = useState<ThemePreference>(() => {
    const saved = localStorage.getItem('theme-preference') as ThemePreference | null;
    return saved || 'light';
  });

  const [isDark, setIsDark] = useState(false);

  // Initialize and handle theme changes
  useEffect(() => {
    const updateTheme = () => {
      const systemDark = window.matchMedia('(prefers-color-scheme: dark)').matches;
      const shouldBeDark = theme === 'dark' || (theme === 'auto' && systemDark);
      
      if (shouldBeDark) {
        document.documentElement.classList.add('dark');
        setIsDark(true);
      } else {
        document.documentElement.classList.remove('dark');
        setIsDark(false);
      }
    };

    updateTheme();

    // Listen to system theme changes
    const mediaQuery = window.matchMedia('(prefers-color-scheme: dark)');
    mediaQuery.addEventListener('change', updateTheme);
    return () => mediaQuery.removeEventListener('change', updateTheme);
  }, [theme]);

  // Save preference to localStorage
  useEffect(() => {
    localStorage.setItem('theme-preference', theme);
  }, [theme]);

  const setThemePreference = (newTheme: ThemePreference) => {
    setTheme(newTheme);
  };

  return { theme, isDark, setThemePreference };
}
