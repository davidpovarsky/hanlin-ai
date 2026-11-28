const { getDefaultConfig } = require('expo/metro-config');
const { mergeConfig } = require('metro-config');
const path = require('path');
const installedModulesRoot = require('fs').realpathSync(path.resolve(__dirname, 'node_modules'));

const config = {
  watchFolders: [
    installedModulesRoot,
    path.resolve(__dirname, '../../Fixtures/ExpoSwiftUIProbe'),
    path.resolve(__dirname, '../../Fixtures/ExpoNativeAPIProbe'),
    path.resolve(__dirname, '../../Fixtures/ExpoWidgetsProbe'),
    path.resolve(__dirname, '../../Packages/HanlinExpoUI'),
    path.resolve(__dirname, '../../Packages/HanlinExpoNativeAPIJS'),
  ],
  resolver: {
    nodeModulesPaths: [
      installedModulesRoot,
    ],
  },
};

module.exports = mergeConfig(getDefaultConfig(__dirname), config);
