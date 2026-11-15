import { defineConfig, loadEnv, type Plugin } from 'vite';

function stripCrossoriginForCapacitor(): Plugin {
  return {
    name: 'strip-crossorigin-for-capacitor',
    transformIndexHtml(html) {
      return html.replace(/ crossorigin/g, '');
    },
  };
}

export default defineConfig(({ mode }) => {
  const env = loadEnv(mode, process.cwd(), '');
  return {
    plugins: [stripCrossoriginForCapacitor()],
    server: {
      open: true,
    },
    build: {
      outDir: 'dist',
      emptyOutDir: true,
      // GitHub's API 30 emulator WebView is Chrome 83; avoid modern syntax (for example ||=).
      target: 'chrome80',
      // Capacitor WebView loads bundled assets from a non-CORS file/localhost origin;
      // Vite's default crossorigin module scripts fail to evaluate there.
      modulePreload: false,
    },
    define: {
      'import.meta.env.VITE_CAPGO_MAESTRO_BUILD': JSON.stringify(env.VITE_CAPGO_MAESTRO_BUILD ?? ''),
      'import.meta.env.VITE_CAPGO_SERVER_URL': JSON.stringify(env.VITE_CAPGO_SERVER_URL ?? ''),
    },
  };
});
