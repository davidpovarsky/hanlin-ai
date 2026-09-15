// Hanlin NativeScript Config-as-JSON ESM Provider
// Implements runtime resolution of the active MiniApp's package.json configuration
// without bundling @nativescript/core into the MiniApp or compiling raw JSON as JS.
let config = {};
try {
  if (typeof global !== 'undefined' && global.require) {
    config = global.require('~/package.json');
  }
} catch (e) {
  try {
    if (typeof global !== 'undefined' && global.__hanlinAppConfig) {
      config = global.__hanlinAppConfig;
    }
  } catch (_) {}
}
export default config;
