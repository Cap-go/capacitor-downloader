import { defineConfig, loadEnv } from 'vite';

export default defineConfig(({ mode }) => {
  const env = loadEnv(mode, process.cwd(), '');
  return {
    server: {
      open: true,
    },
    build: {
      outDir: 'dist',
      emptyOutDir: true,
    },
    define: {
      'import.meta.env.VITE_CAPGO_MAESTRO_BUILD': JSON.stringify(env.VITE_CAPGO_MAESTRO_BUILD ?? ''),
      'import.meta.env.VITE_CAPGO_SERVER_URL': JSON.stringify(env.VITE_CAPGO_SERVER_URL ?? ''),
    },
  };
});
