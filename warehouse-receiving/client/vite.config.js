import { defineConfig } from 'vite';
import vue from '@vitejs/plugin-vue';

// Dev: proxy /api sang Express (port 3000) de khong bi CORS
export default defineConfig({
  plugins: [vue()],
  server: { port: 5173, proxy: {
      '/api': { target: process.env.API_URL || 'http://localhost:3000', changeOrigin: true },
      '/uploads': { target: process.env.API_URL || 'http://localhost:3000', changeOrigin: true },
    } },
});
