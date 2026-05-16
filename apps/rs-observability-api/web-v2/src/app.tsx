import './index.css'
import { useEffect } from 'preact/hooks'
import originalJs from './original_script.js?raw'
import { OriginalMain } from './OriginalMain'

export function App() {
  useEffect(() => {
    // Executar o script antigo no contexto global para manter funcionando provisoriamente
    const script = document.createElement('script');
    script.innerHTML = originalJs;
    document.body.appendChild(script);

    return () => {
      document.body.removeChild(script);
    };
  }, []);

  return (
    <OriginalMain />
  )
}
