import React from 'react';
import { AppRegistry } from 'react-native';
import App from './App';

function Root() {
  return React.createElement(App, { variant: 'A' });
}

AppRegistry.registerComponent('main', () => Root);
AppRegistry.registerComponent('ExpoNativeAPIProbe', () => Root);
