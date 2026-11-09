import react from '@vitejs/plugin-react'
import { defineConfig } from 'vite'

// The Electron and Tauri shells both load this app: from the dev server while it runs, and from
// dist/ in a release. Relative paths let dist/ load from a file:// URL in Electron.
export default defineConfig({
  plugins: [react()],
  base: './',
  // The spec builds the 2 MB of data into the app, so its one chunk is large on purpose.
  build: { chunkSizeWarningLimit: 3000 },
  server: {
    port: 1420,
    strictPort: true,
    // The data lives in the research repository's data/ folder, outside this app.
    fs: { allow: ['.', '../../data'] },
  },
})
