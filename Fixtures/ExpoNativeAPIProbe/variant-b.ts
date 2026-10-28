import React from 'react';
import { AppRegistry } from 'react-native';
import App from './App';

function Root() {
  return React.createElement(App, { variant: 'B' });
}

AppRegistry.registerComponent('main', () => Root);
AppRegistry.registerComponent('ExpoNativeAPIProbe', () => Root);
