import type { CapacitorConfig } from '@capacitor/cli';

import pkg from './package.json';

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
      autoUpdate: true,
      autoSplashscreen: false,
      directUpdate: 'always',
      version: pkg.version,
    },
  },
};

export default config;
