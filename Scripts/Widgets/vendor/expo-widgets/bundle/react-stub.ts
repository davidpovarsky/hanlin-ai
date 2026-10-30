import type { ReactElementNode } from './jsx-runtime-stub';

export const Fragment = 'react.fragment';

export const Children = {
  toArray(children: unknown) {
    return [children]
      .flat(Infinity)
      .filter((child) => child !== undefined && child !== null && typeof child !== 'boolean');
  },
};

export const isValidElement = (value: unknown): value is ReactElementNode => {
  return value !== null && typeof value === 'object' && 'type' in value && 'props' in value;
};

// TODO(@jakex7): Make this a proper React reconciler in the future. For now, we just need a stub to allow the widget bundle to compile with @expo/ui/jetpack-compose.
type StubContext<T> = {
  Provider: string;
  Consumer: string;
  _currentValue: T;
};

export const createContext = <T>(defaultValue: T): StubContext<T> => ({
  Provider: 'react.provider',
  Consumer: 'react.consumer',
  _currentValue: defaultValue,
});

export const useContext = <T>(context: StubContext<T>): T => context._currentValue;

export const useState = (init: any) => [typeof init === 'function' ? init() : init, () => {}];
export const useRef = (val: any) => ({ current: val });
export const useCallback = (fn: any) => fn;
export const useMemo = (fn: any) => (typeof fn === 'function' ? fn() : fn);
export const useEffect = () => {};
export const useLayoutEffect = () => {};
export const createElement = (type: any, props: any, ...children: any[]) => {
  const { key, ...rest } = props ?? {};
  return {
    type,
    key: key == null ? null : String(key),
    props: {
      ...rest,
      children: children.length === 1 ? children[0] : (children.length > 0 ? children : props?.children)
    }
  };
};

const React = {
  Fragment,
  Children,
  isValidElement,
  createContext,
  useContext,
  useState,
  useRef,
  useCallback,
  useMemo,
  useEffect,
  useLayoutEffect,
  createElement,
};

export default React;
