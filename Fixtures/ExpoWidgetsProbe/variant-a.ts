import React from 'react';
import {AppRegistry} from 'react-native';
import App from './App';
AppRegistry.registerComponent('main', () => () => React.createElement(App, {variant: 'A'}));
