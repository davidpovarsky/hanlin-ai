import React from 'react';
import { AppRegistry } from 'react-native';
import App from './App';

function RootB() {
  return React.createElement(App, { variant: 'B' });
}

AppRegistry.registerComponent('main', () => RootB);
AppRegistry.registerComponent('ExpoSwiftUIProbe', () => RootB);
