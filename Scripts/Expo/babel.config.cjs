module.exports = {
  presets: ['@react-native/babel-preset'],
  plugins: [
    '@nativescript/react-native/babel-plugin',
    ['react-native-worklets/plugin', { strictGlobal: true }],
  ],
};
