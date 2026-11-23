// Public JavaScript exports of HanlinScriptWidgetRuntime.swift.
// Original widget component declarations are generated from the upstream catalog.
type ScriptWidgetJSON = null | boolean | number | string | ScriptWidgetJSON[] | {[key:string]:ScriptWidgetJSON};
interface ScriptWidgetHTTPOptions {
  headers?: Record<string,string>;
  body?: string | Record<string,ScriptWidgetJSON>;
  timeoutInterval?: number;
  responseType?: "base64" | "text";
}
declare const $storage: {
  get(key:string): ScriptWidgetJSON | undefined;
  set(key:string,value:ScriptWidgetJSON):boolean;
  remove(key:string):boolean;
  getString(key:string):string;
  setString(key:string,value:string):boolean;
  getJSON(key:string):Record<string,ScriptWidgetJSON>;
  setJSON(key:string,value:Record<string,ScriptWidgetJSON>):boolean;
  compareAndSetString(key:string,expected:string,value:string):boolean;
  compareAndSetJSON(key:string,expected:Record<string,ScriptWidgetJSON>,value:Record<string,ScriptWidgetJSON>):boolean;
  keys():string[];
  clear():boolean;
};
declare const $file: {
  exists(path:string):boolean;
  read(path:string):string;
  readJSON(path:string):Record<string,ScriptWidgetJSON>;
};
declare function $import(path:string):boolean;
declare function $render(element:JSX.Element):void;
declare function $error(message:string):void;
declare function $getenv(key:string):ScriptWidgetJSON;
declare const $widget:Readonly<Record<string,ScriptWidgetJSON>>;
declare function $fetch(url:string,options?:ScriptWidgetHTTPOptions):Promise<string>;
declare const fetch:typeof $fetch;
declare const $http: {
  get:typeof $fetch;
  getResponse(url:string,options?:ScriptWidgetHTTPOptions):Promise<{body:string;status:number;headers:Record<string,string>}>;
  post:typeof $fetch;
  put:typeof $fetch;
  patch:typeof $fetch;
  delete:typeof $fetch;
};
declare const console:{log(...values:unknown[]):void;warn(...values:unknown[]):void;error(error:unknown):void};
declare const $console:typeof console;
