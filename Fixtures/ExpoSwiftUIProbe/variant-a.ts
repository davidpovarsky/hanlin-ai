import React from 'react';
import { AppRegistry } from 'react-native';
import App from './App';

function RootA() {
  return React.createElement(App, { variant: 'A' });
}

AppRegistry.registerComponent('main', () => RootA);
AppRegistry.registerComponent('ExpoSwiftUIProbe', () => RootA);
