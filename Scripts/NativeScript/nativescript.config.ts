import type { NativeScriptConfig } from '@nativescript/core';

export default {
  id: 'com.hanlin.nativescript.fixture',
  appPath: 'Fixtures/Source',
  appResourcesPath: 'Fixtures/App_Resources',
  bundler: 'vite',
  bundlerConfigPath: 'vite.config.mts'
} satisfies NativeScriptConfig;
