import { defineConfig } from 'vite'
import preact from '@preact/preset-vite'

// https://vite.dev/config/
export default defineConfig({
  plugins: [preact()],
  build: {
    // Nomes de assets fixos para facilitar embed via include_bytes! no servidor Rust
    rollupOptions: {
      output: {
        entryFileNames: 'assets/app.js',
        chunkFileNames: 'assets/app-[hash].js',
        assetFileNames: (assetInfo) => {
          if (assetInfo.name?.endsWith('.css')) return 'assets/app.css'
          return 'assets/[name][extname]'
        },
      },
    },
  },
})
