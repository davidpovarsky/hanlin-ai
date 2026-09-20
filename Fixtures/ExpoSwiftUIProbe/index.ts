import React from 'react';
import { AppRegistry } from 'react-native';
import App from './App';

declare const __VARIANT__: 'A' | 'B';
const variant: 'A' | 'B' = typeof __VARIANT__ !== 'undefined' ? __VARIANT__ : 'A';

function Root() {
  return React.createElement(App, { variant });
}

AppRegistry.registerComponent('main', () => Root);
AppRegistry.registerComponent('ExpoSwiftUIProbe', () => Root);
