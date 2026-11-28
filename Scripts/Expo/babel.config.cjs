module.exports = {
  presets: [['babel-preset-expo', { worklets: false }]],
  plugins: [
    '@nativescript/react-native/babel-plugin',
    ['react-native-worklets/plugin', { strictGlobal: true }],
  ],
};
