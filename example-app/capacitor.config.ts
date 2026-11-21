import type { CapacitorConfig } from '@capacitor/cli';

import pkg from './package.json';

const isMaestroBuild = process.env.VITE_CAPGO_MAESTRO_BUILD === 'true';

const config: CapacitorConfig = {
  appId: 'app.capgo.downloader',
  appName: '@capgo/capacitor-downloader',
  webDir: 'dist',
  plugins: {
    SplashScreen: {
      launchAutoHide: true,
    },
    CapacitorUpdater: {
      appId: 'app.capgo.downloader',
      autoUpdate: !isMaestroBuild,
      autoSplashscreen: false,
      directUpdate: isMaestroBuild ? 'false' : 'always',
      version: pkg.version,
    },
  },
};

export default config;
