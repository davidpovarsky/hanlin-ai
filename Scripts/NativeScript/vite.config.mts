import { defineConfig, mergeConfig, type UserConfig } from 'vite';
import { typescriptConfig } from '@nativescript/vite/typescript';

export default defineConfig(({ mode }): UserConfig => {
  return mergeConfig(typescriptConfig({ mode }), {
    build: {
      emptyOutDir: true,
      sourcemap: false
    }
  });
});
